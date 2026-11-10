import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ねこさがしの計測（#3232）。ミス数・ヒント／猫を教えるの回数・クリア後の離脱を、解析の受け口で確かめる。
@Suite("おじさんちのねこさがしの計測")
@MainActor
struct CatPuzzleAnalyticsTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.analytics.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID])
        )
    }

    private func start(_ model: CatPuzzleModel, _ number: Int? = nil) async {
        model.startStage(number)
        await model.stagePreparation?.value
    }

    private func solve(_ model: CatPuzzleModel) {
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    /// 答えでないマスで猫を探す（赤い × が付いてミスになる）。
    private func miss(_ model: CatPuzzleModel) {
        let wrong = (0..<model.puzzle.side * model.puzzle.side).first {
            !model.puzzle.solutionCells.contains($0) && !model.isFixed(cell: $0) && model.marks[$0] != .cat
        }!
        model.findCat(cell: wrong)
    }

    private func lastEnd(_ spy: SpyAnalyticsService) -> [String: AnalyticsValue]? {
        spy.events.last { $0.name == "game_end" }?.parameters
    }

    @Test("ステージ: ミス 2 回・ヒント 1 回・猫を教える 2 回が game_end に載り、ヒントと猫を教えるは別の鍵")
    func stageEndCarriesMissHintTeach() async {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(spy), stageDefaults: makeDefaults("stage"))
        await start(model, 1)
        miss(model)
        miss(model)
        model.useHint()
        model.teachCat()
        model.teachCat()
        solve(model)
        #expect(model.isSolved)
        let end = lastEnd(spy)
        #expect(end?["miss_count"] == .int(2))
        #expect(end?["hints_used"] == .int(1))
        #expect(end?["teach_used"] == .int(2))
        #expect(end?["cause"] == nil, "ねこさがしには原因の語彙が無い")
        #expect(end?["miss_at"] != nil)
    }

    @Test("ミス・ヒント・猫を教えるを使わなかったプレイは鍵ごと送らない")
    func cleanPlayHasNoKeys() async {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(spy), stageDefaults: makeDefaults("clean"))
        await start(model, 1)
        solve(model)
        let end = lastEnd(spy)
        #expect(end != nil)
        #expect(end?["miss_count"] == nil && end?["hints_used"] == nil && end?["teach_used"] == nil)
    }

    @Test("miss_at は置いた猫の数 ÷ 盤の辺（%・5 刻み）")
    func missAtIsPlacedCatsOverSide() async {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(spy), stageDefaults: makeDefaults("at"))
        await start(model, 1)
        let side = model.puzzle.side
        let first = model.puzzle.solutionCells.sorted().first!
        model.findCat(cell: first)
        miss(model)
        solve(model)
        let expected = (1 * 100 / side) / 5 * 5
        #expect(lastEnd(spy)?["miss_at"] == .int(expected))
    }

    @Test("3 回ミスして負けた game_end にも 3 回が載る")
    func lossCarriesAllMisses() async {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(spy), stageDefaults: makeDefaults("loss"))
        await start(model, 1)
        for _ in 0..<CatPuzzleModel.maxMistakes { miss(model) }
        model.declineContinue()
        #expect(lastEnd(spy)?["miss_count"] == .int(CatPuzzleModel.maxMistakes))
    }

    @Test("ステージをクリアして次へも「もう一度」も押さず離れたら clear_exit が 1 回だけ。次の面へ進めば送らない")
    func clearExitOnceAfterLeaving() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        let model = CatPuzzleModel(services: services, stageDefaults: makeDefaults("exit"))
        await start(model, 1)
        solve(model)
        #expect(!spy.events.contains { $0.name == "clear_exit" })
        services.gameDidLeave(gameID: CatPuzzleModel.gameID)
        services.gameDidLeave(gameID: CatPuzzleModel.gameID)
        let exits = spy.events.filter { $0.name == "clear_exit" }
        #expect(exits.count == 1)
        #expect(exits.first?.parameters == ["game_id": .string("catpuzzle"), "level": .string("stage-1")])

        // 次の面へ進んでから離れたときは、前の面の clear_exit を送らない。
        let spy2 = SpyAnalyticsService()
        let services2 = makeServices(spy2)
        let model2 = CatPuzzleModel(services: services2, stageDefaults: makeDefaults("exit2"))
        await start(model2, 1)
        solve(model2)
        await start(model2)
        services2.gameDidLeave(gameID: CatPuzzleModel.gameID)
        #expect(!spy2.events.contains { $0.name == "clear_exit" })
    }
}

/// 広告コンティニュー後の続きの局にも `game_end` が付く（#3446。2048 の #1953 と同じ取りこぼし）。
@Suite("ねこさがし コンティニュー後の game_end（#3446）")
@MainActor
struct CatPuzzleContinueAnalyticsTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID])
        )
    }

    private func makeModel(_ spy: SpyAnalyticsService, _ name: String) async -> CatPuzzleModel {
        let suite = "asobiba.catpuzzle.continue.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let model = CatPuzzleModel(services: makeServices(spy), stageDefaults: defaults)
        model.startStage(1)
        await model.stagePreparation?.value
        return model
    }

    private func missToLimit(_ model: CatPuzzleModel) {
        for _ in 0..<CatPuzzleModel.maxMistakes {
            let wrong = (0..<model.puzzle.side * model.puzzle.side).first {
                !model.puzzle.solutionCells.contains($0) && !model.isFixed(cell: $0) && model.marks[$0] != .cat
                    && model.marks[$0] != .cross
            }!
            model.findCat(cell: wrong)
        }
    }

    @Test("コンティニュー後にクリアすると game_end(win) が出て、game_start は 1 回増えるだけ")
    func winAfterContinueEmitsEnd() async {
        let spy = SpyAnalyticsService()
        let model = await makeModel(spy, "win")
        missToLimit(model)
        #expect(model.isOfferingContinue, "前提: 提案が出ている")
        #expect(spy.outcomes == [.loss])
        let startsBefore = spy.starts.count
        #expect(model.continueAfterAd())
        #expect(spy.starts.count == startsBefore + 1, "コンティニュー 1 回で game_start が 1 回増えるだけ")
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
        #expect(spy.outcomes == [.loss, .win])
    }

    @Test("コンティニュー後に離れると game_end(quit) が 1 回出る")
    func abandonAfterContinueEmitsQuit() async {
        let spy = SpyAnalyticsService()
        let model = await makeModel(spy, "quit")
        missToLimit(model)
        #expect(model.continueAfterAd())
        // 再開できない盤として離れる（`quit` は「進行済みで再開できない」ときだけ送られる）。
        model.services?.analytics?.leaveGame(gameID: CatPuzzleModel.gameID, isResumable: false)
        #expect(spy.quits.map(\.gameID) == [CatPuzzleModel.gameID])
    }
}
