import Foundation

/// 中断スナップショットの永続化境界。`gameID` ごとにキーを分離する。
/// MVP ではローカルのみ・常に上書き（積み上がらない）。`load` の非 nil で「続きから」を判定する。
public protocol SnapshotStore {
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T?
    func clear(for gameID: String)
    /// スナップショットが存在するか（「続きから」表示の判定用）。
    func exists(for gameID: String) -> Bool
    /// スナップショットを最後に書き込んだ時刻（#660）。ハブの「つづき・最近」の**並び順にだけ**使う。
    ///
    /// 既定は nil。**新しい永続化は増やさず、実装が既に持っている情報だけを返す**という約束にしてある
    /// （`FileSnapshotStore` はファイル属性を読むだけ）。時刻を持たない実装が nil を返しても
    /// 呼び出し側は「順序の手掛かりが無い」として扱えるので、保存形式を変えずに済む。
    func modifiedAt(for gameID: String) -> Date?
}

public extension SnapshotStore {
    /// 時刻を持たない実装（テスト用のメモリ実装など）はここに落ちる。
    func modifiedAt(for gameID: String) -> Date? { nil }
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

    /// ファイルの更新日時をそのまま返す（#660）。保存形式には何も足さない。
    public func modifiedAt(for gameID: String) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url(for: gameID).path)
        return attributes?[.modificationDate] as? Date
    }
}

/// `clear(for:)` を横から知らせる `SnapshotStore`（#663）。読み書きも保存形式もそのまま下へ渡す。
///
/// 中断データは各ゲームが終局・やり直し・設定の切り替えなど 40 か所以上で消しており、
/// それぞれに「中断のお知らせを取り消す」を書き足すと付け忘れが必ず出る。消す側を 1 か所で捕まえる。
public struct ClearObservingSnapshotStore: SnapshotStore {
    private let base: SnapshotStore
    private let onClear: @Sendable (String) -> Void

    public init(base: SnapshotStore, onClear: @escaping @Sendable (String) -> Void) {
        self.base = base
        self.onClear = onClear
    }

    public func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        try base.save(snapshot, for: gameID)
    }

    public func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        base.load(type, for: gameID)
    }

    public func clear(for gameID: String) {
        base.clear(for: gameID)
        onClear(gameID)
    }

    public func exists(for gameID: String) -> Bool {
        base.exists(for: gameID)
    }

    public func modifiedAt(for gameID: String) -> Date? {
        base.modifiedAt(for: gameID)
    }
}
