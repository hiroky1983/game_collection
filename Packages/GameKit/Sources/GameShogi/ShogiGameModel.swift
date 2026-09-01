import Foundation
import Observation
import Core

/// 将棋の対局状態。盤・指し手列・選択状態・終局・検討を管理する。
/// ルールは `Position` に委譲し、ここは UI 操作と永続化を担う。
@MainActor
@Observable
public final class ShogiGameModel {
    public let initialSFEN: String
    public private(set) var moves: [Move]
    public private(set) var position: Position
    public private(set) var legalMovesCache: [Move]

    // 選択状態
    public private(set) var selectedSquare: Int?
    public private(set) var selectedHand: PieceType?
    /// 成り選択待ち（成・不成の両方が合法な移動）。
    public private(set) var pendingPromotion: (from: Int, to: Int)?

    // 対局設定・進行
    public private(set) var phase: GamePhase
    public private(set) var reviewPly: Int
    public private(set) var gameOver: Bool
    public private(set) var resultText: String?
    public var sente: PlayerKind
    public var gote: PlayerKind
    public var aiLevel: Int
    public private(set) var undoUsed: Bool
    public private(set) var resigned: Bool
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    private let gameID = "shogi"
    private var startedAt: Date

    public init(services: GameServices? = nil) {
        self.services = services
        let snap = services?.snapshots.load(ShogiSnapshot.self, for: "shogi")

        let sfen = snap?.initialSfen ?? Position.startSFEN
        var pos = Position.fromSFEN(sfen) ?? Position.start()
        var moveList: [Move] = []
        if let snap {
            for usi in snap.moves {
                guard let m = Move.fromUSI(usi) else { break }
                moveList.append(m)
                pos.make(m)
            }
        }

        self.initialSFEN = sfen
        self.moves = moveList
        self.position = pos
        self.legalMovesCache = pos.legalMoves()
        self.selectedSquare = nil
        self.selectedHand = nil
        self.pendingPromotion = nil
        self.phase = snap?.phase ?? .playing
        self.reviewPly = snap?.reviewPly ?? moveList.count
        // 既定は CPU 対戦（人間=先手 / CPU=後手）。
        self.sente = snap?.sente ?? .human
        self.gote = snap?.gote ?? .ai
        self.aiLevel = snap?.aiLevel ?? 1
        self.startedAt = snap?.startedAt ?? Date()
        self.undoUsed = snap?.undoUsed ?? false
        self.resigned = snap?.resigned ?? false
        self.gameOver = false
        self.resultText = nil

        if legalMovesCache.isEmpty {
            self.gameOver = true
            self.phase = .review
            // 詰みの勝敗表示は状態として保存していないので、復元時にここで組み直す。
            // 以前は `gameOver` だけ立てて `resultText` を nil のままにしていたため、
            // 詰んだ対局をアプリの再起動で開くと決着の文字だけが消えていた（#375）。
            self.resultText = Self.checkmateResultText(loser: pos.sideToMove)
        } else if Self.isFourfoldRepetition(initialSFEN: sfen, moves: moveList, current: pos) {
            // 千日手も指し手列から導けるので、復元時も同じ判定でそのまま決着に戻る。
            self.gameOver = true
            self.phase = .review
            self.resultText = Self.repetitionResultText
        }
        if snap?.resigned == true {
            self.gameOver = true
            self.resultText = "あなたの負け（投了）"
            self.phase = .review
        }
        // 将棋だけは終局後の検討画面をスナップショットに残す（他ゲームは終局で破棄する）。
        // 再起動でその画面に戻ったとき記録行が消えないよう、保存済みの記録から作り直す。
        // **記録し直さない**（`gameDidFinish` を呼ばない）ので二重計上にはならず、
        // 「自己ベスト更新！」も出さない（更新の瞬間はもう過ぎているため）。
        if gameOver, let record = services?.playLog?.record(gameID: gameID) {
            self.recordResult = RecordResult(record: record, update: RecordUpdate())
        }
        // 保存された対局が無いときだけ新規対局の開始として数える（#158）。
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if snap == nil { services?.gameDidStart(gameID: gameID) }
    }

