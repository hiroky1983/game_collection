import SwiftUI
import Core

public struct GomokuModule: GameModule {
    public let id = "gomoku"
    public var title: String { tr("五目並べ") }
    public var description: String { tr("先に5つ並べた方が勝ち！CPU に挑戦") }
    public var icon: Image { Image(systemName: "circle.grid.3x3.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GomokuView(services: services))
    }

    /// 人間が一手も打っていない盤は「続き」ではない（#1572）。手順を持たない旧形式は盤上の石の数で見る。
    /// 人間が白のときは CPU の初手（黒）が先に入るので、それだけでは数えない（#2508）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(GomokuSnapshot.self, for: id) else { return false }
        let total = snap.moveHistory?.count ?? snap.cells.filter { $0 != nil }.count
        return CPUOpening.humanHasMoved(totalMoves: total, cpuMovesFirst: snap.humanSide == GomokuStone.white.rawValue)
    }

    /// 人間が一手も打っていない盤（#2161）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
