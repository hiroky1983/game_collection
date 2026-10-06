import SwiftUI
import Core

public struct GoModule: GameModule {
    public let id = "go"
    public let title = "囲碁"
    public let description = "9路盤で CPU と対局。ルールも読める"
    // 碁石 2 つに見える記号を選ぶ。格子系のアイコンは将棋・ナンプレ・五目並べと
    // ハブ上で見分けが付かない。
    public var icon: Image { Image(systemName: "circlebadge.2.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GoView(services: services))
    }

    /// 一手も打っていない対局は「続き」ではない（#1847）。人間が白のときは CPU の初手が先に入るので、
    /// 人間の手番が来る前の 1 手は数えない。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(GoSnapshot.self, for: id) else { return false }
        let cpuOpening = snap.humanSide == GoStone.white.rawValue ? 1 : 0
        return snap.moves.count > cpuOpening || (snap.phase ?? 0) != GoPhase.playing.rawValue
    }
}
