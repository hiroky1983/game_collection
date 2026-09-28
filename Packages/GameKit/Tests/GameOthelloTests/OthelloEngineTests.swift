import Testing
import Foundation
import CoreEngine
@testable import GameOthello

/// CPU の難易度カーブの回帰テスト（#1013）。
///
/// **レベルどうしの勝率の実測は `-O` の単体バイナリで行い、結果は #1013 / PR の表に残す。**
/// ここに入れるのは CI（最適化なしのデバッグビルド）で現実的な時間に収まるものだけ:
/// 深さ 3・5 の探索を自己対戦させると 1 局で数十秒かかるため、置けるのは
/// ①「弱」の打ち方（読まずに最も多く返る手を選ぶ）②探索を一切しない「弱」の直接対戦、の 2 つ。
@Suite("オセロ CPU の難易度")
struct OthelloEngineTests {

    // MARK: - 弱（読まない）

    /// 角を取れるが返る石は 1 枚、別の手なら 3 枚返る盤面。
    /// 「弱」は角の価値を知らないので**枚数の多い方**を選ぶ（#1013。
    /// 位置評価を見る実装に戻すと角を取るのでこのテストが落ちる）。
    @Test("弱は角より返る枚数を優先する")
    func weakPrefersFlipCountOverCorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        // 上端の行: (0,0) が空き・(0,1) が白・(0,2) が黒 → (0,0) に黒を置くと 1 枚返る。
        cells[0 * othelloBoardSize + 1] = .white
        cells[0 * othelloBoardSize + 2] = .black
        // 中央の列: (4,3) が空き・(3,3)(2,3)(1,3) が白・(0,3) が黒 → (4,3) に置くと 3 枚返る。
        cells[3 * othelloBoardSize + 3] = .white
        cells[2 * othelloBoardSize + 3] = .white
        cells[1 * othelloBoardSize + 3] = .white
        cells[0 * othelloBoardSize + 3] = .black
        let board = OthelloBoard(cells: cells)

        #expect(board.flippable(row: 0, col: 0, stone: .black).count == 1)
        #expect(board.flippable(row: 4, col: 3, stone: .black).count == 3)

