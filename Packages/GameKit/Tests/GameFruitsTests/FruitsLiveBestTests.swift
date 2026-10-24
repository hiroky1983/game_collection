import Testing
import Foundation
import Core
@testable import GameFruits
import CoreTestSupport

/// #2808: プレイ中のヘッダーに出す「ベスト」（2048 の #2615 と同じ形）。
@Suite("盆栽 プレイ中のベスト（#2808）")
@MainActor
struct FruitsLiveBestTests {
    private func makeServices(suite: String, savedBest: Int?) -> GameServices {
        let name = "asobiba.fruitslivebest.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        if let savedBest {
            _ = log.recordResult(gameID: "fruits", outcome: .loss,
                                 score: GameScore(metric: .points, points: savedBest))
        }
        return GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    @Test("記録もスコアも無ければ出さない")
    func hiddenWithoutRecordAndScore() {
        let model = FruitsModel(services: makeServices(suite: "none", savedBest: nil), seed: 1)
        #expect(model.liveBestScore == nil)
    }

    @Test("保存済みの自己ベストがあれば、スコア 0 でも出す")
    func showsSavedBest() {
        let model = FruitsModel(services: makeServices(suite: "saved", savedBest: 4200), seed: 1)
        #expect(model.liveBestScore == 4200)
    }
}
