import Core
import Foundation
@testable import GameRunner
import CoreTestSupport
// 自動操縦（`autoPlayCurrentStage` / `failCurrentStage`）は横断のテストとも共有するので
// `GameRunnerTestSupport` に置いてある（#1150）。
import GameRunnerTestSupport

/// 既定オフ・使い捨ての設定。`UserDefaults.standard` を汚さない。
func makePreference(_ suite: String) -> FeedbackPreference {
    let name = "asobiba.runner.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
}

/// Game Center へ実際に送られたものを記録するスパイ。
final class SpyGameCenterService: GameCenterService, @unchecked Sendable {
    var scores: [GameCenterScore] = []
    @MainActor func submit(_ score: GameCenterScore) { scores.append(score) }
    @MainActor func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
}

@MainActor
func makeServices(
    store: SnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    gameCenter: GameCenterService? = nil,
    review: ReviewRequestService? = nil
) -> GameServices {
    GameServices(
        snapshots: store,
        ads: NoopAdService(),
        review: review,
        playLog: log,
        gameCenter: gameCenter.map {
            GameCenterReporter(service: $0, allowedGameIDs: [RunnerModel.gameID])
        }
    )
}
