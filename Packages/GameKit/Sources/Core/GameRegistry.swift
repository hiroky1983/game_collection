/// ハブが列挙する `GameModule` のレジストリ。登録順に表示される。
public struct GameRegistry {
    public let modules: [GameModule]

    public init(_ modules: [GameModule]) {
        self.modules = modules
    }

    public func module(id: String) -> GameModule? {
        modules.first { $0.id == id }
    }

    /// `gameID` の中断データが「続きから」で戻れる途中の局か（#809）。登録外の ID は false。
    public func hasResumableSnapshot(gameID: String, in snapshots: SnapshotStore) -> Bool {
        module(id: gameID)?.hasResumableSnapshot(in: snapshots) ?? false
    }
}
