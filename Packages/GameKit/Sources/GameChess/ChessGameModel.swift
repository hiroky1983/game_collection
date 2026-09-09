import Foundation
import Observation
import Core

/// チェスの対局状態。盤・指し手列・選択状態・終局・検討を管理する。
/// ルールは `ChessPosition` に委譲し、ここは UI 操作と永続化を担う（将棋の `ShogiGameModel` と同じ分担）。
@MainActor
@Observable
public final class ChessGameModel {
    public let initialFEN: String
    public private(set) var moves: [ChessMove]
    public private(set) var position: ChessPosition
    public private(set) var legalMovesCache: [ChessMove]

    // 選択状態
    public private(set) var selectedSquare: Int?
    /// プロモーション先の選択待ち（最奥段に届いたポーンの移動）。
    public private(set) var pendingPromotion: (from: Int, to: Int)?

    // 対局設定・進行
    public private(set) var phase: ChessGamePhase
    public private(set) var reviewPly: Int
    public private(set) var gameOver: Bool
    public private(set) var result: ChessResult?
    public var white: ChessPlayerKind
    public var black: ChessPlayerKind
    public var aiLevel: Int
    public private(set) var undoUsed: Bool
    public private(set) var resigned: Bool
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    private let gameID = "chess"
    private var startedAt: Date

    public init(services: GameServices? = nil) {
        self.services = services
        let snap = services?.snapshots.load(ChessSnapshot.self, for: "chess")

        let fen = snap?.initialFen ?? ChessPosition.startFEN
        var pos = ChessPosition.fromFEN(fen) ?? ChessPosition.start()
        var moveList: [ChessMove] = []
        if let snap {
            for uci in snap.moves {
                guard let m = ChessMove.fromUCI(uci) else { break }
                moveList.append(m)
                pos.make(m)
            }
        }

        self.initialFEN = fen
        self.moves = moveList
        self.position = pos
        self.legalMovesCache = pos.legalMoves()
        self.selectedSquare = nil
        self.pendingPromotion = nil
        self.phase = snap?.phase ?? .playing
        self.reviewPly = snap?.reviewPly ?? moveList.count
        // 既定は CPU 対戦（人間=白 / CPU=黒）。
        self.white = snap?.white ?? .human
        self.black = snap?.black ?? .ai
        self.aiLevel = snap?.aiLevel ?? 1
        self.startedAt = snap?.startedAt ?? Date()
        self.undoUsed = snap?.undoUsed ?? false
        self.resigned = snap?.resigned ?? false
        self.gameOver = false
        self.result = nil

        // 決着は保存していない（指し手列から導ける）ので、復元時にここで判定し直す。
        // 投了だけは盤面から導けないため、スナップショットのフラグを見る。
        if snap?.resigned == true {
            self.result = .resignation(loser: self.humanSideValue)
        } else {
            self.result = Self.detectResult(
                initialFEN: fen, moves: moveList, position: pos, legalMoves: legalMovesCache
            )
        }
        if result != nil {
            self.gameOver = true
            self.phase = .review
        }
        // 終局後の検討画面もスナップショットに残すので、再起動でその画面に戻ったとき
        // 記録行が消えないよう、保存済みの記録から作り直す。**記録し直さない**
        // （`gameDidFinish` を呼ばない）ので二重計上にはならない。
        if gameOver, let record = services?.playLog?.record(gameID: gameID) {
            self.recordResult = RecordResult(record: record, update: RecordUpdate())
        }
        // 保存された対局が無いときだけ新規対局の開始として数える（#158）。
        if snap == nil { services?.gameDidStart(gameID: gameID) }
    }

    // MARK: - 終局の判定

    /// 3回同形反復が成立する同一局面の出現回数。
    static let repetitionLimit = 3
    /// 50手ルールの半手数（両者 50 手 = 100 半手）。
    static let fiftyMoveHalfmoveLimit = 100

    /// 局面と指し手列から決着を導く。**投了以外はすべてここに集約する**ので、
    /// 着手直後でも中断からの復元でも必ず同じ結論になる。
    static func detectResult(
        initialFEN: String, moves: [ChessMove], position: ChessPosition, legalMoves: [ChessMove]
    ) -> ChessResult? {
        if legalMoves.isEmpty {
            return position.isKingInCheck(position.sideToMove)
                ? .checkmate(loser: position.sideToMove)
                : .stalemate
        }
        // 判定の順序: 詰みが先（詰んだ局面は他のどの引き分け条件よりも優先する）。
        if position.isInsufficientMaterial() { return .insufficientMaterial }
        if position.halfmoveClock >= fiftyMoveHalfmoveLimit { return .fiftyMoveRule }
        if isThreefoldRepetition(initialFEN: initialFEN, moves: moves, current: position) {
            return .threefoldRepetition
        }
        return nil
    }

