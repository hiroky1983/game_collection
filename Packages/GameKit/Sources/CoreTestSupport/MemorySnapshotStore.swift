import Foundation
import Core

/// テスト用の中断データ置き場（#841）。ファイルに書かず、プロセス内だけで完結させる。
///
/// 以前は各テストファイルが 12 行ほどの同じ実装を `private` で持っており、47 か所に散らばっていた。
/// `SnapshotStore` に要件を 1 つ足すだけで全部を直すことになるので、ここに 1 つだけ置く。
/// 製品コードからは import しない（`CoreTestSupportTests` の走査で固定している）。
public final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    /// `save` が呼ばれた回数（保存の頻度を検める用）。
    public private(set) var saveCount = 0

    public init() {}

    public func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        storage[gameID] = try JSONEncoder().encode(snapshot)
        saveCount += 1
    }

    public func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = storage[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func clear(for gameID: String) { storage.removeValue(forKey: gameID) }

    public func exists(for gameID: String) -> Bool { storage[gameID] != nil }

    /// 1 件も保存されていないか。
    public var isEmpty: Bool { storage.isEmpty }

    /// 保存された JSON そのもの（鍵の有無や旧形式との互換を検める用）。
    public func rawData(for gameID: String) -> Data? { storage[gameID] }

    /// 任意のバイト列をそのまま置く（旧形式・壊れた形式の中断データを流し込む用）。`saveCount` は数えない。
    public func inject(_ data: Data, for gameID: String) { storage[gameID] = data }
}