        let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        #expect(move?.row == 4 && move?.col == 3, "弱が角 (0,0) を取った: \(String(describing: move))")
    }

    @Test("弱は同じ盤面に必ず同じ手を返す")
    func weakIsDeterministic() async {
        let board = OthelloBoard()
        let first = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        for _ in 0..<20 {
            let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
            #expect(move?.row == first?.row && move?.col == first?.col)
        }
    }

    @Test("打てる手が無ければ nil、あれば必ず合法手")
    func returnsLegalMoveOnly() async throws {
        let board = OthelloBoard()
        let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        let unwrapped = try #require(move)
        #expect(board.isValid(row: unwrapped.row, col: unwrapped.col, stone: .black))

        // 白で埋めた盤は黒に打つ手が無い。
        let full = OthelloBoard(cells: [OthelloStone?](
            repeating: .white, count: othelloBoardSize * othelloBoardSize))
        let none = await OthelloEngine(level: 0).bestMove(board: full, stone: .black)
        #expect(none?.row == nil)
    }

    // MARK: - 「弱」の勝率（#1013）

    /// でたらめに打つ相手との直接対戦。**「弱」は探索しないのでデバッグビルドでも一瞬で終わる。**
    ///
    /// 上限は「初心者が安定して勝てる弱さ」の担保（位置評価を見ていた以前の実装は同じ条件で
    /// 88.3%・平均 +16.9 石だったので、戻すとこのテストが落ちる）。下限は弱くしすぎの検知。
    @Test("弱はでたらめな相手に勝ったり負けたりする")
    func weakWinRateAgainstRandom() async {
        let games = 60
        var wins = 0
        for i in 0..<games {
            let weakIsBlack = i % 2 == 0
            let result = await OthelloSelfPlay.play(
                black: weakIsBlack ? .weak : .random,
                white: weakIsBlack ? .random : .weak,
                seed: UInt64(i) &+ 1)
            let weakStones = weakIsBlack ? result.black : result.white
            let randomStones = weakIsBlack ? result.white : result.black
            if weakStones > randomStones { wins += 1 }
        }
        let rate = Double(wins) / Double(games)
        #expect(rate <= 0.75, "弱がでたらめな相手に \(wins)/\(games) 勝っている（強すぎる）")
        #expect(rate >= 0.35, "弱がでたらめな相手に \(wins)/\(games) しか勝てない（弱すぎる）")
    }

    // MARK: - 時間切れ時の反復深化（#1133）

    /// 時間切れのとき、`rootSearch` が単独で返す不完全な結果（未評価の候補手が残ったまま・
    /// `negamax` が壊れた評価値で埋めた `alpha`）をそのまま使わないことを固定する。
    /// 呼び出し時点で既に期限切れなら、深さ 1 すら読み切れないので `moves[0]` に倒す。
    @Test("時間切れが呼び出し時点で既に発生していれば moves[0] に倒す")
    func iterativeDeepeningFallsBackWhenAlreadyExpired() async {
        let board = OthelloBoard()
        let moves = board.validMoves(for: .black)
        let engine = OthelloEngine(level: CPUStrength.hard.rawValue, timeLimitOverride: -1)
        let move = await engine.bestMove(board: board, stone: .black)
        #expect(move?.row == moves[0].0 && move?.col == moves[0].1,
                "期限切れ時に moves[0] 以外を返している（読み残しの評価に頼っている）: \(String(describing: move))")
    }

    /// 角を取れば圧勝的に評価が高くなるが、`validMoves`（左上から生成）の並びでは角より
    /// 先に来る手がもう1つある局面（CodeRabbit 指摘: 初期盤面は対称で `moves[0]` と
    /// 深さ1の最善手が偶然一致してしまい、フォールバックとの区別が付かない）。
    private func asymmetricBoardWithLateCorner() -> OthelloBoard {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        // (3,2) に黒を置くと (3,3) の白を挟んで1枚返る（validMoves では先に生成される）。
        cells[3 * othelloBoardSize + 3] = .white
        cells[3 * othelloBoardSize + 4] = .black
        // (7,7)（右下の角）に黒を置くと (6,6) の白を挟んで1枚返る。
        cells[6 * othelloBoardSize + 6] = .white
        cells[5 * othelloBoardSize + 5] = .black
        return OthelloBoard(cells: cells)
    }

    /// 反復深化は「時間切れになった深さ」の結果を丸ごと捨て、直前の読み切った深さの結果を使う
    /// （#1133）。実時間には依存しない（CodeRabbit 指摘: 所要時間の実測はスケジューラ停止・
    /// CI 負荷でフレークする）。`now` を注入し、深さ1の探索に要した `now()` 呼び出し回数を
    /// 数えてから、その直後にだけ「期限切れ」へ切り替わる固定時計で深さ2以降を確実に打ち切る。
    @Test("時間切れのときは直前に読み切った深さの結果を使う")
    func iterativeDeepeningUsesLastCompletedDepth() async throws {
        let board = asymmetricBoardWithLateCorner()
        let moves = board.validMoves(for: .black)
        try #require(moves.count == 2, "前提が崩れている: 局面の合法手が想定と違う（\(moves)）")
        try #require(!(moves[0].0 == 7 && moves[0].1 == 7),
                     "前提が崩れている: 角が validMoves の先頭に来ている（非対称にならない）")

        let deadline = Date().addingTimeInterval(600)
        let before = Date()
        let after = Date().addingTimeInterval(1_200)

        // 深さ1のみ／深さ2まで、それぞれ反復深化を1回走らせ、あいだの now() 呼び出し回数を数える。
        let counter1 = CallCountingClock()
        let depth1Only = OthelloEngine(level: CPUStrength.hard.rawValue, now: counter1.now)
            .iterativeDeepening(moves, board: board, stone: .black, maxDepth: 1, deadline: deadline)
        #expect(depth1Only.0 == 7 && depth1Only.1 == 7,
                "前提が崩れている: 深さ1の最善手が角を取っていない（評価関数の重みが変わった？）")
        #expect(!(depth1Only.0 == moves[0].0 && depth1Only.1 == moves[0].1),
                "前提が崩れている: 深さ1の最善手が moves[0] と同じで、フォールバックと区別できない")
        let depth1Calls = counter1.callCount

        let counter2 = CallCountingClock()
        _ = OthelloEngine(level: CPUStrength.hard.rawValue, now: counter2.now)
            .iterativeDeepening(moves, board: board, stone: .black, maxDepth: 2, deadline: deadline)
        let depth1And2Calls = counter2.callCount
        try #require(depth1And2Calls > depth1Calls + 4,
                     "前提が崩れている: 深さ2の呼び出し回数が少なすぎて途中で打ち切るタイミングを作れない")

        // 深さ1は確実に完了させ、深さ2は「開始はするが呼び出しの半ばで期限切れになる」
        // タイミングに切り替える。rootSearch/negamax の途中経過（不完全な best・壊れた
        // 評価値）が最終結果に混ざっていないかを検証できる。
        let switchAt = depth1Calls + (depth1And2Calls - depth1Calls) / 2
        let switching = SwitchingClock(switchAfterCalls: switchAt, before: before, after: after)
        let switchingEngine = OthelloEngine(level: CPUStrength.hard.rawValue, now: switching.now)
        let result = switchingEngine.iterativeDeepening(moves, board: board, stone: .black,
                                                        maxDepth: OthelloEngine.hardMaxDepth, deadline: deadline)
        #expect(result.0 == depth1Only.0 && result.1 == depth1Only.1,
                "深さ1の結果と異なる（未完了の深い探索の結果が混入している可能性）")
    }
}