    /// 3回同形反復の「同一局面」。**盤・手番・キャスリング権・実効アンパッサン標的**が
    /// 一致すれば同一とみなす（FIDE の「同じ指し手が指せること」を実装に落としたもの）。
    /// `ChessPosition` の `==` は手数と 50手計数まで見るため、繰り返しの検出には使えない。
    ///
    /// アンパッサン標的に `effectiveEnPassant()` を使うのが要点。生の `enPassant` は
    /// **取りに行けなくても 2 マス進みの直後なら必ず立つ**ため、そのまま比べると
    /// 「指せる手は全く同じなのに別の局面」と読んで反復を取り逃がす。
    static func isSamePosition(_ a: ChessPosition, _ b: ChessPosition) -> Bool {
        a.squares == b.squares && a.sideToMove == b.sideToMove
            && a.castling == b.castling
            && a.effectiveEnPassant() == b.effectiveEnPassant()
    }

    /// 現在の局面が初手からの経過で 3 回目の出現か。
    ///
    /// 状態として持たず**指し手列から毎回導く**。中断からの復元でもスナップショットに
    /// 項目を足さずに同じ判定になる。
    static func isThreefoldRepetition(
        initialFEN: String, moves: [ChessMove], current: ChessPosition
    ) -> Bool {
        // 同一局面の周期は最短でも 4 手（両者が動かした駒を戻して初めて一致する）なので、
        // 3 回目の出現には少なくとも 8 手が要る。
        guard moves.count >= (repetitionLimit - 1) * 4 else { return false }
        // 比較の相手は毎回同じなので、実効標的の算出（合法手生成を伴う）は 1 回で済ませる。
        let currentEnPassant = current.effectiveEnPassant()
        func isSameAsCurrent(_ pos: ChessPosition) -> Bool {
            guard pos.squares == current.squares, pos.sideToMove == current.sideToMove,
                  pos.castling == current.castling else { return false }
            return pos.effectiveEnPassant() == currentEnPassant
        }
        var pos = ChessPosition.fromFEN(initialFEN) ?? ChessPosition.start()
        var count = isSameAsCurrent(pos) ? 1 : 0
        for move in moves {
            pos.make(move)
            if isSameAsCurrent(pos) { count += 1 }
        }
        return count >= repetitionLimit
    }

    // MARK: - 表示用

    /// 検討中は reviewPly までの局面、対局中は最新局面を表示する。
    public var displayedPosition: ChessPosition {
        phase == .review ? positionAt(ply: reviewPly) : position
    }

    public var resultText: String? { result?.text(humanSide: humanSide) }

    /// 強調表示する直前の指し手（対局中は最新手、検討中は表示局面に至った手）。
    public var highlightedMove: ChessMove? {
        let ply = (phase == .review) ? reviewPly : moves.count
        return ply > 0 ? moves[ply - 1] : nil
    }

    /// 直前手の移動元・移動先マス（CPU の手などを色で示す用）。
    public var highlightedSquares: Set<Int> {
        guard let m = highlightedMove else { return [] }
        return [m.from, m.to]
    }

    /// 王手されている側のキングのマス（表示局面基準）。王手でなければ nil。
    ///
    /// 状態として持たず**局面から毎回導く**（将棋 #377 と同じ）。検討ナビで戻った局面でも
    /// 中断から復元した局面でも、別の復元処理なしに必ず正しく出る。
    public var checkedKingSquare: Int? {
        let pos = displayedPosition
        guard pos.isKingInCheck(pos.sideToMove) else { return nil }
        return pos.kingSquare(pos.sideToMove)
    }

    /// 「チェック」の文字を飛び出させる契機（将棋 #377 と同じ）。
    /// **実対局の着手で王手が生じるたび**に増える。検討ナビ・中断復元では増えない。
    public private(set) var checkEventID: Int = 0
    /// 直前の `checkEventID` で王手を**された**側。
    public private(set) var lastCheckedSide: ChessColor?

    /// 直前手の表記（例 "Nf3" / "e4" / "O-O"）。無ければ nil。
    public var highlightedMoveText: String? {
        guard let m = highlightedMove else { return nil }
        let ply = (phase == .review) ? reviewPly : moves.count
        let before = positionAt(ply: ply - 1)
        return ChessNotation.san(m, in: before)
    }

