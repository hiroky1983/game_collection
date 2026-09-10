import Core
import Foundation
@testable import GameHanafuda

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
            GameCenterReporter(service: $0, allowedGameIDs: [HanafudaModel.gameID])
        }
    )
}

// MARK: - 札を名前で引く

extension HanafudaCard {
    /// 札名から 1 枚引く。テストの期待値を「松に鶴」のように読める形で書くためのもの。
    static func named(_ name: String) -> HanafudaCard {
        guard let card = fullDeck.first(where: { $0.name == name }) else {
            fatalError("そんな札は無い: \(name)")
        }
        return card
    }

    /// その月のカス札を n 枚。
    static func kasu(month: Int, count: Int = 1) -> [HanafudaCard] {
        Array(fullDeck.filter { $0.month == month && $0.kind == .kasu }.prefix(count))
    }

    /// カス札をまとめて n 枚（月をまたいで前から）。
    static func anyKasu(_ count: Int) -> [HanafudaCard] {
        Array(fullDeck.filter { $0.kind == .kasu }.prefix(count))
    }

    /// タネ札をまとめて n 枚（盃を避けたいときは `excluding` に渡す）。
    static func anyTane(_ count: Int, excluding excluded: Set<Int> = []) -> [HanafudaCard] {
        Array(fullDeck.filter { $0.kind == .tane && !excluded.contains($0.id) }.prefix(count))
    }

    /// 短冊札をまとめて n 枚。
    static func anyTanzaku(_ count: Int, excluding excluded: Set<Int> = []) -> [HanafudaCard] {
        Array(fullDeck.filter { $0.kind == .tanzaku && !excluded.contains($0.id) }.prefix(count))
    }
}

/// 酒の役を数えない設定（役の重なりを切り分けたいときに使う）。
let noSakeOptions = HanafudaOptions(sakeYakuEnabled: false)
/// 既定（酒の役あり）。
let defaultOptions = HanafudaOptions()
