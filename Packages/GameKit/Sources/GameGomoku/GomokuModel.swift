import Foundation
import Observation
import Core

struct GomokuMoveRecord: Codable {
    let row: Int
    let col: Int
    let stone: Int
}

/// 着手が拒否された理由（#202）。
///
/// 判定は Model 側に集約する（`FeedbackService` の規約どおり。View のタップハンドラで
/// 早期 return すると、その分岐だけフィードバックを付け忘れる）。View はこれを見て
/// 震え演出のトリガーにするだけで、判定そのものは持たない。
/// 決着後のタップは含まない。結果表示と「もう一度」が出ている状態で盤を触るのは
/// 誤操作ではないため、拒否として鳴らすと雑音になる。
public enum GomokuTapRejection: Equatable, Sendable {
    /// CPU の手番・思考中のタップ。
    case notYourTurn
    /// 盤の外（格子の範囲外）へのタップ。
    case outOfBoard
    /// 既に石が置かれている交点へのタップ。
    case occupied
    /// 禁じ手ルールが有効なときに、黒が三三・四四・長連へ打とうとした（#441）。
    case forbidden(GomokuForbidden)
}

struct GomokuSnapshot: Codable {
    let cells: [Int?]
    let currentStone: Int
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
    let moveHistory: [GomokuMoveRecord]?
    let undoUsed: Bool?
    let resigned: Bool?
    let winner: Int?
    /// 連珠の禁じ手ルール（#441）。旧スナップショットには無いので optional。
    let forbiddenMoves: Bool?
    /// この局で使ったヒントの回数（#1118）。鍵を持たない v1.1.5 までの中断データでは nil = 未使用。
    let hintsUsed: Int?
}

