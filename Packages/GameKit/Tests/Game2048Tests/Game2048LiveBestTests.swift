import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

/// #2615: プレイ中のヘッダーに出す「ベスト」。
@Suite("2048 プレイ中のベスト（#2615）")
@MainActor
struct Game2048LiveBestTests {
    private func makeServices(suite: String, savedBest: Int?) -> GameServices {
        let name = "asobiba.2048livebest.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        if let savedBest {
            _ = log.recordResult(gameID: "2048", outcome: .loss,
                                 score: GameScore(metric: .points, points: savedBest))
        }
        return GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    private let board = [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]

    @Test("記録もスコアも無ければ出さない")
    func hiddenWithoutRecordAndScore() {
        let model = Game2048Model(services: makeServices(suite: "none", savedBest: nil), board: board, score: 0)
        #expect(model.liveBestScore == nil)
    }

    @Test("記録が無くてもスコアが付けば、そのスコアがベストとして追従する")
    func followsScoreWithoutRecord() {
        let model = Game2048Model(services: makeServices(suite: "noRecord", savedBest: nil), board: board, score: 120)
        #expect(model.liveBestScore == 120)
    }

    @Test("保存済みの自己ベストが高ければそれを出し、スコアが超えた瞬間に追従する")
    func savedBestThenFollows() {
        let services = makeServices(suite: "saved", savedBest: 5000)
        let low = Game2048Model(services: services, board: board, score: 100)
        #expect(low.liveBestScore == 5000)
        let high = Game2048Model(services: services, board: board, score: 5200)
        #expect(high.liveBestScore == 5200)
    }

    @Test("今回の最高タイルは盤の最大値（#2812）")
    func highestTileIsBoardMax() {
        let model = Game2048Model(services: makeServices(suite: "tile", savedBest: nil),
                                  board: [[2, 512, 0, 0], [0, 64, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 0)
        #expect(model.highestTile == 512)
    }
}

/// #3488: 「2048 達成！」の幕を出したまま復元しても、幕の直下の記録行が消えない。
@Suite("2048 達成幕の復元と記録行（#3488）")
@MainActor
struct Game2048WinPromptRecordRestoreTests {
    @Test("幕を出したまま復元すると記録行が出て、記録は二重に加算されない")
    func restoredWinPromptKeepsRecordRow() {
        let name = "asobiba.2048winrestore.tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService(), playLog: log)

        let model = Game2048Model(services: services,
                                  board: [[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 100)
        model.move(.left)
        #expect(model.showWinPrompt)
        #expect(model.recordResult != nil)
        let saved = log.record(gameID: "2048")

        let restored = Game2048Model(services: services)
        #expect(restored.showWinPrompt)
        #expect(restored.recordResult?.record == saved)
        #expect(log.record(gameID: "2048") == saved, "復元で gameDidFinish を再実行しない")
    }

    @Test("幕を出していない復元では記録行を出さない")
    func restoredWithoutPromptHasNoRecordRow() {
        let name = "asobiba.2048winrestore.tests.none"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        _ = log.recordResult(gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 500))
        let store = MemorySnapshotStore()
        try? store.save(Game2048Snapshot(board: [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 6),
                   for: "2048")
        let services = GameServices(snapshots: store, ads: NoopAdService(), playLog: log)
        #expect(Game2048Model(services: services).recordResult == nil)
    }
}