/// `now()` の呼び出し回数だけを数える実時計（#1133 回帰テスト用）。
private final class CallCountingClock: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callCount = 0
    func now() -> Date {
        lock.lock(); callCount += 1; lock.unlock()
        return Date()
    }
}

/// `switchAfterCalls` 回目までは `before` を、それ以降は `after` を返す固定時計
/// （#1133 回帰テスト用）。実時間を一切使わないため、CI の速度差でフレークしない。
private final class SwitchingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let switchAfterCalls: Int
    private let before: Date
    private let after: Date
    init(switchAfterCalls: Int, before: Date, after: Date) {
        self.switchAfterCalls = switchAfterCalls
        self.before = before
        self.after = after
    }
    func now() -> Date {
        lock.lock(); callCount += 1; let c = callCount; lock.unlock()
        return c <= switchAfterCalls ? before : after
    }
}

// MARK: - 根の αβ と局面数の上限（#1401）

@Suite("オセロ 探索の打ち切り")
struct OthelloSearchBudgetTests {

    /// 根で αβ を効かせても、選ぶ手の点数は全幅で読んだ最善と一致する（刈り込みで最善を落としていない）。
    @Test("根の刈り込みは全幅の最善と同じ点数の手を選ぶ")
    func rootPruningKeepsTheBestScore() {
        let engine = OthelloEngine(level: CPUStrength.normal.rawValue)
        for seed in 1...6 {
            var board = OthelloBoard()
            var rng = MMIXRandom(seed: UInt64(seed))
            var stone = OthelloStone.black
            for _ in 0..<(6 + seed * 3) {
                let moves = board.validMoves(for: stone)
                guard !moves.isEmpty else { break }
                let m = moves[Int(rng.next() % UInt64(moves.count))]
                board.place(row: m.0, col: m.1, stone: stone)
                stone = stone.opponent
            }
            let moves = board.validMoves(for: stone)
            guard !moves.isEmpty else { continue }
            func fullWidthScore(_ m: (Int, Int)) -> Int {
                var b = board
                b.place(row: m.0, col: m.1, stone: stone)
                var nodes = 0
                return -engine.negamax(b, stone: stone.opponent, depth: 2, alpha: -Int.max, beta: Int.max,
                                       deadline: .distantFuture, nodes: &nodes, nodeLimit: .max)
            }
            let expected = moves.map(fullWidthScore).max()
            let chosen = engine.iterativeDeepening(moves, board: board, stone: stone, maxDepth: 3,
                                                   deadline: .distantFuture)
            #expect(fullWidthScore((chosen.row, chosen.col)) == expected, "seed \(seed): 刈り込みで最善を落とした")
        }
    }