@MainActor
@Observable
public final class GomokuModel: AITurnGuarded, BoardUndoModel, BoardHintModel {
    public private(set) var board: GomokuBoard
    public private(set) var currentStone: GomokuStone
    public private(set) var humanSide: GomokuStone
    public private(set) var aiLevel: Int
    /// 連珠の禁じ手ルール（#441）。既定はオフ = 従来どおりの自由五目。
    /// オンのときだけ黒（先手）に三三・四四・長連が適用される。
    public private(set) var forbiddenMovesEnabled: Bool
    public private(set) var winner: GomokuStone?
    public private(set) var isDraw: Bool
    public private(set) var isThinking: Bool
    public private(set) var lastMove: (row: Int, col: Int)?
    public private(set) var moveCount: Int
    public private(set) var undoUsed: Bool
    /// この局のヒントの残り（#1118）。回数と順位表の扱いは Core の `BoardHintBudget` が持つ（将棋・チェスと共通）。
    public private(set) var hints: BoardHintBudget
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    /// 同じ理由で連続して拒否されても毎回震えるよう、理由ではなく回数を見せる。
    public private(set) var rejectedTapCount: Int = 0
    /// 直近の拒否理由（#202）。フィードバックの内訳をテストから確かめるために公開する。
    public private(set) var lastRejection: GomokuTapRejection?
    /// 決着した五（以上）の座標（#665）。着手で勝敗が決まったときだけ入り、投了・引き分けでは `nil`。
    /// View はこれを盤上の勝ち筋として光らせ、「なぜ負けたか」を見せる。
    public private(set) var winningLine: [GomokuPoint]?
    private var resigned: Bool

    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    public let gameID = "gomoku"
    private var startedAt: Date
    private var moves: [(row: Int, col: Int, stone: GomokuStone)]

    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentStone != humanSide }

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// 手数だけだと「0 手のまま後手で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（#140。将棋 #82 と同じ原因）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moveCount) }

    public init(services: GameServices? = nil) {
        self.services = services

        let board: GomokuBoard
        let currentStone: GomokuStone
        let humanSide: GomokuStone
        let aiLevel: Int
        let forbiddenMoves: Bool
        let startedAt: Date
        let moveCount: Int
        let moves: [(row: Int, col: Int, stone: GomokuStone)]
        let lastMove: (row: Int, col: Int)?
        let undoUsed: Bool
        let resigned: Bool
        let hintsUsed: Int
        let savedWinner: GomokuStone?
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = false

        var loaded = services?.snapshots.load(GomokuSnapshot.self, for: "gomoku")
        // 盤の寸法・着手の座標が範囲外の中断データは、読むと添字が範囲外になり開くたびに落ちる（#1384）。
        // 消して新規開始に倒す。
        if let snap = loaded, !Self.isRestorable(snap) {
            services?.snapshots.clear(for: "gomoku")
            loaded = nil
        }
        if let snap = loaded {
            humanSide = GomokuStone(rawValue: snap.humanSide) ?? .black
            aiLevel   = snap.aiLevel
            forbiddenMoves = snap.forbiddenMoves ?? false
            startedAt = snap.startedAt
            if let history = snap.moveHistory {
                let parsed = history.compactMap { rec -> (Int, Int, GomokuStone)? in
                    guard let stone = GomokuStone(rawValue: rec.stone) else { return nil }
                    return (rec.row, rec.col, stone)
                }
                moves     = parsed
                board     = Self.board(from: parsed)
                moveCount = parsed.count
                if let last = parsed.last {
                    lastMove      = (last.0, last.1)
                    currentStone  = last.2.opponent
                } else {
                    lastMove     = nil
                    currentStone = .black
                }
            } else {
                let cells = snap.cells.map { $0.flatMap { GomokuStone(rawValue: $0) } }
                board        = GomokuBoard(cells: cells)
                currentStone = GomokuStone(rawValue: snap.currentStone) ?? .black
                moveCount    = cells.compactMap { $0 }.count
                moves        = []
                lastMove     = nil
            }
            undoUsed    = snap.undoUsed ?? false
            resigned    = snap.resigned ?? false
            // 鍵を持たない v1.1.5 までの中断データは「まだ使っていない」として読む（#1118）。
            hintsUsed   = snap.hintsUsed ?? 0
            savedWinner = snap.winner.flatMap { GomokuStone(rawValue: $0) }
        } else {
            board        = GomokuBoard()
            currentStone = .black
            humanSide    = .black
            aiLevel      = 1
            forbiddenMoves = false
            startedAt    = Date()
            moveCount    = 0
            moves        = []
            lastMove     = nil
            undoUsed     = false
            resigned     = false
            hintsUsed    = 0
            savedWinner  = nil
            isFreshStart = true
        }

        self.board        = board
        self.currentStone = currentStone
        self.humanSide    = humanSide
        self.aiLevel      = aiLevel
        self.forbiddenMovesEnabled = forbiddenMoves
        self.startedAt    = startedAt
        self.moveCount    = moveCount
        self.moves        = moves
        // savedWinner が最優先。なければ resign フラグで補完（旧スナップショット互換）
        self.winner       = savedWinner ?? (resigned ? humanSide.opponent : nil)
        self.isDraw       = (savedWinner == nil && !resigned && board.isFull)
        self.isThinking   = false
        self.lastMove     = lastMove
        self.undoUsed     = undoUsed
        self.resigned     = resigned
        self.hints        = BoardHintBudget(used: hintsUsed)
        // 勝ち筋は保存せず、直前手から引き直す（決着を書いた中断データでも光るように）。
        if let savedWinner, !resigned, let last = lastMove, board[last.row, last.col] == savedWinner {
            self.winningLine = board.winningLine(row: last.row, col: last.col)
        }
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        // **開始シートを出す局には `level` を載せない**（PR #572 の指摘）。この分岐と開始シートの
        // 表示条件はどちらも「中断データが無いこと」で、シートで強さを選ぶのはこの直後。
        // ここで既定値を送ると、選び直された強さぶんまで `normal` として数えてしまう。
        // 実際に選んだ強さは `newGame` の `gameDidRestart` が送る（シートを閉じてそのまま
        // 遊んだ局は `level` 無しになる = 選ばれていない事実をそのまま表す）。
        if isFreshStart { pendingInitialStart = true }
    }

    /// 開始シートを出す局の `game_start` は、最初の操作かシートを閉じた時点まで遅らせる（#1372）。
    /// シートで「開始」を押すと `newGame` が選んだ強さ付きで数えるので、`init` で先に数えると
    /// 1 局が 2 回 `game_start` になる（`game_end` は 1 回）。冪等で、2 回目以降は何もしない。
    @ObservationIgnored private var pendingInitialStart = false

    public func startPlayIfPending() {
        guard pendingInitialStart else { return }
        pendingInitialStart = false
        services?.gameDidStart(gameID: gameID)
    }

    /// 盤面へのタップ。**盤外の座標を渡してよい**（範囲判定もここで行う）。
    ///
    /// 打てない理由はすべて `reject(_:)` を通す。View 側で早期 return させると、
    /// 「タップしたのに何も起きない = アプリが固まったように見える」状態が残る（#202）。
    public func tap(row: Int, col: Int) {
        // 決着後は結果表示が出ているので、拒否として鳴らさず黙って無視する。
        guard !gameOver else { return }
        guard !isAITurn else { return reject(.notYourTurn) }
        guard row >= 0, row < gomokuBoardSize,
              col >= 0, col < gomokuBoardSize else { return reject(.outOfBoard) }
        guard board[row, col] == nil else { return reject(.occupied) }
        if let reason = forbiddenReason(row: row, col: col) { return reject(.forbidden(reason)) }
        place(row: row, col: col)
    }

    /// 現在の手番がその交点へ打てない禁じ手の理由（#441）。打てるなら `nil`。
    ///
    /// 禁じ手ルールがオフのとき、または手番が白のときは常に `nil`（＝従来の自由五目）。
    public func forbiddenReason(row: Int, col: Int) -> GomokuForbidden? {
        guard forbiddenMovesEnabled, currentStone == .black else { return nil }
        return board.renjuForbidden(row: row, col: col)
    }

    /// 打てないタップを記録し、触覚・効果音で拒否を伝える（#202）。
    private func reject(_ reason: GomokuTapRejection) {
        lastRejection = reason
        rejectedTapCount += 1
        services?.feedback.notify(.warning)
    }

    private func place(row: Int, col: Int) {
        let mover = currentStone
        // 打てた時点で直前の拒否は解消している。View の禁じ手表示もここで消える（#441）。
        lastRejection = nil
        // 盤が動いたらヒントの印は用済み（#1118）。示した交点に打ったかどうかは問わない。
        hintPoint = nil
        board[row, col] = currentStone
        moves.append((row, col, currentStone))
        lastMove = (row, col)
        moveCount += 1
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        startPlayIfPending()
        services?.gameDidProgress(gameID: gameID)
        if let line = board.winningLine(row: row, col: col) {
            winningLine = line
            winner = currentStone
            services?.feedback.notify(mover == humanSide ? .success : .error)
            startPlayIfPending()
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: mover == humanSide ? .win : .loss,
                score: hints.winLossScore
            )
        } else if board.isFull {
            isDraw = true
            services?.feedback.notify(.warning)
            startPlayIfPending()
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .draw, score: hints.winLossScore)
        } else {
            currentStone = currentStone.opponent
            // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
            if mover == humanSide { services?.feedback.impact(.medium) }
        }
        persist()
    }

    #if DEBUG
    /// 撮影用（#366）: 中盤風の盤面を作る（`-gomokuMidgame` 起動引数）。
    /// 五連にならない固定手順で、人間（黒）の手番で止まるため CPU は動き出さない。
    public func applyPreviewMidgameForTesting() {
        guard moveCount == 0, !gameOver else { return }
        let preset: [(Int, Int)] = [(7, 7), (7, 8), (8, 8), (8, 7), (6, 8),
                                    (6, 7), (8, 6), (7, 6), (9, 7), (9, 9)]
        for (row, col) in preset where board[row, col] == nil && !gameOver {
            place(row: row, col: col)
        }
    }

    /// 撮影用（#441）: 禁じ手で断られた直後の画面を作る（`-gomokuRenjuBlocked` 起動引数）。
    ///
    /// 三三は交互着手の固定手順では作りにくいので盤を直接組み、最後に禁じ手の交点を
    /// 叩いて拒否を起こす。`persist()` を通さないので中断データは汚さない。
    public func applyRenjuBlockedPreviewForTesting() {
        guard moveCount == 0, !gameOver else { return }
        forbiddenMovesEnabled = true
        humanSide    = .black
        currentStone = .black
        var preview = GomokuBoard()
        for (row, col) in [(7, 5), (7, 6), (5, 7), (6, 7)] { preview[row, col] = .black }
        for (row, col) in [(6, 9), (8, 5), (5, 9), (9, 6)] { preview[row, col] = .white }
        board     = preview
        moveCount = 8
        lastMove  = (9, 6)
        tap(row: 7, col: 7)   // 三三 → 拒否され、盤の上に理由が出る
    }
    #endif

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧盤面で選んだ手が新しい盤面に着手されてしまう。
        // 計算開始時の `aiTurnKey` と一致する場合だけ着手する（#531 で共通化）。
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isThinking) {
            let b = board
            let s = currentStone
            let level = aiLevel

            let renju = forbiddenMovesEnabled

            return await Task.detached(priority: .userInitiated) {
                await SimpleGomokuEngine(level: level, forbiddenMoves: renju).bestMove(board: b, stone: s)
            }.value
        } commit: { move in
            guard isAITurn, let (r, c) = move, board[r, c] == nil else { return }
            place(row: r, col: c)
        }
    }

    // MARK: - ヒント（#1118）

    /// ヒントで示している交点。着手・待った・新規対局・投了で消える（盤が変われば印は嘘になる）。
    /// **永続化しない** — 中断データに残すのは使った回数だけ（将棋・チェスと同じ）。
    public private(set) var hintPoint: GomokuPoint?
    /// ヒントの読みの最中か。CPU の思考（`isThinking`）とは別に持つ
    /// （同じ旗にすると、ヒントを読んでいるあいだ盤が「思考中…」と名乗る）。
    public private(set) var isHintThinking: Bool = false

    /// 残り回数（`BoardHintButton` が読む）。
    public var hintsRemaining: Int { hints.remaining }

    /// いまヒントを押せるか。**自分の手番で、対局中で、残りが在るとき**だけ。
    public var canUseHint: Bool {
        !gameOver && !hints.isExhausted && !isAITurn && !isThinking && !isHintThinking
    }

    /// 現在の盤面の最善手を 1 手求め、盤の上に示す（#1118。将棋・チェスと同型）。
    ///
    /// 読みは CPU の着手と同じ `AITurnGuarded` の照合に載せる（#531）。**求まらなかった局・
    /// 盤が変わった局では回数を減らさない**。禁じ手ルールは今の対局の設定をそのまま渡す
    /// （渡さないと、黒に三三の点を勧めて「打てません」と断られる手を示してしまう・#441）。
    public func requestHint() async {
        guard canUseHint else { return }
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isHintThinking) {
            let b = board
            let stone = currentStone
            let renju = forbiddenMovesEnabled
            return await Task.detached(priority: .userInitiated) {
                // ヒントは対局中の CPU の強さに関わらず常に最強で読む（`BoardHintBudget.engineLevel`）。
                // 五目並べの level 0（弱）は探索せず確率で見逃すので、合わせると最善手にならない（#665）。
                await SimpleGomokuEngine(level: BoardHintBudget.engineLevel, forbiddenMoves: renju)
                    .bestMove(board: b, stone: stone)
            }.value
        } commit: { move in
            // `canUseHint` は読みの旗が立ったままなのでここでは使えない。前提を個別に確かめ直す。
            guard !gameOver, !isAITurn, !hints.isExhausted,
                  let (row, col) = move, board[row, col] == nil,
                  hints.consume() else { return }
            startPlayIfPending()
            services?.gameDidUseHint(gameID: gameID)
            hintPoint = GomokuPoint(row: row, col: col)
            services?.feedback.impact(.light)
            // 残り回数は中断データに持ち回る（再開でヒントが 3 回に戻らないように）。
            persist()
        }
    }

    public func newGame(humanSide: GomokuStone = .black, aiLevel: Int = 1, forbiddenMoves: Bool = false) {
        board          = GomokuBoard()
        currentStone   = .black
        self.humanSide = humanSide
        self.aiLevel   = aiLevel
        forbiddenMovesEnabled = forbiddenMoves
        lastRejection  = nil
        winningLine    = nil
        winner         = nil
        isDraw         = false
        lastMove       = nil
        moveCount      = 0
        moves          = []
        undoUsed       = false
        resigned       = false
        // ヒントは 1 局ごとに 3 回へ戻す（#1118）。前の局の印も残さない。
        hints.reset()
        hintPoint      = nil
        recordResult   = nil
        startedAt      = Date()
        gameSerial    += 1
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする。
        // 旧タスクは gameSerial が変わったことを見て着手もフラグ操作も行わない。
        isThinking     = false
        // ヒントの読みも同じ理由で下ろす（#1118）。旧タスクの defer は対局が変わると旗に触らない。
        isHintThinking = false
        persist()
        pendingInitialStart = false
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: aiLevel))
    }

    // MARK: - 投了

    public func resign() {
        guard !gameOver else { return }
        // 投了で盤の意味が変わるので、直前の拒否の理由も一緒に片付ける（#518）。
        lastRejection = nil
        // ヒントの印も同じ理由で片付ける（#1118）。
        hintPoint = nil
        resigned = true
        winner = humanSide.opponent
        services?.feedback.notify(.error)
        startPlayIfPending()
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: hints.winLossScore)
        persist()
    }

    // MARK: - 待った（自分の直前手＋CPU 応手の 2 手を戻す）

    private func mover(at index: Int) -> GomokuStone {
        index % 2 == 0 ? .black : .white
    }

    /// 人間の手番で、直前の自分の手と CPU 応手をまとめて戻せるか。
    public var canUndo: Bool {
        guard !gameOver, !isAITurn, !isThinking else { return false }
        let n = moves.count
        guard n >= 2 else { return false }
        return mover(at: n - 1) == humanSide.opponent && mover(at: n - 2) == humanSide
    }

    /// 待った: 直前 2 手（人間→CPU）を巻き戻し、人間が指し直せる状態にする。
    public func undoLastExchange() {
        guard canUndo else { return }
        // 盤が2手ぶん戻ると禁じ手の成立条件も変わるので、古い理由の帯を残さない（#518）。
        lastRejection = nil
        // ヒントの印も 2 手前の盤には合わないので消す（#1118。回数は戻さない）。
        hintPoint = nil
        moves.removeLast(2)
        board        = Self.board(from: moves)
        moveCount    = moves.count
        winner       = nil
        isDraw       = false
        undoUsed     = true
        if let last = moves.last {
            lastMove     = (last.row, last.col)
            currentStone = last.stone.opponent
        } else {
            lastMove     = nil
            currentStone = .black
        }
        persist()
    }

    /// 広告を出す前に控えた `aiTurnKey`（対局の通し番号 × 手数）の局面にだけ待ったを適用する（#729）。
    /// - Returns: 戻せたか。広告のあいだに新規対局・投了・着手で局面が変わっていたら false
    ///   （View は「待ったを使えなかった」と知らせる）。対局の番号だけを照合すると、ロード中に
    ///   1 往復打ったとき、広告を出したときとは別の 1 往復が戻る。
    @discardableResult
    public func undoLastExchange(forTurn turn: AITurnKey) -> Bool {
        guard turn == aiTurnKey, canUndo else { return false }
        undoLastExchange()
        return true
    }

    /// 復元してよい中断データか。座標は盤の内側、手順が無い旧形式は盤の升数が合っていること。
    private static func isRestorable(_ snap: GomokuSnapshot) -> Bool {
        if let history = snap.moveHistory {
            return history.allSatisfy {
                (0..<gomokuBoardSize).contains($0.row) && (0..<gomokuBoardSize).contains($0.col)
            }
        }
        return snap.cells.count == gomokuBoardSize * gomokuBoardSize
    }

    private static func board(from moves: [(row: Int, col: Int, stone: GomokuStone)]) -> GomokuBoard {
        var board = GomokuBoard()
        for move in moves {
            board[move.row, move.col] = move.stone
        }
        return board
    }

    private func persist() {
        guard !gameOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt,
            moveHistory: moves.map { GomokuMoveRecord(row: $0.row, col: $0.col, stone: $0.stone.rawValue) },
            undoUsed: undoUsed,
            resigned: resigned ? true : nil,
            winner: winner?.rawValue,
            forbiddenMoves: forbiddenMovesEnabled ? true : nil,
            hintsUsed: hints.used
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }
}