    /// 取られた駒（表示局面基準）。指定色が**失った**駒を価値の高い順に返す。
    public func capturedPieces(of color: ChessColor) -> [ChessPieceType] {
        let pos = displayedPosition
        var remaining: [ChessPieceType: Int] = [:]
        for piece in pos.squares {
            guard let piece, piece.color == color else { continue }
            remaining[piece.type, default: 0] += 1
        }
        // 初期配置との差分。プロモーションでポーンが増減しても負にならないよう max(0,) を取る。
        let initialCounts: [ChessPieceType: Int] = [
            .pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1,
        ]
        return ChessPieceType.allCases
            .filter { $0 != .king }
            .flatMap { type -> [ChessPieceType] in
                let lost = max(0, (initialCounts[type] ?? 0) - (remaining[type] ?? 0))
                return Array(repeating: type, count: lost)
            }
            .sorted { ChessPieceValue.base($0) > ChessPieceValue.base($1) }
    }

    /// 現在の選択から導く合法な着手先マス。
    public var legalTargets: Set<Int> {
        guard let from = selectedSquare else { return [] }
        return Set(legalMovesCache.filter { $0.from == from }.map(\.to))
    }

    // MARK: - 対局操作

    public func tapSquare(_ sq: Int) {
        // CPU の手番（思考中含む）は人間の操作を受け付けない。
        guard phase == .playing, !gameOver, pendingPromotion == nil, !isAITurn else { return }
        if selectedSquare != nil, legalTargets.contains(sq) {
            attemptMove(to: sq)
            return
        }
        if let p = position.squares[sq], p.color == position.sideToMove {
            selectedSquare = sq
        } else {
            // 駒を選んだ状態で指せないマスを叩いた = 着手の拒否。
            if selectedSquare != nil { services?.feedback.notify(.warning) }
            clearSelection()
        }
    }

    private func attemptMove(to sq: Int) {
        guard let from = selectedSquare else { return }
        let candidates = legalMovesCache.filter { $0.from == from && $0.to == sq }
        if candidates.count >= 2 {
            // プロモーション先が 4 通りあるので選ばせる。
            pendingPromotion = (from, sq)
        } else if let m = candidates.first {
            apply(m)
        }
    }

    /// 成り先の選択肢。**使う頻度の高い順**に並べる（実戦のほぼ全てがクイーン成り）。
    /// 駒種の定義順のままだと一番使う選択肢が端に来るため、並びをここで固定する。
    public static let promotionChoices: [ChessPieceType] = [.queen, .rook, .bishop, .knight]

    public func resolvePromotion(_ type: ChessPieceType) {
        guard let pp = pendingPromotion else { return }
        pendingPromotion = nil
        guard let move = legalMovesCache.first(where: {
            $0.from == pp.from && $0.to == pp.to && $0.promotion == type
        }) else {
            clearSelection()
            return
        }
        apply(move)
    }

    public func cancelPromotion() {
        pendingPromotion = nil
        clearSelection()
    }

    /// 合法手を適用する（AI もここを通る）。
    public func apply(_ move: ChessMove) {
        let mover = position.sideToMove
        position.make(move)
        moves.append(move)
        clearSelection()
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count

        if let detected = Self.detectResult(
            initialFEN: initialFEN, moves: moves, position: position, legalMoves: legalMovesCache
        ) {
            finish(with: detected)
        } else if position.isKingInCheck(position.sideToMove) {
            // 王手の合図（将棋 #377 と同じ）。着手の `impact` は鳴らさない
            // — 同じ着手で 2 度鳴ると合図が濁る。
            lastCheckedSide = position.sideToMove
            checkEventID += 1
            services?.feedback.notify(.warning)
        } else if mover == humanSide {
            // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
            services?.feedback.impact(.medium)
        }
        persist()
    }

    private func finish(with detected: ChessResult) {
        gameOver = true
        result = detected
        phase = .review
        let outcome: GameOutcome
        if detected.isDraw {
            outcome = .draw
            services?.feedback.notify(.warning)
        } else if detected.loser == humanSide {
            outcome = .loss
            services?.feedback.notify(.error)
        } else {
            outcome = .win
            services?.feedback.notify(.success)
        }
        recordResult = services?.gameDidFinish(
            gameID: gameID, outcome: outcome, score: GameScore(metric: .winLoss)
        )
    }

    public func clearSelection() {
        selectedSquare = nil
        pendingPromotion = nil
    }

