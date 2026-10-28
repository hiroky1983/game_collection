import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ステージモード（#3048）。クリアしたら次の面へ進むだけの連番で、保存するのは次に遊ぶ面の番号だけ。
@Suite("おじさんちのねこさがしのステージモード")
@MainActor
struct CatPuzzleStageModeTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.stage.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeServices(store: MemorySnapshotStore = MemorySnapshotStore(),
                              analytics: SpyAnalyticsService? = nil) -> GameServices {
        GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [CatPuzzleModel.gameID]) }
        )
    }

    /// 面を始めて、問題ができるまで待つ。
    private func start(_ model: CatPuzzleModel, _ number: Int? = nil) async {
        model.startStage(number)
        #expect(model.isPreparingStage, "作っている間は操作できない")
        await model.stagePreparation?.value
        #expect(!model.isPreparingStage)
    }

    private func solve(_ model: CatPuzzleModel) {
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    @Test("はじめは 1 面目。番号から決めた問題（6×6）で始まり、game_start の level は stage-1")
    func startsAtStageOne() async {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults("first")
        let model = CatPuzzleModel(services: makeServices(analytics: spy), size: .normal, defersStart: true,
                                   stageDefaults: defaults)
        #expect(model.savedStage == 1)
        await start(model)
        #expect(model.stage == 1)
        #expect(model.size == .easy)
        #expect(model.puzzle == CatPuzzleStage(1).makePuzzle(), "同じ番号なら誰でも同じ問題")
        #expect(spy.startLevels.last == .stage(1))
    }

    @Test("クリアしたら次の面が開き、「次のステージへ」で 2 面目。game_end の level も面の番号")
    func clearingAdvances() async {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults("advance")
        let model = CatPuzzleModel(services: makeServices(analytics: spy), stageDefaults: defaults)
        await start(model, 1)
        solve(model)
        #expect(model.isSolved)
        #expect(model.savedStage == 2, "クリアの時点で進み具合を保存する")
        #expect(spy.endLevels.last == .stage(1))
        await start(model)
        #expect(model.stage == 2)
        #expect(model.puzzle == CatPuzzleStage(2).makePuzzle())
        #expect(!model.isSolved && model.mistakes == 0 && model.hintsUsed == 0)
        // 進み具合はモデルを作り直しても（アプリを閉じても）残る。
        let reopened = CatPuzzleModel(services: makeServices(), stageDefaults: defaults)
        #expect(reopened.savedStage == 2)
    }

    @Test("負けても進み具合は戻らず進まない。「もう一回」は同じ面の同じ問題")
    func failingKeepsStage() async {
        let defaults = makeDefaults("fail")
        let model = CatPuzzleModel(services: makeServices(), stageDefaults: defaults)
        await start(model, 1)
        let first = model.puzzle
        let solution = Set(model.puzzle.solutionCells)
        for cell in (0..<model.puzzle.cellCount).filter({ !solution.contains($0) }).prefix(CatPuzzleModel.maxMistakes) {
            model.findCat(cell: cell)
        }
        model.declineContinue()
        #expect(model.isFailed)
        #expect(model.savedStage == 1)
        await start(model, model.stage)
        #expect(model.stage == 1 && model.puzzle == first)
    }

    @Test("途中の盤は面の番号ごと中断データに残り、開き直すと同じ面から続く")
    func snapshotKeepsStage() async {
        let store = MemorySnapshotStore()
        let defaults = makeDefaults("snapshot")
        let model = CatPuzzleModel(services: makeServices(store: store), stageDefaults: defaults)
        await start(model, 3)
        let cell = (0..<model.puzzle.cellCount).first { !model.puzzle.solutionCells.contains($0) }!
        model.toggleCross(cell: cell)
        let restored = CatPuzzleModel(services: makeServices(store: store), stageDefaults: defaults)
        #expect(restored.stage == 3)
        #expect(restored.puzzle == model.puzzle)
        #expect(restored.marks[cell] == .cross)
    }

    @Test("面の番号と盤の大きさが食い違う中断データは捨てる")
    func mismatchedSnapshotIsRejected() {
        let puzzle = CatPuzzleStage(1).makePuzzle()
        var marks = Array(repeating: 0, count: puzzle.cellCount)
        marks[0] = 1
        let good = CatPuzzleSnapshot(size: "easy", puzzle: puzzle, marks: marks, elapsedSeconds: 0,
                                     mistakes: 0, hintsUsed: 0, stage: 1)
        #expect(CatPuzzleSnapshot.isResumable(good))
        var wrong = good
        wrong.stage = 11  // 11 面目は 7×7
        #expect(!CatPuzzleSnapshot.isResumable(wrong))
        wrong.stage = 0
        #expect(!CatPuzzleSnapshot.isResumable(wrong))
    }

    @Test("ステージの途中で自由に遊ぶを始めると、面の番号は外れて盤の大きさの level に戻る")
    func freePlayLeavesStage() async {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), stageDefaults: makeDefaults("free"))
        await start(model, 1)
        model.newGame(size: .hard)
        #expect(model.stage == nil && model.size == .hard)
        #expect(spy.startLevels.last == .hard)
    }

    @Test("問題を作っている間に自由に遊ぶへ切り替えたら、出来上がった面は盤に出さない")
    func switchingDuringPreparationDropsStage() async {
        let model = CatPuzzleModel(services: makeServices(), stageDefaults: makeDefaults("switch"))
        model.startStage(31)
        // 切り替えで `stagePreparation` は外れるので、作りかけの段取りを先に控えて最後まで待つ。
        let pending = model.stagePreparation
        model.newGame(size: .easy)
        #expect(!model.isPreparingStage)
        await pending?.value
        #expect(model.stage == nil && model.size == .easy)
    }

    @Test("同じ面を作っている最中にもう一度始めても（連打）、作り直さず 1 回で盤に出る")
    func repeatedStartIsIgnored() async {
        let model = CatPuzzleModel(services: makeServices(), stageDefaults: makeDefaults("repeat"))
        model.startStage(2)
        let first = model.stagePreparation
        model.startStage(2)
        #expect(model.stagePreparation == first, "2 回目は何もしない")
        await first?.value
        #expect(model.stage == 2 && !model.isPreparingStage)
        #expect(model.puzzle == CatPuzzleStage(2).makePuzzle())
    }

    @Test("決着後の段は、結果カードが画面を覆っている間に替える（遊んでいる間は高さを取らない）")
    func finishedControlsSwapUnderTheCard() async {
        let model = CatPuzzleModel(services: makeServices(), stageDefaults: makeDefaults("controls"))
        await start(model, 1)
        let clock = ManualClock()
        model.clockNow = clock.now
        #expect(!CatPuzzleView.showsFinishedControls(model))
        solve(model)
        #expect(model.isSolved && !CatPuzzleView.showsFinishedControls(model), "最後の猫の演出の間は盤を縮めない")
        clock.advance(by: .seconds(1))
        model.revealClearCardIfDue()
        #expect(CatPuzzleView.showsFinishedControls(model))
    }

    @Test("クリアのカードの行は 3 行以内（SE の画面に収める）")
    func clearDetailsAreCompact() async {
        let services = makeServices()
        let model = CatPuzzleModel(services: services, stageDefaults: makeDefaults("details"))
        await start(model, 1)
        solve(model)
        let view = CatPuzzleView(services: services, model: model)
        #expect(view.clearDetails.count <= 3)
        #expect(view.clearDetails.contains { $0.contains("ステージ 1") })
    }
}
