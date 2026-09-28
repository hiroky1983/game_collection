import Testing
import Foundation
import CoreEngine
@testable import GameOthello

/// CPU の段階の回帰テスト（#1013・#1464）。
///
/// **段階どうしの勝率の実測は `-O` の単体バイナリで行い、結果は `docs/analytics/othello-1464-ladder.md` に残す。**
/// ここに入れるのは CI（最適化なしのデバッグビルド）で現実的な時間に収まるものだけ。
@Suite("オセロ CPU の難易度")
struct OthelloEngineTests {

    // MARK: - 段階の設定（#1464）

    /// 段階の差は時間・深さの上限・最善手の確率の 3 つだけ（会長決裁 2026-09-27）。値を変えたら段階表を測り直すこと。
    @Test("段階の設定は決裁値（時間・深さの上限・最善手の確率）")
    func settingsMatchTheDecision() {
        let novice = OthelloEngine.settings(for: .novice), easy = OthelloEngine.settings(for: .easy)
        let normal = OthelloEngine.settings(for: .normal), hard = OthelloEngine.settings(for: .hard)
        #expect(novice.timeLimit == 0.3 && novice.depthLimit == 1 && novice.policy.bestMoveProbability == 0.5)
        #expect(easy.timeLimit == 0.5 && easy.depthLimit == 3 && easy.policy.bestMoveProbability == 0.6)
        #expect(normal.timeLimit == 1.0 && normal.depthLimit == 5 && normal.policy.bestMoveProbability == 0.9)
        #expect(hard.timeLimit == 1.5 && hard.depthLimit == nil && hard.policy == .exact)
        for s in [novice, easy, normal] { #expect(s.policy.slipMargin == 40) }
        // 出荷のエンジンは局面数で打ち切らない（強さは時間と深さの上限で決まる）。
        #expect(OthelloEngine(level: CPUStrength.hard.rawValue).nodeLimit == .max)
    }

    @Test("深さの上限より深く読まない")
    func searchStopsAtTheDepthLimit() throws {
        let board = OthelloBoard()
        for (strength, limit) in [(CPUStrength.novice, 1), (.easy, 3), (.normal, 5)] {
            let r = try #require(OthelloEngine(level: strength.rawValue, timeLimitOverride: .infinity)
                .analyze(board: board, stone: .black))
            #expect(r.depth == limit, "\(strength.label) が深さ \(r.depth) まで読んだ")
        }
    }

    @Test("打てる手が無ければ nil、あれば必ず合法手")
    func returnsLegalMoveOnly() async throws {
        let board = OthelloBoard()
        for strength in CPUStrength.allCases where strength != .hard {
            let move = await OthelloEngine(level: strength.rawValue).bestMove(board: board, stone: .black)
            let unwrapped = try #require(move)
            #expect(board.isValid(row: unwrapped.row, col: unwrapped.col, stone: .black))
        }
        // 白で埋めた盤は黒に打つ手が無い。
        let full = OthelloBoard(cells: [OthelloStone?](
            repeating: .white, count: othelloBoardSize * othelloBoardSize))
        let none = await OthelloEngine(level: CPUStrength.novice.rawValue).bestMove(board: full, stone: .black)
        #expect(none?.row == nil)
    }

    // MARK: - 最善手を外すとき（#1464）

    /// 乱数で進めた局面。
    static func randomBoard(seed: UInt64, plies: Int) -> (OthelloBoard, OthelloStone) {
        var board = OthelloBoard()
        var rng = MMIXRandom(seed: seed)
        var stone = OthelloStone.black
        for _ in 0..<plies {
            var moves = board.validMoves(for: stone)
            if moves.isEmpty { stone = stone.opponent; moves = board.validMoves(for: stone) }
            guard !moves.isEmpty else { break }
            let m = moves[Int(rng.next() % UInt64(moves.count))]
            board.place(row: m.0, col: m.1, stone: stone)
            stone = stone.opponent
        }
        return (board, stone)
    }

