import SwiftUI
import Core

public struct GomokuModule: GameModule {
    public let id = "gomoku"
    public let title = "五目並べ"
    public let description = "先に5つ並べた方が勝ち！CPU に挑戦"
    public var icon: Image { Image(systemName: "circle.grid.3x3.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GomokuView(services: services))
    }

    /// 一手も打っていない盤は「続き」ではない（#1572）。手順を持たない旧形式は盤上の石の数で見る。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(GomokuSnapshot.self, for: id) else { return false }
        return !(snap.moveHistory ?? []).isEmpty || snap.cells.contains { $0 != nil }
    }
}