    // MARK: - 終局の判定

    /// 千日手が成立する同一局面の出現回数。
    static let repetitionLimit = 4

    static func checkmateResultText(loser: Side) -> String {
        (loser == .black ? "先手" : "後手") + "の負け（詰み）"
    }

    static let repetitionResultText = "引き分け（千日手）"

    /// 千日手の「同一局面」。**盤・持ち駒・手番**が一致すれば同一とみなす。
    /// `Position` の `==` は手数（`moveNumber`）も見るため、繰り返しの検出には使えない。
    private static func isSamePosition(_ a: Position, _ b: Position) -> Bool {
        a.squares == b.squares && a.hands == b.hands && a.sideToMove == b.sideToMove
    }

    /// 現在の局面が初手からの経過で 4 回目の出現か（= 千日手）。
    ///
    /// 状態として持たず**指し手列から毎回導く**（`checkedKingSquare` と同じ方針）。こうしておくと、
    /// 中断からの復元でもスナップショットに項目を足さずに同じ判定になる。
    ///
    /// **連続王手の千日手（王手を掛け続けた側の負け）は v1 のスコープ外**で、この場合も引き分けに
    /// なる。判定を誤ると勝敗が逆転するため、独立した Issue として起票する。
    static func isFourfoldRepetition(initialSFEN: String, moves: [Move], current: Position) -> Bool {
        // 同一局面の周期は最短でも 4 手（両者が動かした駒を戻して初めて一致する）なので、
        // 4 回目の出現には少なくとも 12 手が要る。
        guard moves.count >= (repetitionLimit - 1) * 4 else { return false }
        var pos = Position.fromSFEN(initialSFEN) ?? Position.start()
        var count = isSamePosition(pos, current) ? 1 : 0
        for move in moves {
            pos.make(move)
            if isSamePosition(pos, current) { count += 1 }
        }
        return count >= repetitionLimit
    }

    // MARK: - 表示用

    /// 検討中は reviewPly までの局面、対局中は最新局面を表示する。
    public var displayedPosition: Position {
        if phase == .review {
            return positionAt(ply: reviewPly)
        }
        return position
    }

    /// 強調表示する直前の指し手（対局中は最新手、検討中は表示局面に至った手）。
    public var highlightedMove: Move? {
        let ply = (phase == .review) ? reviewPly : moves.count
        return ply > 0 ? moves[ply - 1] : nil
    }

    /// 直前手の移動元・移動先マス（CPU の手などを色で示す用）。
    public var highlightedSquares: Set<Int> {
        switch highlightedMove {
        case let .board(from, to, _): return [from, to]
        case let .drop(_, to): return [to]
        case nil: return []
        }
    }

    /// 王手されている側の玉のマス（表示局面基準）。王手でなければ nil。
    ///
    /// 状態として持たず**局面から毎回導く**（#377）。こうしておくと、検討ナビで戻った局面でも
    /// 中断から復元した局面でも、玉の印が別途の復元処理なしに必ず正しく出る。
    public var checkedKingSquare: Int? {
        let pos = displayedPosition
        let side = pos.sideToMove
        guard pos.isKingInCheck(side) else { return nil }
        return pos.squares.firstIndex { $0?.type == .king && $0?.color == side }
    }

    /// 「王手」の文字を飛び出させる契機（#377）。**実対局の着手で王手が生じるたび**に増える。
    ///
    /// 検討ナビ・中断復元では増えない。玉の印（`checkedKingSquare`）は局面から導くので
    /// どの経路でも出るが、文字のほうは「いま王手が掛かった」瞬間の合図なので、
    /// 盤を戻して王手局面を通過しただけで飛び出すと意味が変わる。
    public private(set) var checkEventID: Int = 0

    /// 直前の `checkEventID` で王手を**された**側。
    public private(set) var lastCheckedSide: Side?

    /// 直前手の棋譜表記（例 "▲７六歩"）。無ければ nil。
    public var highlightedMoveText: String? {
        guard let m = highlightedMove else { return nil }
        let ply = (phase == .review) ? reviewPly : moves.count
        let before = positionAt(ply: ply - 1)
        let mover = before.sideToMove == .black ? "▲" : "△"
        return mover + KIF.notation(m, pos: before, prevTo: nil)
    }