    /// 外しの候補は、採点で最も高い手を含まず、最善から損の幅以内の手だけ。
    @Test("外しの候補は最善を除き、損の幅の中の手だけ")
    func slipPoolExcludesTheBestAndStaysWithinTheMargin() {
        for strength in [CPUStrength.novice, .easy] {
            let engine = OthelloEngine(level: strength.rawValue, seed: 1)
            for seed in 1...12 {
                let (board, stone) = Self.randomBoard(seed: UInt64(seed), plies: 8 + seed * 3)
                let moves = board.validMoves(for: stone)
                guard moves.count >= 2 else { continue }
                func score(_ m: (Int, Int)) -> Int {
                    var b = board
                    b.place(row: m.0, col: m.1, stone: stone)
                    var nodes = 0
                    return -engine.negamax(b, stone: stone.opponent, depth: engine.slipDepth - 1,
                                           alpha: -Int.max, beta: Int.max, deadline: .distantFuture,
                                           nodes: &nodes, nodeLimit: .max)
                }
                let best = moves.map(score).max()!
                let pool = engine.slipPool(moves, board: board, stone: stone)
                #expect(pool.count < moves.count, "\(strength.label) seed \(seed): 最善が候補に残っている")
                for m in pool {
                    #expect(score(m) >= best - OthelloEngine.slipMargin, "\(strength.label) seed \(seed): 損の幅を超えた手 \(m)")
                }
            }
        }
    }

    /// 外しの採点は、その段の深さの上限より深く読まない（入門は 1 手）。上限より深く読むと、外した手のほうが
    /// 探索の最善手より良い手になりうる（#1464 の段階表の注）。
    @Test("外しの採点はその段の深さの上限より深く読まない")
    func slipReadsNoDeeperThanTheLevel() {
        #expect(OthelloEngine(level: CPUStrength.novice.rawValue).slipDepth == 1)
        #expect(OthelloEngine(level: CPUStrength.easy.rawValue).slipDepth == 2)
        #expect(OthelloEngine(level: CPUStrength.normal.rawValue).slipDepth == 2)
    }

    /// 黒の唯一の手 (7,2) を打つと、白が (0,3) で上の辺を返して終局し、黒が 3 対 4 で負ける局面。
    private func boardWhoseOnlyMoveLosesAtOnce() -> OthelloBoard {
        var board = OthelloBoard(cells: [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize))
        board[0, 0] = .white
        board[0, 1] = .black
        board[0, 2] = .black
        board[7, 0] = .black
        board[7, 1] = .white
        return board
    }

    @Test("即負けの手を見分ける")
    func detectsAMoveThatLosesAtOnce() {
        let board = boardWhoseOnlyMoveLosesAtOnce()
        let moves = board.validMoves(for: .black)
        let onlyMove = moves.count == 1 && moves[0] == (7, 2)
        #expect(onlyMove, "前提が崩れている: \(moves)")
        #expect(OthelloEngine.allowsImmediateLoss(board, move: (7, 2), stone: .black))
        // 初期配置の手は即負けにならない。
        for m in OthelloBoard().validMoves(for: .black) {
            #expect(!OthelloEngine.allowsImmediateLoss(OthelloBoard(), move: m, stone: .black))
        }
    }

    /// 外しは即負けの手を選ばない。選べる手がそれしか無ければ、外さずに探索の手を打つ（ここでは唯一の合法手）。
    @Test("外しは即負けの手を選ばない")
    func slipNeverChoosesAnImmediateLoss() {
        let board = boardWhoseOnlyMoveLosesAtOnce()
        var rng = SplitMix64(seed: 1)
        let engine = OthelloEngine(level: CPUStrength.novice.rawValue, policy: OthelloEngine.policy(0), seed: 1)
        let slip = engine.slipMove(board.validMoves(for: .black), board: board, stone: .black, using: &rng)
        #expect(slip == nil)
        let move = engine.move(board: board, stone: .black)
        #expect(move?.row == 7 && move?.col == 2)

        // 乱数で進めた局面でも、外しの手は即負けの手にならない。
        for seed in 1...20 {
            let (b, stone) = Self.randomBoard(seed: UInt64(seed), plies: 40 + seed % 15)
            let moves = b.validMoves(for: stone)
            guard !moves.isEmpty else { continue }
            var r = SplitMix64(seed: UInt64(seed))
            if let m = engine.slipMove(moves, board: b, stone: stone, using: &r) {
                #expect(!OthelloEngine.allowsImmediateLoss(b, move: m, stone: stone))
            }
        }
    }

