import Foundation
import Observation
import Core

/// 将棋の対局状態。盤・指し手列・選択状態・終局・検討を管理する。
/// ルールは `Position` に委譲し、ここは UI 操作と永続化を担う。
@MainActor
@Observable
public final class ShogiGameModel: AITurnGuarded, BoardUndoModel, BoardHintModel {
    /// 開始局面。手合い（#2179）はここに焼き込む（平手は初形、駒落ちは上手の駒を欠いた後手番の局面）。
    public private(set) var initialSFEN: String
    public private(set) var moves: [Move]
    /// CPU が着手した直後の `aiTurnKey`（#2280）。View はこれと一致する鍵の変化だけを読み上げる。
    public private(set) var lastCPUMoveKey: AITurnKey?
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
    /// 決着の文言の原文（日本語）。終局の種類の判定（`endKind`・`endVerdict`）はこの原文で行い、
    /// 表示は `resultText` が表示言語に訳す（#2109。訳した文で判定すると、言語を切り替えた瞬間に食い違う）。
    private(set) var resultKey: String?
    /// 決着の文言（表示用）。表示言語で引く。
    public var resultText: String? { resultKey.map(Self.localizedResultText) }
    public var sente: PlayerKind
    public var gote: PlayerKind
    public var aiLevel: Int
    /// 定跡の選び方を 1 局ごとに変える種（#2800）。新規対局ごとに引き直す。保存はしない
    /// （続きから再開した対局は、その時点から別の定跡筋を選んでよい。手は常に定跡の合法手）。
    private var bookSeed = UInt64.random(in: .min ... .max)
    public private(set) var undoUsed: Bool
    public private(set) var resigned: Bool
    /// この局のヒントの残り（#1118）。回数と順位表の扱いは Core の `BoardHintBudget` が持つ。
    public private(set) var hints: BoardHintBudget
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?
    /// 直近の決着が、達人（#2698）への**初めての勝ち**か（#2991）。結果カードの専用の見出しを出す。
    /// 保存はしない（再起動後に見返した結果カードは通常の勝ちの見た目に戻る）。
    public private(set) var isMasterFirstWin = false

    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    public let gameID = "shogi"
    private var startedAt: Date

    /// 盤上と両者の持ち駒を駒種ごとに合算して、平手の初期総数を超えていないか。
    private static func hasPlausiblePieceCounts(_ pos: Position) -> Bool {
        let limits: [PieceType: Int] = [
            .pawn: 18, .lance: 4, .knight: 4, .silver: 4, .gold: 4, .bishop: 2, .rook: 2, .king: 2,
        ]
        var totals: [PieceType: Int] = [:]
        for piece in pos.squares.compactMap({ $0 }) { totals[piece.type, default: 0] += 1 }
        for hand in pos.hands {
            for (raw, count) in hand.enumerated() {
                guard let type = PieceType(rawValue: raw) else { continue }
                // 足す前に 1 つずつ弾く（巨大な値の加算そのもので溢れさせない）。
                guard count >= 0, count <= limits[type, default: 0] else { return false }
                totals[type, default: 0] += count
            }
        }
        return limits.allSatisfy { totals[$0.key, default: 0] <= $0.value }
    }

