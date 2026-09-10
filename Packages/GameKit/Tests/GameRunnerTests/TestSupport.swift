import Core
import Foundation
@testable import GameRunner

/// テスト用の使い捨てスナップショット置き場。
final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private(set) var saveCount = 0
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        saveCount += 1
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
    /// 壊れたデータを流し込む（復元の検め方を試すため）。
    func inject(_ data: Data, for gameID: String) { store[gameID] = data }
}

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
    gameCenter: GameCenterService? = nil
) -> GameServices {
    GameServices(
        snapshots: store,
        ads: NoopAdService(),
        playLog: log,
        gameCenter: gameCenter.map {
            GameCenterReporter(service: $0, allowedGameIDs: [RunnerModel.gameID])
        }
    )
}

/// 自動操縦でいまのステージをゴールまで走らせる。
/// - Returns: 決着したか（打ち切りに達したら false）。
@MainActor
@discardableResult
func autoPlayCurrentStage(_ model: RunnerModel, maxFrames: Int = 60 * 300) -> Bool {
    if model.phase == .ready {
        model.press()
        model.release()
    }
    var frames = 0
    // `.falling` は `isRunning` に含めない（ミス直後の短い演出中はタップ・一時停止を効かせない
    // ための設計）ので、ここで打ち切らず `.failed` に落ち着くまで回し続ける。
    while model.phase.isRunning || model.phase == .falling, frames < maxFrames {
        frames += 1
        if RunnerAutoPilot.shouldJump(field: model.field) {
            model.press()
            model.release()
        }
        model.tick(dt: 1.0 / 60)
    }
    return frames < maxFrames
}

/// 跳ばずに走らせてミスさせる。
@MainActor
func failCurrentStage(_ model: RunnerModel, stopAfterCheckpoint: Bool = false) {
    if model.phase == .ready {
        model.press()
        model.release()
    }
    var frames = 0
    // 同上: `.falling` の演出時間ぶんも回して `.failed` まで進める。
    while model.phase.isRunning || model.phase == .falling, frames < 60 * 300 {
        frames += 1
        // `stopAfterCheckpoint` のときだけ、チェックポイントを通過するまで自動操縦で走る。
        // それ以外は一度も跳ばないので、最初の障害で必ずミスになる。
        if stopAfterCheckpoint, !model.field.passedCheckpoint,
           RunnerAutoPilot.shouldJump(field: model.field) {
            model.press()
            model.release()
        }
        model.tick(dt: 1.0 / 60)
    }
}
