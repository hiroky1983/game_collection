import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameGo

/// 視聴完了・未完了を制御できる広告スタブ（`GomokuAdHintTests` と同じ形）。
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

/// 1局3回（広告で最大5回）のヒント（#2027）。回数の勘定そのものは Core の `BoardHintBudget`
/// （`BoardHintTests`）が固定するので、ここでは**囲碁の対局にどう結線されているか**を見る（将棋と同型）。
@MainActor
@Suite("囲碁 ヒント（#2027）")
struct GoHintTests {

    private func makeModel(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore(),
        screenGeneration: GameScreenGeneration = GameScreenGeneration()
    ) -> (GoModel, StubAdService) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let services = GameServices(snapshots: store, ads: ads, screenGeneration: screenGeneration)
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .easy)
        return (model, ads)
    }

    /// 盤の左 4 列が黒・右 4 列が白で埋まり、中央の列は (4,4) だけが空いた局面（黒の手番・80 手目）。
    /// 黒の連も白の連も呼吸点は (4,4) の 1 つだけで、黒が (4,4) に打てば白 40 子を取れる
    /// （打たなければ白に黒 40 子を取られる）。合法手は (4,4) とパスだけで、答えは 1 つに決まる。
    private func makeCaptureModel() -> GoModel {
        let (model, _) = makeModel()
        for row in 0..<9 {
            for col in 0..<4 {
                model.applyMoveForTesting(.play(row: row, col: col))       // 黒
                model.applyMoveForTesting(.play(row: row, col: col + 5))   // 白
            }
        }
        for offset in 0..<4 {
            model.applyMoveForTesting(.play(row: 5 + offset, col: 4))     // 黒
            model.applyMoveForTesting(.play(row: offset, col: 4))         // 白
        }
        return model
    }

    // MARK: 回数

    @Test("押すと打つと良い手が1つ出て、残りが1つ減る")
    func showsBestMoveAndSpendsOne() async throws {
        let (model, _) = makeModel()
        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        let move = try #require(model.hintMove, "ヒントが出ていない")
        #expect(model.state.isLegal(move), "打てない手を示している")
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("無料3回 → 広告 → 使い切りの順に進み、使い切ると押せない")
    func freeThenAdThenExhausted() async throws {
        let (model, ads) = makeModel()
        #expect(!model.needsAdForHint)
        let early = await model.requestAdHint()
        #expect(early == .unavailable, "無料が残っているのに広告を求めている")
        #expect(ads.shownCount == 0)

        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax)
        #expect(model.needsAdForHint)
        #expect(model.canUseHint, "広告枠が残っているので押せる状態のまま")

        await model.requestHint()
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax, "無料専用の requestHint() で広告枠が動いている")

        for _ in 0..<BoardHintBudget.adRefillMax {
            #expect(await model.requestAdHint() == .granted)
        }
        #expect(ads.shownCount == BoardHintBudget.adRefillMax)
        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)
        #expect(!model.needsAdForHint, "使い切ったら広告要求の状態も外れる")
        #expect(await model.requestAdHint() == .unavailable)
        #expect(model.hints.used == BoardHintBudget.total)
    }

    @Test("広告を視聴しなかったときは回数を減らさない")
    func notEarnedDoesNotConsume() async {
        let (model, ads) = makeModel(rewardEarned: false)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }

        #expect(await model.requestAdHint() == .notEarned)
        #expect(ads.shownCount == 1)
        #expect(model.hints.used == BoardHintBudget.perGame)
    }

    @Test("広告を見ているあいだに新規対局が始まったら、新しい対局へは適用しない")
    func discardsTheHintIfANewGameStartedDuringTheAd() async {
        let (model, ads) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        ads.duringAd = { model.newGame() }

        #expect(await model.requestAdHint() == .unavailable)
        #expect(model.hints.used == 0, "新しい対局の回数へ広告の分が乗っている")
        #expect(model.hintMove == nil)
    }

    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルには適用しない")
    func discardsTheHintIfTheScreenWasLeftDuringTheAd() async {
        let generation = GameScreenGeneration()
        let (model, ads) = makeModel(screenGeneration: generation)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        ads.duringAd = { generation.advance() }

        #expect(await model.requestAdHint() == .unavailable)
        #expect(model.hints.used == BoardHintBudget.perGame)
    }

    // MARK: 押せない局面

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() async {
        let (model, _) = makeModel()
        model.applyMoveForTesting(.play(row: 4, col: 4))
        #expect(model.isAITurn, "前提: CPU の手番")
        #expect(!model.canUseHint)

        await model.requestHint()
        #expect(model.hints.used == 0)
        #expect(model.hintMove == nil)
    }

    @Test("終局の確認中・決着後はヒントを押せない")
    func cannotUseHintAfterTheGameEnds() async {
        let (model, _) = makeModel()
        model.applyMoveForTesting(.pass)
        model.applyMoveForTesting(.pass)
        #expect(model.phase == .scoring)
        #expect(!model.canUseHint)

        model.resign()
        #expect(model.phase == .finished)
        #expect(!model.canUseHint)
        await model.requestHint()
        #expect(model.hints.used == 0)
    }

    @Test("ヒントを読んでいるあいだは、もう一度押せない")
    func cannotUseHintWhileReading() async {
        let (model, _) = makeModel()
        var duringRead: (canUse: Bool, thinking: Bool)?
        model.hintThinkingGate = { duringRead = (model.canUseHint, model.isHintThinking) }

        await model.requestHint()

        #expect(duringRead?.thinking == true)
        #expect(duringRead?.canUse == false)
        #expect(!model.isHintThinking)
    }

    // MARK: 読み中の操作・印の消去

    @Test("読んでいるあいだに打つと、印を出さず回数も減らさない")
    func tapDuringReadingDiscardsTheHint() async {
        let (model, _) = makeModel()
        model.hintThinkingGate = { model.tap(row: 4, col: 4) }

        await model.requestHint()

        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
        #expect(!model.isHintThinking)
    }

    @Test("読んでいるあいだにパスすると、印を出さず回数も減らさない")
    func passDuringReadingDiscardsTheHint() async {
        let (model, _) = makeModel()
        model.hintThinkingGate = { model.pass() }

        await model.requestHint()

        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
    }

    @Test("読んでいるあいだに待ったすると、印を出さず回数も減らさない")
    func undoDuringReadingDiscardsTheHint() async {
        let (model, _) = makeModel()
        model.applyMoveForTesting(.play(row: 4, col: 4))
        model.applyMoveForTesting(.play(row: 2, col: 2))
        model.hintThinkingGate = { model.undoLastExchange() }

        await model.requestHint()

        #expect(model.moveCount == 0, "前提: 待ったが通っている")
        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
    }

    @Test("読んでいるあいだに新規対局を始めると、印を出さず新しい対局の回数も減らさない")
    func newGameDuringReadingDiscardsTheHint() async {
        let (model, _) = makeModel()
        model.hintThinkingGate = { model.newGame() }

        await model.requestHint()

        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(!model.isHintThinking)
    }

    @Test("読んでいるあいだに投了すると、印を出さず回数も減らさない")
    func resignDuringReadingDiscardsTheHint() async {
        let (model, _) = makeModel()
        model.hintThinkingGate = { model.resign() }

        await model.requestHint()

        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
    }

    @Test("探索の結果が非合法手なら示さず、回数も減らさない")
    func illegalResultIsNotShown() async {
        let (model, _) = makeModel()
        model.applyMoveForTesting(.play(row: 4, col: 4))
        model.applyMoveForTesting(.play(row: 2, col: 2))
        model.hintMoveForTesting = .play(row: 4, col: 4)   // 黒石がある交点

        await model.requestHint()

        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
    }

    @Test("打つ・パス・待った・新規対局・投了で印は消える（回数は戻らない）")
    func hintMarkDisappears() async throws {
        let (model, _) = makeModel()

        await model.requestHint()
        try #require(model.hintMove != nil)
        model.tap(row: 0, col: 0)
        #expect(model.hintMove == nil, "打っても印が残っている")
        #expect(model.hints.used == 1, "打ったら回数が戻っている")

        // CPU の応手を直接指定して、人間の手番へ戻す。
        model.applyMoveForTesting(.play(row: 8, col: 8))
        await model.requestHint()
        try #require(model.hintMove != nil)
        model.pass()
        #expect(model.hintMove == nil, "パスしても印が残っている")

        model.applyMoveForTesting(.play(row: 8, col: 7))
        await model.requestHint()
        try #require(model.hintMove != nil)
        model.undoLastExchange()
        #expect(model.hintMove == nil, "待ったしても印が残っている")

        // 無料の 3 回は使い切ったので、4 回目は広告枠から出す。
        #expect(await model.requestAdHint() == .granted)
        try #require(model.hintMove != nil)
        model.resign()
        #expect(model.hintMove == nil, "投了しても印が残っている")

        model.newGame()
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total, "新規対局で回数が戻らない")
    }

    // MARK: 示す手

    @Test("取れる石があれば、取る手を示す（種を固定）")
    func hintsTheCapture() async throws {
        for seed: UInt64 in [1, 2, 3] {
            let model = makeCaptureModel()
            try #require(!model.isAITurn && model.moveCount == 80, "前提: 黒の手番")
            try #require(model.state.isLegal(.play(row: 4, col: 4)))
            model.hintSeedForTesting = seed

            await model.requestHint()

            #expect(model.hintMove == .play(row: 4, col: 4), "種 \(seed): 白 40 子を取れる交点を示していない")
            #expect(model.hintPoint == GoPoint(row: 4, col: 4))
            #expect(!model.hintSuggestsPass)
        }
    }

    @Test("最善手がパスのときは交点を示さず、パスを勧める")
    func hintCanSuggestPass() async throws {
        let (model, _) = makeModel()
        model.hintMoveForTesting = .pass

        await model.requestHint()

        #expect(model.hintMove == .pass)
        #expect(model.hintSuggestsPass)
        #expect(model.hintPoint == nil, "パスなのに交点を示している")
        #expect(model.hints.used == 1)
        #expect(GoAccessibility.hintPassMessage == "ここはパスでよい局面です")
    }

    @Test("ヒントの交点は読み上げに「ヒントの手」と付く")
    func hintPointIsAnnouncedToVoiceOver() {
        let plain = GoAccessibility.pointLabel(row: 2, col: 3, stone: nil, isLastMove: false)
        let hinted = GoAccessibility.pointLabel(row: 2, col: 3, stone: nil, isLastMove: false, isHint: true)
        #expect(!plain.contains("ヒント"))
        #expect(hinted == "3行4列、空点、ヒントの手")
    }

    // MARK: 中断データ・成績

    @Test("中断データに使った回数が乗り、再開しても残りが戻らない（印は保存しない）")
    func hintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        _ = await model.requestAdHint()
        try #require(model.hints.used == BoardHintBudget.perGame + 1)

        let restored = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.hintsRemaining == BoardHintBudget.total - (BoardHintBudget.perGame + 1))
        #expect(restored.needsAdForHint, "無料枠を使い切った状態のまま再開している")
        #expect(restored.hintMove == nil, "印は保存しない（開き直したら出し直す）")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        model.newGame()

        let raw = try #require(store.rawData(for: "go"))
        let text = try #require(String(data: raw, encoding: .utf8))
        #expect(text.contains("hintsUsed"), "前提: いまの形式は鍵を持つ")
        let stripped = try #require(
            text.replacingOccurrences(of: "\"hintsUsed\":0,", with: "")
                .replacingOccurrences(of: ",\"hintsUsed\":0", with: "")
                .data(using: .utf8)
        )
        store.inject(stripped, for: "go")

        let restored = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.hintsRemaining == BoardHintBudget.total)
    }

    @Test("ヒントを使った対局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() async throws {
        let name = "asobiba.go.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = GoModel(services: services)

        #expect(model.hints.winLossScore.isLeaderboardEligible, "前提: 使う前は順位表の対象")
        await model.requestHint()
        try #require(model.hints.used == 1)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        model.resign()
        #expect(log.record(gameID: "go")?.plays == 1, "自己ベスト（端末内）は使用有無を問わず残す")
        #expect(model.recordResult != nil)
    }

    @Test("ヒントを使った局の game_end に hints_used が載る")
    func gameEndCarriesHintsUsed() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["go"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .easy)
        await model.requestHint()
        await model.requestHint()

        model.resign()

        let ends = spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
        #expect(ends.first?["hints_used"] == .int(2))
    }
}
