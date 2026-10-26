import SwiftUI
import Core

public struct DaifugoModule: GameModule {
    public let id = "daifugo"
    public var title: String { daifugoGameName() }
    public var description: String { tr("CPU3人と対戦。革命・8切りあり！") }
    public var icon: Image { Image(systemName: "crown.fill") }

    public init() {}

    /// 人間が一度も動いていない局（CPU が親で先に出しただけ）は「続き」ではない（#2774）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(DaifugoSnapshot.self, for: id) else { return false }
        return DaifugoSnapshot.humanHasActed(lastActions: snap.lastActions)
    }

    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(DaifugoSnapshot.self, for: id) else { return false }
        return !DaifugoSnapshot.humanHasActed(lastActions: snap.lastActions)
    }

    public func makeView(services: GameServices) -> AnyView {
        AnyView(DaifugoView(services: services))
    }
}