    /// 新規対局（CPU 対戦）。人間が指す側を選ぶ。
    public func newGame(humanSide: ChessColor = .white, aiLevel: Int = 1) {
        position = ChessPosition.start()
        moves = []
        legalMovesCache = position.legalMoves()
        phase = .playing
        reviewPly = 0
        gameOver = false
        result = nil
        undoUsed = false
        resigned = false
        recordResult = nil
        // 通し番号（`checkEventID`）は 0 に戻さない。View は「値が変わったこと」で
        // 文字を出すため、対局をまたいで単調に増やしておかないと巻き戻しが合図として拾われる。
        lastCheckedSide = nil
        self.white = humanSide == .white ? .human : .ai
        self.black = humanSide == .white ? .ai : .human
        self.aiLevel = aiLevel
        startedAt = startedAtFallback()
        gameSerial += 1
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする（将棋 #145）。
        isThinking = false
        clearSelection()
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    /// 人間が指している側（CPU 戦の表示用）。
    public var humanSide: ChessColor { humanSideValue }

    /// `init` の途中（`humanSide` がまだ使えない時点）からも引けるようにした実体。
    private var humanSideValue: ChessColor { white == .human ? .white : .black }

    // MARK: - CPU 着手

    public private(set) var isThinking: Bool = false

    /// 思考タスクの待ち合わせ点（テスト専用。本番では nil のまま）。
    /// `isThinking = true` と局面の取り込みが済んだ直後・探索の開始前に await する。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// 手数だけだと「0 手のまま黒番で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（将棋 #82）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moves.count) }

    /// 現在の対局が AI の手番か。
    public var isAITurn: Bool {
        guard phase == .playing, !gameOver else { return false }
        return (position.sideToMove == .white ? white : black) == .ai
    }

    /// AI の手番なら最善手を計算して指す。View から手番変化のたびに呼ぶ。
    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧局面で選んだ手が新しい局面に指されうる。
        // 開始時のトリガー（対局の通し番号 × 手数）を控え、完了時に一致する場合だけ着手する。
        let key = aiTurnKey
        let serial = gameSerial
        isThinking = true
        defer { if gameSerial == serial { isThinking = false } }

        let level = aiLevel
        let fen = position.toFEN()
        await thinkingGate?()
        let uci = await Task.detached(priority: .userInitiated) {
            await SimpleChessEngine(level: level).bestMove(fen: fen)
        }.value

        guard aiTurnKey == key, isAITurn, let uci, let move = ChessMove.fromUCI(uci),
              legalMovesCache.contains(move) else { return }
        apply(move)
    }

    // MARK: - 検討（終局後に手を戻す／進める）

    public func reviewGoTo(ply: Int) {
        phase = .review
        reviewPly = min(max(ply, 0), moves.count)
        clearSelection()
        persist()
    }

    public func reviewStepBack() { reviewGoTo(ply: reviewPly - 1) }
    public func reviewStepForward() { reviewGoTo(ply: reviewPly + 1) }

    /// 指定手数までの局面を再生して返す。
    public func positionAt(ply: Int) -> ChessPosition {
        var pos = ChessPosition.fromFEN(initialFEN) ?? ChessPosition.start()
        for m in moves.prefix(min(max(ply, 0), moves.count)) { pos.make(m) }
        return pos
    }

    // MARK: - 投了

    public func resign() {
        guard phase == .playing, !gameOver else { return }
        resigned = true
        finish(with: .resignation(loser: humanSide))
        reviewPly = moves.count
        clearSelection()
        persist()
    }

    // MARK: - 待った（自分の直前手＋CPU 応手の 2 手を戻す）

    private func mover(at index: Int) -> ChessColor {
        // 開始局面の手番から数える（駒落ち等で黒番から始まる FEN でも正しくなる）。
        let start = ChessPosition.fromFEN(initialFEN)?.sideToMove ?? .white
        return index % 2 == 0 ? start : start.opponent
    }

    /// 人間の手番で、直前の自分の手と CPU 応手をまとめて戻せるか。
    public var canUndo: Bool {
        guard phase == .playing, !gameOver, !isAITurn, !isThinking, pendingPromotion == nil else {
            return false
        }
        let n = moves.count
        guard n >= 2 else { return false }
        return mover(at: n - 1) == humanSide.opponent && mover(at: n - 2) == humanSide
    }

    /// 待った: 直前 2 手（人間→CPU）を巻き戻し、人間が指し直せる状態にする。
    public func undoLastExchange() {
        guard canUndo else { return }
        moves.removeLast(2)
        position = positionAt(ply: moves.count)
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count
        undoUsed = true
        clearSelection()
        persist()
    }

    // MARK: - 永続化

    private func persist() {
        let snap = ChessSnapshot(
            initialFen: initialFEN,
            moves: moves.map(\.uci),
            phase: phase,
            reviewPly: phase == .review ? reviewPly : nil,
            white: white,
            black: black,
            aiLevel: (white == .ai || black == .ai) ? aiLevel : nil,
            startedAt: startedAt,
            undoUsed: undoUsed,
            resigned: resigned
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }

    // Date.now を init 前に使えないため分離。
    private func startedAtFallback() -> Date { Date() }
}
