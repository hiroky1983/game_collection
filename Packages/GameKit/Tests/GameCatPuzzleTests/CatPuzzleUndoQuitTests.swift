import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 「戻す」「リセット」で手つかずの盤まで戻したら、離脱の印も戻す（#3458）。
@Suite("ねこさがし 戻す・リセットと離脱の印（#3458）")
@MainActor
struct CatPuzzleUndoQuitTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID])
        )
    }

    private func makeModel(_ spy: SpyAnalyticsService, name: String) async -> (CatPuzzleModel, GameServices) {
        let suite = "asobiba.catpuzzle.undoquit.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let services = makeServices(spy)
        services.gameDidStart(gameID: CatPuzzleModel.gameID)
        let model = CatPuzzleModel(services: services, stageDefaults: defaults)
        model.startStage(1)
        await model.stagePreparation?.value
        return (model, services)
    }

    private func firstFreeCell(_ model: CatPuzzleModel) -> Int {
        (0..<model.puzzle.side * model.puzzle.side).first {
            !model.isFixed(cell: $0) && model.marks[$0] == .empty
        }!
    }

    @Test("× を付けて「戻す」で手つかずに戻したら、離れても離脱に数えない")
    func undoToUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let (model, services) = await makeModel(spy, name: "undo")
        _ = model.toggleCross(cell: firstFreeCell(model))
        model.undo()
        #expect(!model.hasProgressToLose, "前提: 印が空に戻った")
        services.analytics?.leaveGame(gameID: CatPuzzleModel.gameID, isResumable: false)
        #expect(spy.quits.isEmpty)
    }

    @Test("× を付けて「リセット」で手つかずに戻したら、離れても離脱に数えない")
    func resetToUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let (model, services) = await makeModel(spy, name: "reset")
        _ = model.toggleCross(cell: firstFreeCell(model))
        model.reset()
        #expect(!model.hasProgressToLose)
        services.analytics?.leaveGame(gameID: CatPuzzleModel.gameID, isResumable: false)
        #expect(spy.quits.isEmpty)
    }

    @Test("印が 1 つでも残っていれば、従来どおり離脱に数える（対照）")
    func partialUndoStaysQuit() async {
        let spy = SpyAnalyticsService()
        let (model, services) = await makeModel(spy, name: "partial")
        let first = firstFreeCell(model)
        _ = model.toggleCross(cell: first)
        _ = model.toggleCross(cell: (0..<model.puzzle.side * model.puzzle.side).first {
            $0 != first && !model.isFixed(cell: $0) && model.marks[$0] == .empty
        }!)
        model.undo()
        #expect(model.hasProgressToLose)
        services.analytics?.leaveGame(gameID: CatPuzzleModel.gameID, isResumable: false)
        #expect(spy.quits.map(\.gameID) == [CatPuzzleModel.gameID])
    }

    @Test("ヒントを使った盤は、印を戻しても離脱に数える（対照）")
    func hintedBoardStaysQuit() async {
        let spy = SpyAnalyticsService()
        let (model, services) = await makeModel(spy, name: "hint")
        _ = model.toggleCross(cell: firstFreeCell(model))
        model.useHint()
        model.reset()
        #expect(model.hintsUsed > 0)
        services.analytics?.leaveGame(gameID: CatPuzzleModel.gameID, isResumable: false)
        #expect(spy.quits.map(\.gameID) == [CatPuzzleModel.gameID])
    }
}
