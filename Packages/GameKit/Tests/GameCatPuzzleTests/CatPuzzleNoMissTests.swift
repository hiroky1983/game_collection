import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ステージのノーミス連続（#3244）。ミス 0 回のクリアで +1、ミス 1 回以上のクリア・ゲームオーバーで 0。
@Suite("おじさんちのねこさがしのノーミス連続")
@MainActor
struct CatPuzzleNoMissTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.nomiss.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(_ defaults: UserDefaults) -> CatPuzzleModel {
        CatPuzzleModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
                       stageDefaults: defaults)
    }

    private func start(_ model: CatPuzzleModel, _ number: Int) async {
        model.startStage(number)
        await model.stagePreparation?.value
    }

    private func solve(_ model: CatPuzzleModel) {
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    private func miss(_ model: CatPuzzleModel, times: Int) {
        let solution = Set(model.puzzle.solutionCells)
        for cell in (0..<model.puzzle.cellCount).filter({ !solution.contains($0) && model.marks[$0] == .empty }).prefix(times) {
            model.findCat(cell: cell)
        }
    }

    @Test("ミス 0 回のクリアで 1 ずつ増え、最高も更新する。1 面目は自己ベスト扱いにしない")
    func increments() async {
        let model = makeModel(makeDefaults("inc"))
        await start(model, 1)
        solve(model)
        #expect(model.noMissStreak == 1 && model.noMissBest == 1 && !model.beatNoMissBest)
        await start(model, 2)
        solve(model)
        #expect(model.noMissStreak == 2 && model.noMissBest == 2 && model.beatNoMissBest)
    }

    @Test("ミス 1 回以上のクリアで 0 に戻り、最高は残る。最高に届かない連続は自己ベストにしない")
    func missedClearResets() async {
        let model = makeModel(makeDefaults("reset"))
        for n in 1...3 { await start(model, n); solve(model) }
        #expect(model.noMissStreak == 3)
        await start(model, 4)
        miss(model, times: 1)
        solve(model)
        #expect(model.noMissStreak == 0 && model.noMissBest == 3)
        await start(model, 5)
        solve(model)
        await start(model, 6)
        solve(model)
        #expect(model.noMissStreak == 2 && model.noMissBest == 3 && !model.beatNoMissBest)
    }

    @Test("ゲームオーバーで 0 に戻る。コンティニューしても戻ったまま")
    func gameOverResets() async {
        let model = makeModel(makeDefaults("over"))
        await start(model, 1); solve(model)
        await start(model, 2)
        miss(model, times: CatPuzzleModel.maxMistakes)
        #expect(model.isOfferingContinue && model.noMissStreak == 0)
        #expect(model.continueAfterAd())
        solve(model)
        #expect(model.isSolved && model.noMissStreak == 0 && model.noMissBest == 1)
    }

    @Test("ヒント・猫を教えるを使っても途切れない")
    func assistsDoNotBreak() async {
        let model = makeModel(makeDefaults("assist"))
        await start(model, 1)
        model.useHint()
        model.teachCat()
        solve(model)
        #expect(model.isSolved && model.mistakes == 0 && model.noMissStreak == 1)
    }

    @Test("自由に遊ぶは数えない")
    func freePlayIgnored() {
        let defaults = makeDefaults("free")
        let model = makeModel(defaults)
        model.newGame()
        solve(model)
        #expect(model.isSolved && model.noMissStreak == 0 && CatPuzzleNoMiss.streak(defaults) == 0)
    }

    @Test("端末に保存され、作り直したモデルに引き継がれる")
    func persists() async {
        let defaults = makeDefaults("persist")
        let model = makeModel(defaults)
        await start(model, 1); solve(model)
        await start(model, 2); solve(model)
        let reopened = makeModel(defaults)
        #expect(reopened.noMissStreak == 2 && reopened.noMissBest == 2)
    }
}