    /// 現在の選択から導く合法な着手先マス。
    public var legalTargets: Set<Int> {
        if let from = selectedSquare {
            return Set(legalMovesCache.compactMap {
                if case let .board(f, t, _) = $0, f == from { return t }
                return nil
            })
        } else if let hand = selectedHand {
            return Set(legalMovesCache.compactMap {
                if case let .drop(ty, t) = $0, ty == hand { return t }
                return nil
            })
        }
        return []
    }

    // MARK: - 対局操作

    public func tapSquare(_ sq: Int) {
        // CPU の手番（思考中含む）は人間の操作を受け付けない。
        guard phase == .playing, !gameOver, pendingPromotion == nil, !isAITurn else { return }
        if (selectedSquare != nil || selectedHand != nil), legalTargets.contains(sq) {
            attemptMove(to: sq)
            return
        }
        if let p = position.squares[sq], p.color == position.sideToMove {
            selectedSquare = sq
            selectedHand = nil
        } else {
            // 駒を選んだ状態で指せないマスを叩いた = 着手の拒否。
            if selectedSquare != nil || selectedHand != nil {
                services?.feedback.notify(.warning)
            }
            clearSelection()
        }
    }

    public func tapHand(_ type: PieceType, color: Side) {
        guard phase == .playing, !gameOver, pendingPromotion == nil, !isAITurn else { return }
        guard color == position.sideToMove,
              position.hands[color.rawValue][type.rawValue] > 0 else { return }
        selectedHand = type
        selectedSquare = nil
    }

    private func attemptMove(to sq: Int) {
        if let from = selectedSquare {
            let candidates = legalMovesCache.filter {
                if case let .board(f, t, _) = $0 { return f == from && t == sq }
                return false
            }
            if candidates.count >= 2 {
                pendingPromotion = (from, sq) // 成・不成を選ばせる
            } else if let m = candidates.first {
                apply(m)
            }
        } else if let hand = selectedHand {
            if let m = legalMovesCache.first(where: { $0 == .drop(type: hand, to: sq) }) {
                apply(m)
            }
        }
    }

    public func resolvePromotion(_ promote: Bool) {
        guard let pp = pendingPromotion else { return }
        pendingPromotion = nil
        apply(.board(from: pp.from, to: pp.to, promote: promote))
    }

