import SwiftUI
import Core

public struct GoModule: GameModule {
    public let id = "go"
    public var title: String { tr("囲碁") }
    public var description: String { tr("9路・13路盤で CPU と対局。ルールも読める") }
    // 碁石 2 つに見える記号を選ぶ。格子系のアイコンは将棋・ナンプレ・五目並べと
    // ハブ上で見分けが付かない。
    public var icon: Image { Image(systemName: "circlebadge.2.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GoView(services: services))
    }

    /// 一手も打っていない対局は「続き」ではない（#1847）。人間が白のとき、または人間が黒で置き石があるとき
    /// （白が先に打つ）は CPU の初手が先に入るので、人間の手番が来る前の 1 手は数えない（#2508）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(GoSnapshot.self, for: id) else { return false }
        let cpuFirst = snap.humanSide == GoStone.white.rawValue || snap.handicap >= 2
        return CPUOpening.humanHasMoved(totalMoves: snap.moves.count, cpuMovesFirst: cpuFirst)
            || (snap.phase ?? 0) != GoPhase.playing.rawValue
    }

    /// 対局中で、人間がまだ一手も打っていない局（#2161）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