    public init(services: GameServices? = nil) {
        self.services = services
        let snap = services?.snapshots.load(ShogiSnapshot.self, for: "shogi")

        // 中断データが壊れていても起動できるようにする（#1384。チェス #520 と同じ方針）。
        // 読めない初期局面は初形に倒し、`initialSFEN` にも実際に読めた側を残す
        // （千日手判定がここから指し手列を再生し直すため、食い違わせない）。
        let savedSFEN = snap?.initialSfen ?? Position.startSFEN
        // 駒数が初期の総数を超える局面も拒む（持ち駒数が巨大だと合法手の生成中に整数が溢れる）。
        let parsed = Position.fromSFEN(savedSFEN).flatMap { Self.hasPlausiblePieceCounts($0) ? $0 : nil }
        let sfen = parsed == nil ? Position.startSFEN : savedSFEN
        var pos = parsed ?? Position.start()
        var moveList: [Move] = []
        if let snap {
            for usi in snap.moves {
                // 読めない表記に加えて**不正な手でも切り詰める**。`make` は移動元の駒を
                // force-unwrap するので、検証せず適用すると壊れた中断データで起動不能になる。
                guard let m = Move.fromUSI(usi), pos.legalMoves().contains(m) else { break }
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
        // 手数の範囲に収める（切り詰めが起きた手順や壊れた値でも添字が範囲外にならないように）。
        self.reviewPly = min(max(snap?.reviewPly ?? moveList.count, 0), moveList.count)
        // 既定は CPU 対戦（人間=先手 / CPU=後手）。
        self.sente = snap?.sente ?? .human
        self.gote = snap?.gote ?? .ai
        self.aiLevel = snap?.aiLevel ?? 1
        self.startedAt = snap?.startedAt ?? Date()
        self.undoUsed = snap?.undoUsed ?? false
        self.resigned = snap?.resigned ?? false
        // 鍵を持たない v1.1.5 までの中断データは「まだ使っていない」として読む（#1118）。
        self.hints = BoardHintBudget(used: snap?.hintsUsed ?? 0)
        self.gameOver = false
        self.resultKey = nil

        if legalMovesCache.isEmpty {
            self.gameOver = true
            self.phase = .review
            // 詰みの勝敗表示は状態として保存していないので、復元時にここで組み直す。
            // 以前は `gameOver` だけ立てて `resultText` を nil のままにしていたため、
            // 詰んだ対局をアプリの再起動で開くと決着の文字だけが消えていた（#375）。
            self.resultKey = Self.checkmateResultText(loser: pos.sideToMove)
        } else if Self.isFourfoldRepetition(initialSFEN: sfen, moves: moveList, current: pos) {
            // 千日手も指し手列から導けるので、復元時も同じ判定でそのまま決着に戻る。
            self.gameOver = true
            self.phase = .review
            self.resultKey = Self.repetitionResultText(
                perpetualCheckLoser: Self.perpetualCheckLoser(initialSFEN: sfen, moves: moveList)
            )
        }
        if snap?.resigned == true {
            self.gameOver = true
            self.resultKey = Self.resignationResultText
            self.phase = .review
        }
        // 将棋だけは終局後の検討画面をスナップショットに残す（他ゲームは終局で破棄する）。
        // 再起動でその画面に戻ったとき記録行が消えないよう、保存済みの記録から作り直す。
        // **記録し直さない**（`gameDidFinish` を呼ばない）ので二重計上にはならず、
        // 「自己ベスト更新！」も出さない（更新の瞬間はもう過ぎているため）。
        if gameOver, let record = services?.playLog?.record(gameID: gameID, variant: recordVariant) {
            self.recordResult = RecordResult(record: record, update: RecordUpdate())
        }
        // 見返しとして復元した局は決着済み。中断データは残っていても続きは無いので、
        // 中断のお知らせ（#663）の対象から外す。
        if gameOver { services?.gameDidRestoreFinished(gameID: gameID) }
        // 保存された対局が無いときだけ新規対局の開始として数える（#158）。
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        // **開始シートを出す局には `level` を載せない**（PR #572 の指摘）。この分岐と開始シートの
        // 表示条件はどちらも「中断データが無いこと」で、シートで強さを選ぶのはこの直後。
        // ここで既定値を送ると、選び直された強さぶんまで `normal` として数えてしまう。
        // 実際に選んだ強さは `newGame` の `gameDidRestart` が送る（シートを閉じてそのまま
        // 遊んだ局は `level` 無しになる = 選ばれていない事実をそのまま表す）。
        if snap == nil { pendingInitialStart = true }
    }

    /// 開始シートを出す局の `game_start` は、最初の操作かシートを閉じた時点まで遅らせる（#1372）。
    /// シートで「開始」を押すと `newGame` が選んだ強さ付きで数えるので、`init` で先に数えると
    /// 1 局が 2 回 `game_start` になる（`game_end` は 1 回）。冪等で、2 回目以降は何もしない。
    @ObservationIgnored private var pendingInitialStart = false

    public func startPlayIfPending() {
        guard pendingInitialStart else { return }
        pendingInitialStart = false
        services?.gameDidStart(gameID: gameID, mode: matchSetting.analyticsMode)
    }

    // MARK: - 終局の判定

    /// 千日手が成立する同一局面の出現回数。
    static let repetitionLimit = 4

    static func checkmateResultText(loser: Side) -> String {
        (loser == .black ? "先手" : "後手") + "の負け（詰み）"  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
    }

    static let drawRepetitionResultText = "引き分け（千日手）"  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
    static let perpetualCheckSuffix = "の負け（連続王手の千日手）"  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
    static let resignationResultText = "あなたの負け（投了）"  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）

    static func perpetualCheckResultText(loser: Side) -> String {
        (loser == .black ? "先手" : "後手") + perpetualCheckSuffix  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
    }

    /// 決着の文言の原文を表示言語の文にする（#2109）。原文は上の関数が組む 6 通りだけ。
    /// 表のキーはリテラルで書く決まりなので、原文ごとに `tr` を書き分ける。
    static func localizedResultText(_ key: String) -> String {
        switch key {
        case "先手の負け（詰み）": return tr("先手の負け（詰み）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        case "後手の負け（詰み）": return tr("後手の負け（詰み）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        case "先手の負け（連続王手の千日手）": return tr("先手の負け（連続王手の千日手）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        case "後手の負け（連続王手の千日手）": return tr("後手の負け（連続王手の千日手）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        case "引き分け（千日手）": return tr("引き分け（千日手）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        case "あなたの負け（投了）": return tr("あなたの負け（投了）")  // i18n-keep: 決着の判定に使う原文（表示は localizedResultText で訳す）
        default: return key
        }
    }

    /// 千日手の結果文言。連続王手の側がいれば、その側の負け。
    static func repetitionResultText(perpetualCheckLoser loser: Side?) -> String {
        loser.map(perpetualCheckResultText(loser:)) ?? drawRepetitionResultText
    }

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
    /// 連続王手の千日手（王手を掛け続けた側の負け）は `perpetualCheckLoser` が別に判定する（#2005）。
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

    /// 連続王手の千日手で負けになる側（#2005）。千日手が成立した局面（= 指し手列の末尾）で呼ぶ。
    ///
    /// 末尾の局面が最初に現れた手から末尾までを「繰り返しの区間」とし、その区間で**自分の指した
    /// 手がすべて王手だった**側が負け。両方がそうなる・どちらもそうでない場合は nil（引き分け）。
    /// 状態として持たず指し手列から毎回導く（`isFourfoldRepetition` と同じ方針）。
    static func perpetualCheckLoser(initialSFEN: String, moves: [Move]) -> Side? {
        var pos = Position.fromSFEN(initialSFEN) ?? Position.start()
        // 各手を指した後の局面と、その手が王手だったか・誰が指したか。
        var positions = [pos]
        var gaveCheck: [(mover: Side, check: Bool)] = []
        for move in moves {
            let mover = pos.sideToMove
            pos.make(move)
            positions.append(pos)
            gaveCheck.append((mover, pos.isKingInCheck(pos.sideToMove)))
        }
        guard let last = positions.last,
              let first = positions.firstIndex(where: { isSamePosition($0, last) }),
              first < moves.count else { return nil }
        let cycle = gaveCheck[first...]
        func alwaysChecks(_ side: Side) -> Bool {
            let own = cycle.filter { $0.mover == side }
            return !own.isEmpty && own.allSatisfy(\.check)
        }
        switch (alwaysChecks(.black), alwaysChecks(.white)) {
        case (true, false): return .black
        case (false, true): return .white
        default: return nil
        }
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

    /// ヒントが「持ち駒を打つ手」のとき、その駒の種類（持ち駒の欄の印と、打つ先の薄い駒の影に使う・#2768）。
    public var hintDropType: PieceType? {
        if case let .drop(type, _) = hintMove { return type }
        return nil
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

    /// 出したままの「王手」の文字を畳む契機（#519）。**盤の意味が変わる操作**
    /// （待った・新規対局・投了）のたびに増える。
    ///
    /// 文字は `checkBannerHold` の固定待ちで引っ込むので、待った等でその途中に局面が変わると
    /// 王手でない盤の上に札が残っていた。`checkEventID` は着手でしか増えないため、
    /// 巻き戻し側の契機はこちらで別に持つ。`checkEventID` と同じく **0 には戻さない**
    /// （View は「値が変わったこと」で畳むので、巻き戻すと畳む合図として誤読される）。
    public private(set) var checkBannerDismissID: Int = 0

    /// 直前手の棋譜表記（例 "▲７六歩"）。無ければ nil。
    public var highlightedMoveText: String? {
        guard let m = highlightedMove else { return nil }
        let ply = (phase == .review) ? reviewPly : moves.count
        let before = positionAt(ply: ply - 1)
        let mover = before.sideToMove == .black ? "▲" : "△"
        return mover + KIF.notation(m, pos: before, prevTo: nil)
    }

    /// 終局の種類（結果カード用・#1753）。局面と指し手列から毎回導き、状態としては保存しない。
    public enum EndKind: Equatable, Sendable {
        case checkmate, repetition, perpetualCheck, resignation

        /// 結果カードに出す理由。
        public var reasonText: String {
            switch self {
            case .checkmate: return tr("詰み")
            case .repetition: return tr("千日手")
            case .perpetualCheck: return tr("連続王手の千日手")
            case .resignation: return tr("投了")
            }
        }
    }

    public var endKind: EndKind? {
        guard gameOver else { return nil }
        if resigned { return .resignation }
        if resultKey == Self.drawRepetitionResultText { return .repetition }
        if resultKey?.hasSuffix(Self.perpetualCheckSuffix) == true { return .perpetualCheck }
        return .checkmate
    }

    /// 結果カードの勝敗。詰みは手番側（動かせない側）が負け。
    public var endVerdict: BoardGameResultCard.Verdict? {
        switch endKind {
        case nil: return nil
        case .resignation: return .loss
        case .repetition: return .draw
        case .perpetualCheck:
            return resultKey == Self.perpetualCheckResultText(loser: humanSide) ? .loss : .win
        case .checkmate: return position.sideToMove == humanSide ? .loss : .win
        }
    }

    /// 結果カードに出す決め手（詰ましに行った最後の手。例 "▲７六歩"）。詰み以外では nil。
    /// 検討ナビで戻っていても最終手を返す（`highlightedMoveText` は表示中の手）。
    public var decisiveMoveText: String? {
        guard endKind == .checkmate, let m = moves.last else { return nil }
        let before = positionAt(ply: moves.count - 1)
        return (before.sideToMove == .black ? "▲" : "△") + KIF.notation(m, pos: before, prevTo: nil)
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
        if sq == selectedSquare {
            // 選んだ駒をもう一度叩いたら選択を取り消す（拒否ではないので触覚は鳴らさない）。
            clearSelection()
            return
        }
        if let p = position.squares[sq], p.color == position.sideToMove {
            selectedSquare = sq
            selectedHand = nil
            services?.feedback.impact(.selection)
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
        if selectedHand == type {
            clearSelection()
            return
        }
        selectedHand = type
        selectedSquare = nil
        services?.feedback.impact(.selection)
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

    /// 成・不成の選択をやめる。指し手そのものを取り消し、駒の選択状態まで戻す
    /// （チェスの `cancelPromotion` と同じ形。#201 時点では無かった逃げ道を足す）。
    public func cancelPromotion() {
        clearSelection()
    }

    /// 合法手を適用する（AI もここを通る）。
    public func apply(_ move: Move) {
        let mover = position.sideToMove
        // 駒を取る手かは盤を動かす前にしか分からない（取ったときは指す音より少し重い音・#2767）。
        let isCapture: Bool
        if case let .board(_, to, _) = move { isCapture = position.squares[to] != nil } else { isCapture = false }
        position.make(move)
        moves.append(move)
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        startPlayIfPending()
        // CPU の着手では数えない。人間が未着手のまま離れたら離脱ではない（#3042）。
        if mover == humanSide { services?.gameDidProgress(gameID: gameID) }
        clearSelection()
        // 盤が動いたらヒントの印は用済み（#1118）。示した手を指したかどうかは問わない。
        hintMove = nil; hintIsMate = false
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count
        if legalMovesCache.isEmpty {
            gameOver = true
            let loser = position.sideToMove
            resultKey = Self.checkmateResultText(loser: loser)
            phase = .review
            startPlayIfPending()
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: loser == humanSide ? .loss : .win,
                score: recordScore,
                // 評価リクエストの見せ場は「ふつう」以上の CPU に勝ったとき（#1471）。
                isReviewHighlight: beatsWorthyCPU
            )
            notifyFinish(isWin: loser != humanSide, isLoss: loser == humanSide)
        } else if Self.isFourfoldRepetition(initialSFEN: initialSFEN, moves: moves, current: position) {
            // 千日手（#375）。同一局面が 4 回現れたら終局する。これが無いと、
            // 閉塞局面や相入玉で合法手は在り続けるのに勝敗が付かず、出口が投了（負け記録）
            // しか無かった。繰り返しの間ずっと王手を掛け続けた側がいれば、その側の負け（#2005）。
            let loser = Self.perpetualCheckLoser(initialSFEN: initialSFEN, moves: moves)
            gameOver = true
            resultKey = Self.repetitionResultText(perpetualCheckLoser: loser)
            phase = .review
            startPlayIfPending()
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: loser.map { $0 == humanSide ? .loss : .win } ?? .draw,
                score: recordScore
            )
            if let loser {
                notifyFinish(isWin: loser != humanSide, isLoss: loser == humanSide)
            } else {
                services?.feedback.notify(.warning)
            }
        } else if position.isKingInCheck(position.sideToMove) {
            // 王手（#377）。された側・した側のどちらの手番でも同じ合図を出す
            // （初心者が「なぜ動かせないのか」で詰まるのは前者だが、掛けた側にも手応えが要る）。
            // 着手の `impact` は鳴らさない — 同じ着手で 2 度鳴ると合図が濁る。
            lastCheckedSide = position.sideToMove
            checkEventID += 1
            services?.feedback.notify(.warning)
        } else if mover == humanSide {
            // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
            services?.feedback.impact(.board(isCapture ? .shogiCapture : .shogiPiece))
        }
        persist()
    }

    /// 決着の触覚。達人への初勝利（#2991）だけ、通常の勝ちより強い合図（`milestone`）にして実績を解除する。
    /// 記録（`gameDidFinish`）の**後**に呼ぶ: 初めてかどうかは更新後の勝ち数で決まるため。
    private func notifyFinish(isWin: Bool, isLoss: Bool) {
        isMasterFirstWin = isWin && isFirstMasterWin()
        if isMasterFirstWin {
            services?.feedback.notify(.milestone)
            services?.feedback.impact(.rigid)
            services?.gameCenter?.reportUnlocked([GameCenterAchievements.shogiMaster])
        } else {
            services?.feedback.notify(isLoss ? .error : .success)
        }
    }

    /// 達人（平手・駒落ちのどの手合いも含む）の勝ち数が、いま付けた 1 勝だけか。
    private func isFirstMasterWin() -> Bool {
        guard aiLevel == ShogiMasterEngine.level, sente == .ai || gote == .ai,
              let log = services?.playLog else { return false }
        let wins = log.records(gameID: gameID)
            .filter { record in
                guard let key = record.recordKey else { return false }
                return key == "\(gameID)#master" || key.hasPrefix("\(gameID)#master-")
            }
            .reduce(0) { $0 + $1.wins }
        return wins == 1
    }

    public func clearSelection() {
        selectedSquare = nil
        selectedHand = nil
        pendingPromotion = nil
    }

    /// 新規対局（CPU 対戦）。人間が指す側を選ぶ。
    ///
    /// 駒落ち（#2179）のときは、落とす側で人間の座る側が決まる（上手＝後手の位置）ので `humanSide` は使わない。
    /// 手合いはここで開始局面に焼き込む。途中で個人設定を読み直さない（1局＝1ルール）。
    public func newGame(
        humanSide: Side = .black, aiLevel: Int = 1,
        handicap: ShogiHandicap = .even, dropper: ShogiHandicapDropper = .player
    ) {
        let humanSide = handicap == .even ? humanSide : dropper.humanSide
        initialSFEN = handicap.initialSFEN
        position = Position.fromSFEN(initialSFEN) ?? Position.start()
        moves = []
        legalMovesCache = position.legalMoves()
        phase = .playing
        reviewPly = 0
        gameOver = false
        resultKey = nil
        undoUsed = false
        resigned = false
        // ヒントは 1 局ごとに 3 回へ戻す（#1118）。前の局の印も残さない。
        hints.reset()
        hintMove = nil; hintIsMate = false; showsHintHopeless = false
        recordResult = nil
        isMasterFirstWin = false
        // 通し番号（`checkEventID`）は 0 に戻さない。View は「値が変わったこと」で
        // 文字を出すため、対局をまたいで単調に増やしておかないと巻き戻しが合図として拾われる。
        lastCheckedSide = nil
        // 前対局の王手の札が出たままなら、新しい盤の上に残さない（#519）。
        checkBannerDismissID += 1
        self.sente = humanSide == .black ? .human : .ai
        self.gote = humanSide == .black ? .ai : .human
        self.aiLevel = aiLevel
        startedAt = startedAtFallback()
        gameSerial += 1
        bookSeed = UInt64.random(in: .min ... .max)
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする（#145）。
        // 旧タスクは gameSerial が変わったことを見て着手もフラグ操作も行わない。
        isThinking = false
        // ヒントの読みも同じ理由で下ろす（#1118）。旧タスクの defer は対局が変わると旗に触らない。
        isHintThinking = false
        clearSelection()
        persist()
        pendingInitialStart = false
        services?.gameDidRestart(
            gameID: gameID, level: ShogiMasterEngine.analyticsLevel(forLevel: aiLevel), mode: matchSetting.analyticsMode)
    }

    /// この局の手合いと落とす側（#2179）。開始局面と人間の座る側から毎回導く（状態として持たない）ので、
    /// 中断データに項目を足さなくても、続きから再開して手合いが保たれる。
    public var matchSetting: ShogiMatchSetting {
        ShogiMatchSetting(
            handicap: ShogiHandicap.detect(initialSFEN: initialSFEN),
            dropper: .from(humanSide: humanSide))
    }

    /// 決着に渡す成績。手合いごとに記録を分ける（平手は従来の保存先のまま）。
    private var recordScore: GameScore {
        var score = hints.winLossScore
        score.variant = recordVariant
        score.variantLabel = recordVariant.map { RecordVariantLabels.stored(gameID: "shogi", variant: $0) }
        return score
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
    /// ヒントの考える時間にかける倍率（テスト用。広告の回数の検査で探索を実時間で待たない・#2952）。出荷は 1。
    @ObservationIgnored var hintThinkingScaleForTesting: Double = 1

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// 手数だけだと「0 手のまま後手で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（#82）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moves.count) }

    /// AI の手番なら最善手を計算して指す。View から手番変化のたびに呼ぶ。
    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧局面で選んだ手が新しい局面に指されうる（#145）。
        // 開始時の `aiTurnKey` と一致する場合だけ着手する（#531 で共通化）。
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isThinking) {
            let level = aiLevel
            let seed = bookSeed
            let sfen = position.toSFEN()
            await thinkingGate?()
            return await Task.detached(priority: .userInitiated) {
                await ShogiMasterEngine.engine(level: level, seed: seed).bestMove(sfen: sfen)
            }.value
        } commit: { usi in
            // 計算中に状況が変わっていないか確認してから着手。
            guard isAITurn, let usi, let move = Move.fromUSI(usi),
                  legalMovesCache.contains(move) else { return }
            apply(move)
            lastCPUMoveKey = aiTurnKey
        }
    }

    // MARK: - ヒント（#1118）

    /// ヒントで示している最善手。着手・待った・新規対局・投了で消える（局面が変われば印は嘘になる）。
    /// **永続化しない** — 中断データに残すのは使った回数だけで、印は開き直したら出し直す。
    public internal(set) var hintMove: Move?
    /// ヒントの読みの最中か。CPU の思考（`isThinking`）とは別に持つ
    /// （同じ旗にすると、ヒントを読んでいるあいだ盤が「CPU思考中…」と名乗る）。
    public private(set) var isHintThinking: Bool = false

    /// 示している手が「詰ます手」か（#2779。読み上げが「詰みがあります」と添える）。`hintMove` と同じ寿命。
    public internal(set) var hintIsMate = false
    /// 「この局面は詰みを逃れる手がありません」の知らせを出しているか（#2779）。回数は減らさない。
    public var showsHintHopeless = false
    public func dismissHintHopeless() { showsHintHopeless = false }

    /// 残り回数（`BoardControlBarHint` が読む）。
    public var hintsRemaining: Int { hints.remaining }

    /// ヒントで光らせるマス（移動元・移動先。打つ手は打つ先だけ）。
    public var hintSquares: Set<Int> {
        switch hintMove {
        case let .board(from, to, _): return [from, to]
        case let .drop(_, to): return [to]
        case nil: return []
        }
    }

    /// いまヒントを押せるか。**自分の手番で、対局中で、残りが在るとき**だけ。
    /// CPU の思考中・成り選択の最中は盤が自分のものではないので押させない。
    public var canUseHint: Bool {
        phase == .playing && !gameOver && !hints.isExhausted
            && !isAITurn && !isThinking && !isHintThinking && pendingPromotion == nil
    }

    /// 無料枠を使い切っていて、次の 1 回に広告が要るか（#1500）。
    public var needsAdForHint: Bool { !hints.hasFreeRemaining && !hints.isExhausted }

    /// 現在の局面の最善手を 1 手求め、盤の上に示す（#1118）。
    ///
    /// 読みは CPU の着手と同じ `AITurnGuarded` の照合に載せる（#531）。読んでいるあいだに
    /// 指す・待った・新規対局が入ると、旧局面の手を新しい盤の上に光らせることになるため。
    /// **求まらなかった局・局面が変わった局では回数を減らさない**（ヒントが出ないのに
    /// 1 回使ったことにしない）。
    public func requestHint() async {
        guard canUseHint else { return }
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isHintThinking) {
            let sfen = position.toSFEN()
            let scale = hintThinkingScaleForTesting
            await thinkingGate?()
            return await Task.detached(priority: .userInitiated) {
                // ヒントは対局中の CPU の強さに関わらず常に最強で読む（`BoardHintBudget.engineLevel`）。
                // 先に詰みを探し、詰ます手・詰みを避ける手を選ぶ（#2779）。
                SimpleMinimaxEngine.hint(thinkingScale: scale).hintAnswer(sfen: sfen)
            }.value
        } commit: { answer in
            // `canUseHint` は読みの旗が立ったままなのでここでは使えない。前提を個別に確かめ直す。
            // 成り選択中（`pendingPromotion`）を外せないのが要点（PR #1184 の指摘）。読みの最中でも
            // 成・不成は選べてしまい、そのとき `aiTurnKey` はまだ変わらないのでキーの照合では弾けない。
            // 弾かずに通すと、直後の `apply` が印を消すので「回数だけ減ってヒントが出ない」になる。
            guard phase == .playing, !gameOver, !isAITurn, pendingPromotion == nil,
                  hints.hasFreeRemaining, let answer else { return }
            // 受けが無い局面は知らせるだけ。回数は減らさない（#2779）。
            guard let move = answer.move else { showsHintHopeless = true; return }
            guard legalMovesCache.contains(move), hints.consume() else { return }
            showHint(move, isMate: answer.isMate)
        }
    }

    /// 読み終えた手を盤に示す（回数の消費は呼び出し側）。
    private func showHint(_ move: Move, isMate: Bool) {
        startPlayIfPending()
        services?.gameDidUseHint(gameID: gameID)
        hintMove = move
        hintIsMate = isMate
        services?.feedback.impact(.light)
        // 残り回数は中断データに持ち回る（再開でヒントが 3 回に戻らないように）。
        persist()
    }

    /// 無料枠を使い切った後、広告を見て 1 回ぶん追加する（会長決裁 2026-09-27・#1500）。
    ///
    /// 広告の視聴完了を確かめてから CPU の読みを始める（読み終えてから広告を流さない契約）。
    /// 視聴のあいだに指す・待った・新規対局が入ったら、読みには進まず `.unavailable` を返す。
    public func requestAdHint() async -> RewardedModelOutcome {
        guard canUseHint, needsAdForHint else { return .unavailable }
        // 受けが無い局面では広告を流さない（#2779）。詰み探索は短いので、広告の前に確かめる。
        let sfenBeforeAd = position.toSFEN()
        let scale = hintThinkingScaleForTesting
        if await Task.detached(priority: .userInitiated, operation: {
            SimpleMinimaxEngine.hint(thinkingScale: scale).hasNoDefense(sfen: sfenBeforeAd)
        }).value {
            guard canUseHint, position.toSFEN() == sfenBeforeAd else { return .unavailable }
            showsHintHopeless = true
            return .granted
        }
        let turn = aiTurnKey
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .hint) ?? true else {
            return .notEarned
        }
        guard services?.screenGeneration.current == generationBeforeAd, turn == aiTurnKey else { return .unavailable }
        var outcome: RewardedModelOutcome = .unavailable
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isHintThinking) {
            let sfen = position.toSFEN()
            let scale = hintThinkingScaleForTesting
            await thinkingGate?()
            return await Task.detached(priority: .userInitiated) {
                SimpleMinimaxEngine.hint(thinkingScale: scale).hintAnswer(sfen: sfen)
            }.value
        } commit: { answer in
            guard phase == .playing, !gameOver, !isAITurn, pendingPromotion == nil,
                  !hints.isExhausted, let answer else { return }
            // 広告の前の確認が間に合わず、広告のあとに受けが無いと分かったとき（回数は減らさない・#2779）。
            guard let move = answer.move else { showsHintHopeless = true; outcome = .granted; return }
            guard legalMovesCache.contains(move), hints.consumeAd() else { return }
            showHint(move, isMate: answer.isMate)
            outcome = .granted
        }
        return outcome
    }

    // MARK: - 検討（終局後に手を戻す／進める）

    public func reviewGoTo(ply: Int) {
        phase = .review
        reviewPly = min(max(ply, 0), moves.count)
        // 盤に出ている局面が変わるので、ヒントの印は残さない（#1118）。
        hintMove = nil; hintIsMate = false
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
        // 投了で盤の意味が変わるので、出したままの王手の札も一緒に片付ける（#519）。
        checkBannerDismissID += 1
        // ヒントの印も同じ理由で片付ける（#1118）。
        hintMove = nil; hintIsMate = false
        resigned = true
        gameOver = true
        services?.feedback.notify(.error)
        startPlayIfPending()
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: recordScore)
        resultKey = Self.resignationResultText
        phase = .review
        reviewPly = moves.count
        clearSelection()
        persist()
    }

    // MARK: - 待った（自分の直前手＋CPU 応手の 2 手を戻す）

    /// 開始局面で最初に指す側。平手は先手、駒落ちは上手（後手の位置・#2179）。
    private var firstMover: Side {
        initialSFEN.split(separator: " ").dropFirst().first == "w" ? .white : .black
    }

    private func mover(at index: Int) -> Side {
        index % 2 == 0 ? firstMover : firstMover.opponent
    }

    /// 人間の手番で、直前の自分の手と CPU 応手をまとめて戻せるか。
    public var canUndo: Bool {
        // 読み中は戻さない（待つ前の局面のヒントが、手数が戻ったあとの局面に適用されてしまうため。#2236）
        guard phase == .playing, !gameOver, !isAITurn, !isThinking, !isHintThinking, pendingPromotion == nil else {
            return false
        }
        let n = moves.count
        guard n >= 2 else { return false }
        return mover(at: n - 1) == humanSide.opponent && mover(at: n - 2) == humanSide
    }

    /// 待った: 直前 2 手（人間→CPU）を巻き戻し、人間が指し直せる状態にする。
    public func undoLastExchange() {
        guard canUndo else { return }
        // 盤が 2 手ぶん戻ると王手も消えるので、出したままの札を残さない（#519）。
        checkBannerDismissID += 1
        // ヒントの印も 2 手前の盤には合わないので消す（#1118。回数は戻さない）。
        hintMove = nil; hintIsMate = false
        moves.removeLast(2)
        position = positionAt(ply: moves.count)
        legalMovesCache = position.legalMoves()
        reviewPly = moves.count
        undoUsed = true
        clearSelection()
        persist()
    }

    /// 広告を出す前に控えた `aiTurnKey`（対局の通し番号 × 手数）の局面にだけ待ったを適用する（#729）。
    /// - Returns: 戻せたか。広告のあいだに新規対局・投了・着手で局面が変わっていたら false
    ///   （View は「待ったを使えなかった」と知らせる）。対局の番号だけを照合すると、ロード中に
    ///   1 往復指したとき、広告を出したときとは別の 1 往復が戻る。
    @discardableResult
    public func undoLastExchange(forTurn turn: AITurnKey) -> Bool {
        guard turn == aiTurnKey, canUndo else { return false }
        undoLastExchange()
        return true
    }

    // MARK: - 永続化

    /// 評価リクエストの見せ場（#1471）: 「ふつう」以上の CPU との対局か。人間同士の対局は含まない。
    private var beatsWorthyCPU: Bool {
        guard sente == .ai || gote == .ai else { return false }
        // CPU に駒を落とされた勝ちは、手加減してもらった勝ちなので見せ場にしない（#2179）。
        let setting = matchSetting
        if setting.isHandicap && setting.dropper == .cpu { return false }
        return CPUStrength.isReviewWorthy(level: aiLevel)
    }

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
            resigned: resigned,
            hintsUsed: hints.used
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }

    // Date.now を init 前に使えないため分離。
    private func startedAtFallback() -> Date { Date() }
}

// MARK: - 達人（#2698）

extension ShogiGameModel {
    /// 記録の区分キー。手合いの区分に、達人のときだけ `master` を前に付ける（既存の段の記録と混ぜない）。
    var recordVariant: String? {
        ShogiMasterEngine.recordVariant(level: aiLevel, handicapVariant: matchSetting.recordVariant)
    }
}

extension ShogiMasterEngine {
    /// 開始シートに出す呼び名。
    public static var label: String { tr("達人") }

    /// 生の `aiLevel` から強さの呼び名。達人は `CPUStrength` の並びの外（読み替えると「ふつう」に倒れる）ので先に拾う。
    public static func strengthLabel(forLevel level: Int) -> String {
        level == Self.level ? label : CPUStrength.strength(for: level).label
    }

    /// 記録の区分キー。達人は既存の段（平手は区分なし＝通算の保存先）と混ざらないよう別の保存先にする。
    /// 駒落ちは手合いのキーの前に付ける（`master-rook-player` など）。達人以外は手合いの区分のまま。
    public static func recordVariant(level: Int, handicapVariant: String?) -> String? {
        guard level == Self.level else { return handicapVariant }
        return handicapVariant.map { "master-\($0)" } ?? "master"
    }

    /// 解析の段。達人は既存 4 段（novice/beginner/normal/hard）と分けるため最上級（`expert`）で送る。
    public static func analyticsLevel(forLevel level: Int) -> AnalyticsLevel {
        level == Self.level ? .expert : CPUStrength.analyticsLevel(forLevel: level)
    }
}
