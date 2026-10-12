import Testing
import Foundation
import CoreEngine

/// `FileSnapshotStore.load` が壊れた中断データを残さないこと（#1914）。
/// 残ると `exists` が true のまま「中断データあり」と見なされ、開始シートが出ずに空の盤で始まる。
@Suite("FileSnapshotStore")
struct FileSnapshotStoreTests {
    private struct Sample: Codable, Equatable {
        var value: Int
    }

    private static func makeStore() -> (store: FileSnapshotStore, subdirectory: String) {
        let subdirectory = "FileSnapshotStoreTests-\(UUID().uuidString)"
        return (FileSnapshotStore(subdirectory: subdirectory), subdirectory)
    }

    /// `FileSnapshotStore` の保存先は公開されていないので、同じ規則（Application Support /
    /// subdirectory / `<gameID>.json`）で組み立て直す。実装とずれたら書き込みが失敗して気付ける。
    private static func directoryURL(subdirectory: String) throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
    }

    private static func fileURL(subdirectory: String, gameID: String) throws -> URL {
        try directoryURL(subdirectory: subdirectory).appendingPathComponent("\(gameID).json", isDirectory: false)
    }

    private static func removeDirectory(_ subdirectory: String) throws {
        try FileManager.default.removeItem(at: directoryURL(subdirectory: subdirectory))
    }

    @Test("壊れた JSON を load すると nil で、ファイルも消えて exists が false になる")
    func brokenJSONIsClearedOnLoad() throws {
        let (store, subdirectory) = Self.makeStore()
        defer { try? Self.removeDirectory(subdirectory) }
        try Data("{\"value\":".utf8).write(to: Self.fileURL(subdirectory: subdirectory, gameID: "game"))
        #expect(store.exists(for: "game"), "前提: 壊れたファイルが置かれている")

        #expect(store.load(Sample.self, for: "game") == nil)
        #expect(!store.exists(for: "game"), "decode できないファイルが残っている")
    }

    @Test("必須キーが欠けた JSON も同じく消える")
    func missingRequiredKeyIsClearedOnLoad() throws {
        let (store, subdirectory) = Self.makeStore()
        defer { try? Self.removeDirectory(subdirectory) }
        try Data("{\"other\":1}".utf8).write(to: Self.fileURL(subdirectory: subdirectory, gameID: "game"))

        #expect(store.load(Sample.self, for: "game") == nil)
        #expect(!store.exists(for: "game"))
    }

    @Test("正常なデータは load しても消えない")
    func validSnapshotSurvivesLoad() throws {
        let (store, subdirectory) = Self.makeStore()
        defer { try? Self.removeDirectory(subdirectory) }
        try store.save(Sample(value: 7), for: "game")

        #expect(store.load(Sample.self, for: "game") == Sample(value: 7))
        #expect(store.exists(for: "game"), "正常なデータが load で消えた")
        #expect(store.load(Sample.self, for: "game") == Sample(value: 7), "2 回目も読める")
    }

    @Test("ファイルが無いときの load は nil のまま副作用なし")
    func missingFileLoadsNil() {
        let (store, subdirectory) = Self.makeStore()
        defer { try? Self.removeDirectory(subdirectory) }

        #expect(store.load(Sample.self, for: "none") == nil)
        #expect(!store.exists(for: "none"))
    }

    @Test("壊れていない別 ID のデータには触れない")
    func otherGameUntouched() throws {
        let (store, subdirectory) = Self.makeStore()
        defer { try? Self.removeDirectory(subdirectory) }
        try store.save(Sample(value: 1), for: "good")
        try Data("not json".utf8).write(to: Self.fileURL(subdirectory: subdirectory, gameID: "bad"))

        #expect(store.load(Sample.self, for: "bad") == nil)
        #expect(store.load(Sample.self, for: "good") == Sample(value: 1))
    }
}
