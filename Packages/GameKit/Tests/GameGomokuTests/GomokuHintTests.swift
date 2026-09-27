import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameGomoku

/// 1局3回のヒント（#1118）。回数の勘定そのものは Core の `BoardHintBudget`（`BoardHintTests`）が
/// 固定するので、ここでは**五目並べの対局にどう結線されているか**を見る（将棋・チェスと同型）。
@MainActor
@Suite("五目並べ ヒント（#1118）")
struct GomokuHintTests {

    private func makeServices(_ store: MemorySnapshotStore) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService())
    }

    @Test("押すと打つと良い交点が1つ出て、残りが1つ減る")
    func showsBestPointAndSpendsOne() async throws {
        let model = GomokuModel(services: nil)
        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        let point = try #require(model.hintPoint, "ヒントの交点が出ていない")
        #expect((0..<gomokuBoardSize).contains(point.row) && (0..<gomokuBoardSize).contains(point.col))
        #expect(model.board[point.row, point.col] == nil, "石のある交点を示している")
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("無料3回を使い切ると requestHint()（無料専用）は何も起きない（広告枠は残る・#1500）")
    func stopsAfterThreeHints() async {
        let model = GomokuModel(services: nil)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax, "無料枠だけを使い切った状態")
        #expect(model.canUseHint, "広告枠が残っているので押せる状態のまま")
        #expect(model.needsAdForHint)

        await model.requestHint()
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax, "無料専用の requestHint() で回数が動いている")
    }

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() {
        let model = GomokuModel(services: nil)
        model.tap(row: 7, col: 7)
        #expect(model.isAITurn, "前提: CPU の手番になっている")
        #expect(!model.canUseHint)
    }

    @Test("打つとヒントの印は消える（回数は戻らない）")
    func hintMarkDisappearsAfterTheMove() async throws {
        let model = GomokuModel(services: nil)
        await model.requestHint()
        try #require(model.hintPoint != nil)

        model.tap(row: 0, col: 0)

        #expect(model.hintPoint == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1, "打ったら回数が戻っている")
    }

    @Test("新規対局で8回に戻る")
    func newGameRefillsHints() async {
        let model = GomokuModel(services: nil)
        await model.requestHint()
        #expect(model.hintsRemaining < BoardHintBudget.total)

        model.newGame()

        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.hintPoint == nil, "前の対局のヒントの印が残っている")
    }

    /// 禁じ手ルールがオンのとき、黒に三三・四四・長連を勧めると「打てません」と断られる手を示すことになる。
    ///
    /// (7,7) に打つと三三が成立する盤（`GomokuRenjuTests` の形）を注入する。黒にとっては最も打ちたい
    /// 点なので、読みに禁じ手を渡し忘れていればヒントはここを示す。
    @Test("禁じ手ルールの対局では、黒に打てない交点を示さない")
    func hintRespectsRenjuForbiddenMoves() async throws {
        let store = MemorySnapshotStore()
        try store.save(Self.doubleThreeSnapshot(), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))
        try #require(!model.gameOver && !model.isAITurn, "前提: 黒（人間）の手番で止まっている")
        try #require(model.forbiddenReason(row: 7, col: 7) != nil, "前提: (7,7) は黒の禁じ手")

        await model.requestHint()

        let point = try #require(model.hintPoint)
        #expect(model.forbiddenReason(row: point.row, col: point.col) == nil,
                "禁じ手の交点をヒントとして示している")
    }

    /// (7,7) が黒の三三になる一歩手前の盤（禁じ手ルールあり・黒の手番）。
    private static func doubleThreeSnapshot() -> GomokuSnapshot {
        var board = GomokuBoard()
        for (row, col) in [(7, 5), (7, 6), (5, 7), (6, 7)] { board[row, col] = .black }
        // 手数の辻褄合わせ（盤の端で、判定に絡まない位置）。
        for (row, col) in [(0, 0), (0, 14), (14, 0), (14, 14)] { board[row, col] = .white }
        return GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: GomokuStone.black.rawValue,
            humanSide: GomokuStone.black.rawValue,
            aiLevel: 1,
            startedAt: Date(),
            moveHistory: nil,
            undoUsed: nil,
            resigned: nil,
            winner: nil,
            forbiddenMoves: true,
            hintsUsed: nil
        )
    }

    @Test("中断データに使った回数が乗り、再開しても残りが戻らない")
    func hintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let model = GomokuModel(services: makeServices(store))
        await model.requestHint()
        try #require(model.hints.used == 1)

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.total - 1, "再開でヒントが戻っている")
        #expect(restored.hintPoint == nil, "印は保存しない（開き直したら出し直す）")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let store = MemorySnapshotStore()
        let model = GomokuModel(services: makeServices(store))
        model.newGame()

        // v1.1.5 までの中断データと同じく `hintsUsed` の鍵が無い形を流し込む。
        let legacy = try #require(store.rawData(for: "gomoku"))
        let text = try #require(String(data: legacy, encoding: .utf8))
        #expect(text.contains("hintsUsed"), "前提: いまの形式は鍵を持つ")
        let stripped = try #require(
            text.replacingOccurrences(of: "\"hintsUsed\":0,", with: "")
                .replacingOccurrences(of: ",\"hintsUsed\":0", with: "")
                .data(using: .utf8)
        )
        store.inject(stripped, for: "gomoku")

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.total)
    }

    @Test("ヒントを使った対局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() async throws {
        let name = "asobiba.gomoku.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = GomokuModel(services: services)

        #expect(model.hints.winLossScore.isLeaderboardEligible, "前提: 使う前は順位表の対象")
        await model.requestHint()
        try #require(model.hints.used == 1)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        model.resign()
        #expect(log.record(gameID: "gomoku")?.plays == 1, "自己ベスト（端末内）は使用有無を問わず残す")
        #expect(model.recordResult != nil, "リザルトの記録行も従来どおり出る")
    }
}