    /// 局面数の上限に達したら、その深さの結果は捨てて前の深さの手を使う。上限 0 では深さ 1 すら
    /// 読み切れないので `moves[0]` に倒す。時計には依存しない（`deadline` は遠い未来）。
    @Test("局面数の上限で読み切れなければ moves[0] に倒す")
    func nodeLimitFallsBackToFirstMove() {
        let board = OthelloBoard()
        let moves = board.validMoves(for: .black)
        let engine = OthelloEngine(level: CPUStrength.hard.rawValue)
        let move = engine.iterativeDeepening(moves, board: board, stone: .black, maxDepth: 5,
                                             deadline: .distantFuture, nodeLimit: 0)
        #expect(move.row == moves[0].0 && move.col == moves[0].1)
    }

    /// 強さは時計で変わらない: 同じ局面には、時計が速くても遅くても同じ手を返す（局面数が主）。
    @Test("むずかしいは時計が違っても同じ手を返す")
    func hardMoveIsIndependentOfClock() {
        let board = OthelloBoard()
        let slow = OthelloEngine(level: CPUStrength.hard.rawValue,
                                 now: { Date(timeIntervalSince1970: 0) })
        let fast = OthelloEngine(level: CPUStrength.hard.rawValue)
        let a = slow.move(board: board, stone: .black)
        let b = fast.move(board: board, stone: .black)
        #expect(a?.row == b?.row && a?.col == b?.col)
    }
}

// MARK: - 入門（#1174）

@Suite("オセロ 入門")
struct OthelloNoviceAndSeriousTests {

    private static let novice = CPUStrength.novice.rawValue

    /// 入門は角が取れても取らない（#1401。2 手読んで自分にいちばん不利な手を選ぶので、角は選ばれない）。
    /// 以前（#1174）は「取れる角は取る」だったが、簡単に負け越さなかったので悪手そのものを選ぶ形にした。
    @Test("入門は取れる角を取らない")
    func noviceDoesNotTakeTheCorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        cells[0 * othelloBoardSize + 1] = .white
        cells[0 * othelloBoardSize + 2] = .black
        cells[3 * othelloBoardSize + 3] = .white
        cells[2 * othelloBoardSize + 3] = .white
        cells[1 * othelloBoardSize + 3] = .white
        cells[0 * othelloBoardSize + 3] = .black
        let board = OthelloBoard(cells: cells)
        #expect(board.isValid(row: 0, col: 0, stone: .black))

