import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameChess

/// 1局3回のヒント（#1118）。回数の勘定そのものは Core の `BoardHintBudget`（`BoardHintTests`）が
/// 固定するので、ここでは**チェスの対局にどう結線されているか**を見る（将棋の `ShogiHintTests` と同型）。
@MainActor
@Suite("チェス ヒント（#1118）")
struct ChessHintTests {

    /// 人間（白）が 1 手指す（View の操作と同じ「駒を選ぶ → 着手先をタップ」の経路）。
    private func playPawn(_ model: ChessGameModel) throws {
        model.tapSquare(try #require(ChessSquare.fromName("e2")))
        model.tapSquare(try #require(ChessSquare.fromName("e4")))
    }

    @Test("押すと最善手が1手出て、残りが1つ減る")
    func showsBestMoveAndSpendsOne() async throws {
        let model = ChessGameModel(services: nil)
        #expect(model.hintsRemaining == BoardHintBudget.perGame)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1)
        let move = try #require(model.hintMove, "ヒントの手が出ていない")
        #expect(model.legalMovesCache.contains(move), "合法手でない手を示している")
        #expect(model.hintSquares == [move.from, move.to])
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("3回使うと押せなくなり、4回目は何も起きない")
    func stopsAfterThreeHints() async {
        let model = ChessGameModel(services: nil)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)

        await model.requestHint()
        #expect(model.hintsRemaining == 0, "使い切ったあとに回数が動いている")
    }

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() throws {
        let model = ChessGameModel(services: nil)
        try playPawn(model)
        #expect(model.isAITurn, "前提: CPU の手番になっている")
        #expect(!model.canUseHint)
    }

    @Test("指すとヒントの印は消える（回数は戻らない）")
    func hintMarkDisappearsAfterTheMove() async throws {
        let model = ChessGameModel(services: nil)
        await model.requestHint()
        try #require(model.hintMove != nil)

        try playPawn(model)

        #expect(model.hintMove == nil)
        #expect(model.hintSquares.isEmpty)
        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1, "指したら回数が戻っている")
    }

    @Test("新規対局で3回に戻る")
    func newGameRefillsHints() async {
        let model = ChessGameModel(services: nil)
        await model.requestHint()
        #expect(model.hintsRemaining < BoardHintBudget.perGame)

        model.newGame()

        #expect(model.hintsRemaining == BoardHintBudget.perGame)
        #expect(model.hintMove == nil, "前の対局のヒントの印が残っている")
    }

    /// 読みの最中でも成り先は選べてしまい、そのとき `aiTurnKey` はまだ変わらないので
    /// キーの照合では弾けない（PR #1184 の指摘）。通すと直後の `apply` が印を消すため、
    /// 「回数だけ減ってヒントが出ない」になる。
    @Test("成り先を選んでいる最中に返ってきたヒントは、回数を減らさない")
    func hintDuringPromotionChoiceIsDropped() async throws {
        let store = MemorySnapshotStore()
        // a7 のポーンが a8 へ上がると成り先を選ぶ局面（人間=白の手番）。
        try store.save(
            ChessSnapshot(
                initialFen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1", moves: [], phase: .playing,
                reviewPly: nil, white: .human, black: .ai, aiLevel: 1,
                startedAt: Date(), undoUsed: false
            ),
            for: "chess"
        )
        let model = ChessGameModel(services: makeChessServices(store))
        try #require(!model.gameOver && !model.isAITurn, "前提: 白（人間）の手番で止まっている")

        // 読みが始まる直前に成り先の選択へ入る（手数は増えないので照合は素通りする）。
        model.thinkingGate = { @MainActor in
            model.tapSquare(ChessSquare.fromName("a7") ?? 0)
            model.tapSquare(ChessSquare.fromName("a8") ?? 0)
        }
        await model.requestHint()

        #expect(model.pendingPromotion != nil, "前提: 成り先の選択中のまま")
        #expect(model.hints.used == 0, "選択中に返ってきたヒントで回数が減っている")
        #expect(model.hintMove == nil, "成り先の選択中にヒントの印を出している")
    }

    @Test("中断データに使った回数が乗り、再開しても残りが戻らない")
    func hintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let model = ChessGameModel(services: makeChessServices(store))
        await model.requestHint()
        try #require(model.hints.used == 1)

        let restored = ChessGameModel(services: makeChessServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.perGame - 1, "再開でヒントが戻っている")
        #expect(restored.hintMove == nil, "印は保存しない（開き直したら出し直す）")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let store = MemorySnapshotStore()
        let model = ChessGameModel(services: makeChessServices(store))
        model.newGame()

        // 鍵を落として v1.1.5 までの中断データと同じ形にする（nil の optional は鍵ごと書かれない）。
        var snapshot = try #require(store.load(ChessSnapshot.self, for: "chess"))
        snapshot.hintsUsed = nil
        try store.save(snapshot, for: "chess")
        let data = try #require(store.rawData(for: "chess"))
        let legacy = try #require(String(data: data, encoding: .utf8))
        #expect(!legacy.contains("hintsUsed"), "前提: 旧形式と同じく鍵が無い中断データ")

        let restored = ChessGameModel(services: makeChessServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.perGame)
    }

    @Test("ヒントを使った対局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() async throws {
        let name = "asobiba.chess.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = ChessGameModel(services: services)

        #expect(model.hints.winLossScore.isLeaderboardEligible, "前提: 使う前は順位表の対象")
        await model.requestHint()
        try #require(model.hints.used == 1)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        model.resign()
        #expect(log.record(gameID: "chess")?.plays == 1, "自己ベスト（端末内）は使用有無を問わず残す")
        #expect(model.recordResult != nil, "リザルトの記録行も従来どおり出る")
    }
}

/// ヒントの使用回数が `game_end` の `hints_used` に載る結線（#1326）。
@MainActor
@Suite("チェス ヒントの解析（#1326）")
struct ChessHintAnalyticsTests {

    private func makeModel() -> (ChessGameModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["chess"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (ChessGameModel(services: services), spy)
    }

    private func playPawn(_ model: ChessGameModel) throws {
        model.tapSquare(try #require(ChessSquare.fromName("e2")))
        model.tapSquare(try #require(ChessSquare.fromName("e4")))
    }

    private func endParameters(_ spy: SpyAnalyticsService) -> [[String: AnalyticsValue]] {
        spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
    }

    @Test("ヒントを使った局を指してから捨てると、quit の game_end に hints_used が載る")
    func quitCarriesHintsUsed() async throws {
        let (model, spy) = makeModel()
        await model.requestHint()
        await model.requestHint()
        try playPawn(model)

        model.newGame()

        let ends = endParameters(spy)
        #expect(ends.count == 1)
        #expect(ends.first?["result"] == .string("quit"))
        #expect(ends.first?["hints_used"] == .int(2))
    }

    @Test("ヒントを使った局の決着（投了）の game_end に hints_used が載る")
    func finishCarriesHintsUsed() async {
        let (model, spy) = makeModel()
        await model.requestHint()

        model.resign()

        #expect(endParameters(spy).first?["hints_used"] == .int(1))
    }

    @Test("ヒントを使わなかった局の game_end には hints_used の鍵が無い")
    func noHintNoKey() throws {
        let (model, spy) = makeModel()
        try playPawn(model)

        model.newGame()

        let ends = endParameters(spy)
        #expect(ends.count == 1)
        #expect(ends.first?.keys.contains("hints_used") == false)
    }
}
