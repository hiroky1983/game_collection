import SwiftUI
import Core

public struct OthelloModule: GameModule {
    public let id = "othello"
    public let title = "オセロ"
    public let description = "石を挟んでひっくり返せ！CPU に挑戦"
    public var icon: Image { Image(systemName: "circle.lefthalf.filled") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OthelloView(services: services))
    }

    /// 初形（石 4 個）のままの盤は「続き」ではない（#1572）。一手ごとに石が 1 個増えるので、石の数で見分けられる。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(OthelloSnapshot.self, for: id) else { return false }
        return snap.cells.compactMap { $0 }.count > 4
    }
}