    /// 確率 0 なら（外しの候補がある局面では）探索の最善手と違う手を打つ。確率 1 は外さない。
    @Test("最善手の確率が 0 なら外し、1 なら外さない")
    func bestMoveProbabilityDecidesTheSlip() {
        var slipped = 0, compared = 0
        for seed in 1...12 {
            let (board, stone) = Self.randomBoard(seed: UInt64(seed), plies: 10 + seed)
            let moves = board.validMoves(for: stone)
            guard moves.count >= 2 else { continue }
            let exact = OthelloEngine(level: CPUStrength.easy.rawValue, timeLimitOverride: .infinity,
                                      policy: OthelloEngine.policy(1), seed: UInt64(seed))
            let always = OthelloEngine(level: CPUStrength.easy.rawValue, timeLimitOverride: .infinity,
                                       policy: OthelloEngine.policy(0), seed: UInt64(seed))
            let best = exact.move(board: board, stone: stone)!
            let again = exact.move(board: board, stone: stone)!
            let same = best == again
            #expect(same, "確率 1 なのに手が揺れた")
            guard !always.slipPool(moves, board: board, stone: stone).isEmpty else { continue }
            compared += 1
            let m = always.move(board: board, stone: stone)!
            #expect(board.isValid(row: m.row, col: m.col, stone: stone))
            if m != best { slipped += 1 }
        }
        #expect(compared > 0, "前提が崩れている: 外しの候補がある局面が 1 つも無い")
        #expect(slipped * 2 >= compared, "確率 0 なのに最善手ばかり打った: \(slipped)/\(compared)")
    }

    /// 入門（出荷値）は一様乱択の相手に大きく勝ち越す（決裁の基準は先後入れ替え 100 局で 8 割以上。実測は段階表）。
    /// 入門は 1 手先しか読まないのでデバッグビルドでも速い。種を固定して毎回同じ対局にする。
    @Test("入門は一様乱択の相手に勝ち越す")
    func noviceBeatsRandom() async {
        let games = 20
        var wins = 0
        for i in 0..<games {
            let noviceIsBlack = i % 2 == 0
            let novice = OthelloSelfPlay.Side.level(CPUStrength.novice.rawValue)
            let result = await OthelloSelfPlay.play(
                black: noviceIsBlack ? novice : .random,
                white: noviceIsBlack ? .random : novice,
                seed: UInt64(i / 2) &+ 1)
            let mine = noviceIsBlack ? result.black : result.white
            let theirs = noviceIsBlack ? result.white : result.black
            if mine > theirs { wins += 1 }
        }
        #expect(wins >= 14, "入門が一様乱択の相手に \(wins)/\(games) しか勝てない")
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
                                                        maxDepth: 5, deadline: deadline)
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

    /// 局面数で打ち切る計測用のエンジン（`CPUBenchLadder.engine`）は時計に依存しない: 時計が止まっていても
    /// 進んでいても同じ手を返す（計測の対局を同時に回しても強さが揺れない）。
    @Test("局面数で打ち切るエンジンは時計が違っても同じ手を返す")
    func nodeLimitedEngineIsIndependentOfClock() {
        let board = OthelloBoard()
        let stopped = OthelloEngine(level: CPUStrength.hard.rawValue, timeLimitOverride: .infinity,
                                    nodeLimit: 20_000, now: { Date(timeIntervalSince1970: 0) })
        let running = OthelloEngine(level: CPUStrength.hard.rawValue, timeLimitOverride: .infinity, nodeLimit: 20_000)
        let a = stopped.move(board: board, stone: .black)
        let b = running.move(board: board, stone: .black)
        #expect(a?.row == b?.row && a?.col == b?.col)
    }
}

// MARK: - 自己対戦（テスト用）

enum OthelloSelfPlay {
    enum Side: Equatable {
        /// 出荷している段階そのもの（#1174。段の番号から `OthelloEngine` を作る。乱数の種は対局と手数から決める）。
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
            case .level(let level):
                let engine = OthelloEngine(level: level, seed: seed &* 1_000 &+ UInt64(ply))
                if let move = await engine.bestMove(board: board, stone: stone) {
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
