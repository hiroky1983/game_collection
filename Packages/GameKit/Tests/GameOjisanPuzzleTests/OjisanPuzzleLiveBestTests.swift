import Testing
import Foundation
import Core
@testable import GameOjisanPuzzle
import CoreTestSupport

/// #2808: プレイ中のヘッダーに出す「ベスト」（2048 の #2615 と同じ形）。
@Suite("荷物運びパズル プレイ中のベスト（#2808）")
@MainActor
struct OjisanPuzzleLiveBestTests {
    private func makeServices(suite: String, savedBest: Int?) -> GameServices {
        let name = "asobiba.ojisanlivebest.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        if let savedBest {
            _ = log.recordResult(gameID: "ojisanpuzzle", outcome: .loss,
                                 score: GameScore(metric: .points, points: savedBest, variant: OjisanPuzzleMode.puzzle.recordVariant, variantLabel: "パズル"))
        }
        return GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    @Test("記録もスコアも無ければ出さない")
    func hiddenWithoutRecordAndScore() {
        let model = OjisanPuzzleModel(services: makeServices(suite: "none", savedBest: nil), mode: .puzzle, announcesStart: false)
        #expect(model.liveBestScore == nil)
    }

    @Test("保存済みの自己ベストがあれば、スコア 0 でも出す")
    func showsSavedBest() {
        let model = OjisanPuzzleModel(services: makeServices(suite: "saved", savedBest: 4200), mode: .puzzle, announcesStart: false)
        #expect(model.liveBestScore == 4200)
    }

    @Test("荷運びモードの自己ベストはタイムなので出さない")
    func hiddenInCleanupMode() {
        let model = OjisanPuzzleModel(services: makeServices(suite: "cleanup", savedBest: 4200), mode: .backpain, announcesStart: false)
        #expect(model.liveBestScore == nil)
    }
}