    /// 合法手を適用する（AI もここを通る）。
    public func apply(_ move: Move) {
        let mover = position.sideToMove
        position.make(move)
        moves.append(move)
        clearSelection()
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count
        if legalMovesCache.isEmpty {
            gameOver = true
            let loser = position.sideToMove
            resultText = Self.checkmateResultText(loser: loser)
            phase = .review
            services?.feedback.notify(loser == humanSide ? .error : .success)
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: loser == humanSide ? .loss : .win,
                score: GameScore(metric: .winLoss)
            )
        } else if Self.isFourfoldRepetition(initialSFEN: initialSFEN, moves: moves, current: position) {
            // 千日手（#375）。同一局面が 4 回現れたら引き分けで終局する。これが無いと、
            // 閉塞局面や相入玉で合法手は在り続けるのに勝敗が付かず、出口が投了（負け記録）
            // しか無かった。
            gameOver = true
            resultText = Self.repetitionResultText
            phase = .review
            services?.feedback.notify(.warning)
            recordResult = services?.gameDidFinish(
                gameID: gameID, outcome: .draw, score: GameScore(metric: .winLoss)
            )
        } else if position.isKingInCheck(position.sideToMove) {
            // 王手（#377）。された側・した側のどちらの手番でも同じ合図を出す
            // （初心者が「なぜ動かせないのか」で詰まるのは前者だが、掛けた側にも手応えが要る）。
            // 着手の `impact` は鳴らさない — 同じ着手で 2 度鳴ると合図が濁る。
            lastCheckedSide = position.sideToMove
            checkEventID += 1
            services?.feedback.notify(.warning)
        } else if mover == humanSide {
            // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
            services?.feedback.impact(.medium)
        }
        persist()
    }

    public func clearSelection() {
        selectedSquare = nil
        selectedHand = nil
        pendingPromotion = nil
    }

    /// 新規対局（CPU 対戦）。人間が指す側を選ぶ。
    public func newGame(humanSide: Side = .black, aiLevel: Int = 1) {
        position = Position.start()
        moves = []
        legalMovesCache = position.legalMoves()
        phase = .playing
        reviewPly = 0
        gameOver = false
        resultText = nil
        undoUsed = false
        resigned = false
        recordResult = nil
        // 通し番号（`checkEventID`）は 0 に戻さない。View は「値が変わったこと」で
        // 文字を出すため、対局をまたいで単調に増やしておかないと巻き戻しが合図として拾われる。
        lastCheckedSide = nil
        self.sente = humanSide == .black ? .human : .ai
        self.gote = humanSide == .black ? .ai : .human
        self.aiLevel = aiLevel
        startedAt = startedAtFallback()
        gameSerial += 1
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする（#145）。
        // 旧タスクは gameSerial が変わったことを見て着手もフラグ操作も行わない。
        isThinking = false
        clearSelection()
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    /// 人間が指している側（CPU 戦の表示用）。
    public var humanSide: Side { sente == .human ? .black : .white }

    // MARK: - CPU 着手

    public private(set) var isThinking: Bool = false

    /// 思考タスクの待ち合わせ点（テスト専用。本番では nil のまま）。
    /// `isThinking = true` と局面の取り込みが済んだ直後・探索の開始前に await する。
    /// テストはここで思考を止めることで、「探索の完了待ちで停止中」という状態を
    /// 探索の所要時間に依存せず決定論的に作れる（#172）。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// 手数だけだと「0 手のまま後手で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（#82）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moves.count) }

    /// AI の手番なら最善手を計算して指す。View から手番変化のたびに呼ぶ。
    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧局面で選んだ手が新しい局面に指されうる
        // （初期局面同士なら合法性の確認を通ってしまう）。開始時のトリガー
        // （対局の通し番号 × 手数）を控え、完了時に一致する場合だけ着手する（#145）。
        let key = aiTurnKey
        let serial = gameSerial
        isThinking = true
        // 別対局が始まっていたら、思考フラグの持ち主は新しい対局のタスクなので触らない。
        defer { if gameSerial == serial { isThinking = false } }

        let level = aiLevel
        let sfen = position.toSFEN()
        await thinkingGate?()
        let usi = await Task.detached(priority: .userInitiated) {
            await SimpleMinimaxEngine(level: level).bestMove(sfen: sfen)
        }.value

        // 計算中に状況が変わっていないか確認してから着手。
        guard aiTurnKey == key, isAITurn, let usi, let move = Move.fromUSI(usi),
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
    public func positionAt(ply: Int) -> Position {
        var pos = Position.fromSFEN(initialSFEN) ?? Position.start()
        for m in moves.prefix(min(ply, moves.count)) {
            pos.make(m)
        }
        return pos
    }

    /// 現在の対局が AI の手番か（手番側プレイヤーが AI）。
    public var isAITurn: Bool {
        guard phase == .playing, !gameOver else { return false }
        return (position.sideToMove == .black ? sente : gote) == .ai
    }

    // MARK: - 投了

    public func resign() {
        guard phase == .playing, !gameOver else { return }
        resigned = true
        gameOver = true
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: GameScore(metric: .winLoss))
        resultText = "あなたの負け（投了）"
        phase = .review
        reviewPly = moves.count
        clearSelection()
        persist()
    }

    // MARK: - 待った（自分の直前手＋CPU 応手の 2 手を戻す）

    private func mover(at index: Int) -> Side {
        index % 2 == 0 ? .black : .white
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
        let snap = ShogiSnapshot(
            initialSfen: initialSFEN,
            moves: moves.map(\.usi),
            phase: phase,
            reviewPly: phase == .review ? reviewPly : nil,
            sente: sente,
            gote: gote,
            aiLevel: (sente == .ai || gote == .ai) ? aiLevel : nil,
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
