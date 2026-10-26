import SwiftUI
import Core

public struct OthelloModule: GameModule {
    public let id = "othello"
    public var title: String { tr("オセロ") }
    public var description: String { tr("石を挟んでひっくり返せ！CPU に挑戦") }
    public var icon: Image { Image(systemName: "circle.lefthalf.filled") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OthelloView(services: services))
    }

    /// 初形（石 4 個）から人間が一手も打っていない盤は「続き」ではない（#1572）。一手ごとに石が 1 個増えるので、
    /// 石の数で見分けられる。人間が白のときは CPU の初手（黒）が先に入るので、それだけでは数えない（#2508）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(OthelloSnapshot.self, for: id) else { return false }
        let moves = snap.cells.compactMap { $0 }.count - 4
        return CPUOpening.humanHasMoved(totalMoves: moves, cpuMovesFirst: snap.humanSide == OthelloStone.white.rawValue)
    }

    /// 初形から人間が一手も打っていない盤（#2161）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
