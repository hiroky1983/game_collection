import Foundation

/// 中断スナップショットの永続化境界。`gameID` ごとにキーを分離する。
/// MVP ではローカルのみ・常に上書き（積み上がらない）。`load` の非 nil で「続きから」を判定する。
public protocol SnapshotStore {
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T?
    func clear(for gameID: String)
    /// スナップショットが存在するか（「続きから」表示の判定用）。
    func exists(for gameID: String) -> Bool
}

/// Application Support 配下に `gameID` 別の JSON ファイルとして保存する実装。
public struct FileSnapshotStore: SnapshotStore {
    private let directory: URL
    private let fileManager: FileManager

    public init(
        subdirectory: String = "Snapshots",
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent(subdirectory, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for gameID: String) -> URL {
        directory.appendingPathComponent("\(gameID).json", isDirectory: false)
    }

    public func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url(for: gameID), options: .atomic)
    }

    public func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: gameID)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func clear(for gameID: String) {
        try? fileManager.removeItem(at: url(for: gameID))
    }

    public func exists(for gameID: String) -> Bool {
        fileManager.fileExists(atPath: url(for: gameID).path)
    }
}
