import Testing
import Foundation
import CoreEngine
@testable import GameShogi

/// 最善手を外すときの手の選び方と局面数の上限（#1461）。数秒で終わるものだけを置く。
/// CPU 同士の対局・所要時間の計測は `CPUBenchTests`（`CPU_BENCH=1` のときだけ）。
@Suite("将棋の難易度: 最善手の確率と外したときの手（#1461）")
struct ShogiMovePolicyTests {

    /// 歩が只で取れる局面で、取らずに別の手を指す割合。外したときは最善（取る手）を除いて選ぶので、
    /// 割合は 1 − 確率にそのまま近づく。
    private func missRate(probability: Double, trials: Int) async -> Double {
        let sfen = "4k4/9/9/4p4/4G4/9/9/9/4K4 b - 1"
        let policy = SimpleMinimaxEngine.policy(probability)
        var missed = 0
        for seed in 1...UInt64(trials) {
            let e = SimpleMinimaxEngine(depth: 2, usePositional: false, useQuiescence: false, useBook: false,
                                        timeLimit: .infinity, policy: policy, seed: seed)
            if await e.bestMove(sfen: sfen) != "5e5d" { missed += 1 }
        }
        return Double(missed) / Double(trials)
    }

    @Test("最善手を外す割合が設定した確率どおりになる（0% と 100% の両端を含む）")
    func missRateFollowsTheProbability() async {
        #expect(await missRate(probability: 1, trials: 20) == 0)
        #expect(await missRate(probability: 0, trials: 20) == 1, "確率 0% は最善手を一度も指さない")
        for p in [0.1, 0.5, 0.8] {
            let rate = await missRate(probability: p, trials: 400)
            #expect(abs(rate - (1 - p)) < 0.09, "確率 \(p) の外し率が \(rate)（期待 \(1 - p)）")
        }
    }

    /// 黒は 1i の玉と 5g の歩だけで、白は 2h の飛車と持ち駒の金。歩を動かす手など、黒が何を指しても
    /// 白の金打ちで詰まされる手が多い（詰まされる手・そうでない手の両方があることはテストで確かめる）。
    private let matingThreat = "4k4/9/9/9/9/9/4P4/7r1/8K b g 1"

    private func exactEngine(seed: UInt64, margin: Int = SimpleMinimaxEngine.slipMargin) -> SimpleMinimaxEngine {
        SimpleMinimaxEngine(depth: 2, usePositional: true, useQuiescence: true, useBook: false, timeLimit: .infinity,
                            policy: ShogiMovePolicy(bestMoveProbability: 0, slipMargin: margin), seed: seed)
    }

    @Test("外したときの手に、次の一手で詰まされる手は入らない")
    func slipNeverWalksIntoMate() {
        let pos = Position.fromSFEN(matingThreat)!
        let moves = pos.legalMoves()
        var probe = pos
        let mating = Set(moves.filter { SimpleMinimaxEngine.allowsMateInOne(&probe, after: $0) }.map(\.usi))
        #expect(!mating.isEmpty && mating.count < moves.count, "前提: 詰まされる手とそうでない手の両方がある")

        // 対照: 損の幅を実質無制限にすると、候補（詰みの確認前）に詰まされる手が入る。
        // 確認が効いていなければ、下のループで選ばれる。
        var pooled = pos
        let pool = exactEngine(seed: 1, margin: 1_000_000).slipPool(&pooled, moves: moves).map(\.usi)
        #expect(pool.contains { mating.contains($0) }, "対照: 候補に詰まされる手が入っていない（前提が崩れている）")

        for seed in 1...60 {
            var p = pos
            var rng = SplitMix64(seed: UInt64(seed))
            let e = exactEngine(seed: UInt64(seed), margin: 1_000_000)
            if let m = e.slipMove(&p, moves: moves, using: &rng) {
                #expect(!mating.contains(m.usi), "詰まされる手を選んだ: \(m.usi)")
            }
        }
    }