/// ヒントの使用回数が `game_end` の `hints_used` に載る結線（#1326）。
@MainActor
@Suite("五目並べ ヒントの解析（#1326）")
struct GomokuHintAnalyticsTests {

    private func makeModel() -> (GomokuModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["gomoku"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (GomokuModel(services: services), spy)
    }

    private func endParameters(_ spy: SpyAnalyticsService) -> [[String: AnalyticsValue]] {
        spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
    }

    @Test("ヒントを使った局を打ってから捨てると、quit の game_end に hints_used が載る")
    func quitCarriesHintsUsed() async {
        let (model, spy) = makeModel()
        await model.requestHint()
        await model.requestHint()
        model.tap(row: 0, col: 0)

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
    func noHintNoKey() {
        let (model, spy) = makeModel()
        model.tap(row: 0, col: 0)

        model.newGame()

        let ends = endParameters(spy)
        #expect(ends.count == 1)
        #expect(ends.first?.keys.contains("hints_used") == false)
    }
}

// MARK: - 広告での追加ヒント（会長決裁 2026-09-27・#1500）

/// 視聴完了・未完了を制御できる広告スタブ（`PokerRewardedAdTests` と同じ形）。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var shownCount = 0
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        shownCount += 1
        duringAd?()
        return rewardEarned
    }
}

@MainActor
@Suite("五目並べ 広告での追加ヒント（#1500）")
struct GomokuAdHintTests {

    private func makeModel(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore(),
        screenGeneration: GameScreenGeneration = GameScreenGeneration()
    ) -> (GomokuModel, StubAdService) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let services = GameServices(snapshots: store, ads: ads, screenGeneration: screenGeneration)
        return (GomokuModel(services: services), ads)
    }

    @Test("無料枠が残っているうちは広告を要求しない")
    func doesNotNeedAdWhileFreeRemains() async throws {
        let (model, ads) = makeModel()
        #expect(!model.needsAdForHint)

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(ads.shownCount == 0, "無料枠があるのに広告を出している")
        #expect(model.hints.used == 0)
    }

    @Test("無料3回を使い切ると次の1回に広告が要る")
    func needsAdAfterTheFreeThreeAreUsed() async throws {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }

        #expect(model.needsAdForHint)
        #expect(model.canUseHint, "広告枠が残っているので押せる状態のまま")
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax)
    }

    @Test("広告を視聴すると打つと良い交点が1つ出て、広告枠が1つ減る")
    func adGrantsOneMoreHint() async throws {
        let (model, ads) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .granted)
        #expect(ads.shownCount == 1)
        #expect(model.hints.used == BoardHintBudget.perGame + 1)
        #expect(model.hintPoint != nil, "ヒントの交点が出ていない")
    }

    @Test("視聴しなかった・読み込めなかったときは回数を減らさない")
    func notEarnedDoesNotConsume() async throws {
        let (model, ads) = makeModel(rewardEarned: false)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .notEarned)
        #expect(ads.shownCount == 1)
        #expect(model.hints.used == BoardHintBudget.perGame, "視聴未完了なのに回数が減っている")
    }

    @Test("広告5回ぶんで合計8回を使い切ると押せなくなる")
    func stopsAfterEightHintsTotal() async throws {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        for _ in 0..<BoardHintBudget.adRefillMax { _ = await model.requestAdHint() }

        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)
        #expect(!model.needsAdForHint, "使い切ったら広告要求の状態も外れる")

        let extra = await model.requestAdHint()
        #expect(extra == .unavailable)
        #expect(model.hints.used == BoardHintBudget.total)
    }

    @Test("広告を見ているあいだに新しい対局が始まったら、捨てた局へは適用しない")
    func discardsTheHintIfANewGameStartedDuringTheAd() async throws {
        let (model, ads) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        ads.duringAd = { model.newGame() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(model.hints.used == 0, "新しい対局の回数へ広告の分が乗っている")
    }

    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルには適用しない")
    func discardsTheHintIfTheScreenWasLeftDuringTheAd() async throws {
        let generation = GameScreenGeneration()
        let (model, ads) = makeModel(screenGeneration: generation)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        ads.duringAd = { generation.advance() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(model.hints.used == BoardHintBudget.perGame, "画面を離れたのに回数が増えている")
    }

    @Test("新規対局で無料・広告とも8回に戻る")
    func newGameRefillsBothTiers() async throws {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        _ = await model.requestAdHint()

        model.newGame()

        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(!model.needsAdForHint)
    }

    @Test("中断データに広告ぶんの使用回数も乗り、再開しても残りが戻らない")
    func adHintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        _ = await model.requestAdHint()
        try #require(model.hints.used == BoardHintBudget.perGame + 1)

        let restoredServices = GameServices(snapshots: store, ads: NoopAdService())
        let restored = GomokuModel(services: restoredServices)
        #expect(restored.hintsRemaining == BoardHintBudget.total - (BoardHintBudget.perGame + 1))
        #expect(restored.needsAdForHint, "無料枠を使い切った状態のまま再開している")
    }
}