        let move = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        #expect(!(move?.row == 0 && move?.col == 0), "入門が角を取った: \(String(describing: move))")
    }

    /// 角が無いときは**角のとなり**（X打ち・C打ち）へ飛びつく。初心者の癖をそのまま真似ている。
    @Test("入門は角のとなりを選ぶ")
    func novicePrefersTheSquaresNextToACorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        // (1,1)（X打ち）に黒を置くと 1 枚返る。
        cells[2 * othelloBoardSize + 2] = .white
        cells[3 * othelloBoardSize + 3] = .black
        // (5,4) に黒を置くと 3 枚返る（枚数だけなら簡単はこちらを選ぶ）。
        cells[4 * othelloBoardSize + 4] = .white
        cells[3 * othelloBoardSize + 4] = .white
        cells[2 * othelloBoardSize + 4] = .white
        cells[1 * othelloBoardSize + 4] = .black
        let board = OthelloBoard(cells: cells)
        #expect(board.flippable(row: 1, col: 1, stone: .black).count == 1)
        #expect(board.flippable(row: 5, col: 4, stone: .black).count == 3)

        let novice = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        #expect(novice?.row == 1 && novice?.col == 1, "入門が角のとなりを選ばない: \(String(describing: novice))")
        let easy = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        #expect(easy?.row == 5 && easy?.col == 4, "前提が崩れている: 簡単は枚数で選ぶ")
    }

    @Test("入門は同じ盤面に必ず同じ手を返す")
    func noviceIsDeterministic() async {
        let board = OthelloBoard()
        let first = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        for _ in 0..<20 {
            let move = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
            #expect(move?.row == first?.row && move?.col == first?.col)
        }
    }

    /// 入門は簡単に負け越す。どちらも決定的な打ち方なので同じ手順しか作れず、
    /// **最初の 8 手をでたらめに進めてから**戦わせて局面を散らす。
    @Test("入門は簡単に負け越す")
    func noviceLosesToEasy() async {
        let games = 12
        var wins = 0
        for i in 0..<games {
            let noviceIsBlack = i % 2 == 0
            let result = await OthelloSelfPlay.play(
                black: noviceIsBlack ? .level(Self.novice) : .level(0),
                white: noviceIsBlack ? .level(0) : .level(Self.novice),
                seed: UInt64(i) &+ 1, openingPlies: 8)
            let mine = noviceIsBlack ? result.black : result.white
            let theirs = noviceIsBlack ? result.white : result.black
            if mine > theirs { wins += 1 }
        }
        print("othello novice vs easy: \(wins)/\(games)")
        #expect(wins <= games / 10, "入門が簡単に \(wins)/\(games) 勝っている（段の順が崩れている）")
    }
}

// MARK: - 自己対戦（テスト用）

enum OthelloSelfPlay {
    enum Side: Equatable {
        case weak
        /// 出荷している段階そのもの（#1174。段の番号から `OthelloEngine` を作る）。
        case level(Int)
        case random
    }

    struct Result {
        var black: Int
        var white: Int
    }

    /// - Parameter openingPlies: 最初の何手をでたらめに打つか。決定的な段どうしを
    ///   何局も戦わせるために使う（同じ手順を繰り返すと 1 局しか作れないため・#1174）。
    static func play(black: Side, white: Side, seed: UInt64, openingPlies: Int = 0) async -> Result {
        var board = OthelloBoard()
        // 決定的な擬似乱数（でたらめ役の手を再現可能にする）。共通の `MMIXRandom`（#1150）。
        var rng = MMIXRandom(seed: seed)
        var stone = OthelloStone.black
        var ply = 0
        while true {
            let moves = board.validMoves(for: stone)
            if moves.isEmpty {
                if board.validMoves(for: stone.opponent).isEmpty { break }
                stone = stone.opponent
                continue
            }
            var chosen = moves[Int(rng.next() % UInt64(moves.count))]
            defer { ply += 1 }
            if ply < openingPlies {
                board.place(row: chosen.0, col: chosen.1, stone: stone)
                stone = stone.opponent
                continue
            }
            switch stone == .black ? black : white {
            case .weak:
                if let move = await OthelloEngine(level: 0).bestMove(board: board, stone: stone) {
                    chosen = move
                }
            case .level(let level):
                if let move = await OthelloEngine(level: level).bestMove(board: board, stone: stone) {
                    chosen = move
                }
            case .random:
                break
            }
            board.place(row: chosen.0, col: chosen.1, stone: stone)
            stone = stone.opponent
        }
        return Result(black: board.count(for: .black), white: board.count(for: .white))
    }
}