    @Test("外しの手は、最善と損の幅の外の手（駒を只で取られる手）を選ばない")
    func slipStaysWithinTheMargin() {
        // 5e の金は 5d の歩を取れるが、その歩にも 5e の金を取られうる。金を歩の利きに残す手は幅（500 = 銀 1 枚ぶん）の外。
        let sfen = "4k4/9/9/4p4/4G4/9/9/9/4K4 b - 1"
        let pos = Position.fromSFEN(sfen)!
        var p = pos
        let pool = exactEngine(seed: 1).slipPool(&p, moves: pos.legalMoves())
        #expect(!pool.isEmpty)
        #expect(!pool.contains { $0.usi == "5e5d" }, "最善（歩を取る手）は外しの候補に入らない")
        for move in pool {
            var q = pos
            q.make(move)
            let lostGold = q.legalMoves().contains { reply in
                if case let .board(_, to, _) = reply, let piece = q.squares[to], piece.type == .gold { return true }
                return false
            }
            #expect(!lostGold, "金を只で取られる手が候補に入っている: \(move.usi)")
        }
    }

    /// 外しの候補が無い（合法手が 1 手だけ）ときは、外せないので探索して最善手を指す。
    /// 何も返さない・非合法手を返すと、CPU が止まる。
    @Test("外しの候補が無ければ探索に回り、唯一の合法手を返す")
    func slipWithNoCandidatesFallsBackToSearch() async {
        // 黒玉 1i は、2a の飛車が 2 筋を押さえているので 1h へしか動けない。
        let pos = Position.fromSFEN("4k2r1/9/9/9/9/9/9/9/8K b - 1")!
        let moves = pos.legalMoves()
        #expect(moves.count == 1, "前提: 合法手が 1 手だけ（\(moves.map(\.usi))）")
        let e = SimpleMinimaxEngine(depth: 2, usePositional: true, useQuiescence: true, useBook: false,
                                    timeLimit: .infinity, policy: SimpleMinimaxEngine.policy(0), seed: 1)
        #expect(await e.bestMove(sfen: pos.toSFEN()) == moves[0].usi)
    }

    @Test("探索に残す時間は、使った時間と後始末ぶんを引く（上限を超えない・0 にならない）")
    func searchTimeSubtractsWhatWasUsed() {
        let over = SimpleMinimaxEngine.searchOverhead
        #expect(abs(SimpleMinimaxEngine.searchTime(limit: 1, elapsed: 0.4) - (0.6 - over)) < 1e-9)
        #expect(SimpleMinimaxEngine.searchTime(limit: 1, elapsed: 5) == SimpleMinimaxEngine.minSearchTime)
        #expect(SimpleMinimaxEngine.searchTime(limit: .infinity, elapsed: 5) == .infinity)
    }

    @Test("局面数の上限に達したら読みを打ち切り、途中の深さは採用せず合法手を返す")
    func nodeLimitStopsTheSearch() {
        let engine = SimpleMinimaxEngine(depth: 5, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 3_000)
        let r = engine.analyze(sfen: Position.startSFEN)
        #expect(r != nil)
        #expect((r?.depth ?? 99) < 5, "上限があるのに深さ 5 まで読み切った")
        // 打ち切り後に上限を大きく超えて読み続けない（1 手ぶんの余りは許す）。
        #expect((r?.nodes ?? .max) < 3_000 + 2_000, "上限を超えて読み続けている（\(r?.nodes ?? 0)）")
        let move = r?.usi.flatMap(Move.fromUSI)
        #expect(move != nil && Position.start().legalMoves().contains(move!))
    }

    /// `bestMove` が上限を探索へ渡していること。上限が渡らないと深さ 7 の全読みになり、
    /// デバッグビルドでは何分もかかる（時間の上限は無限にしてあるので、止めるのは局面数だけ）。
    @Test("bestMove も局面数の上限で止まる")
    func bestMoveHonorsTheNodeLimit() async {
        let engine = SimpleMinimaxEngine(depth: 7, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 300)
        let start = Date()
        let usi = await engine.bestMove(sfen: Position.startSFEN)
        #expect(Date().timeIntervalSince(start) < 20, "局面数の上限が bestMove の探索に渡っていない")
        #expect(usi.flatMap(Move.fromUSI) != nil)
    }

    @Test("上限が極端に小さくても合法手を返す")
    func tinyNodeLimitStillReturnsALegalMove() {
        let engine = SimpleMinimaxEngine(depth: 4, usePositional: true, useQuiescence: true,
                                         useBook: false, timeLimit: .infinity, nodeLimit: 1)
        let r = engine.analyze(sfen: Position.startSFEN)
        let move = r?.usi.flatMap(Move.fromUSI)
        #expect(r?.depth == 0)
        #expect(move != nil && Position.start().legalMoves().contains(move!))
    }
}
