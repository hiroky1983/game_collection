import SwiftUI
import Core

public struct BaccaratModule: GameModule {
    public let id = "baccarat"
    public let title = "バカラ"
    public let description = "プレイヤーとバンカー、勝つのはどっち？"
    public var icon: Image { Image(systemName: "suit.diamond.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(BaccaratView(services: services))
    }

    /// 賭けた瞬間に決着まで進むので、**持ち回る「途中の局」が存在しない**。
    /// 中断データは復活（#499）のチップだけを持つ賭け待ちの形（#1104）なので、
    /// ハブの「続きから」にも `game_open` の `resume` にも数えない（#809）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool { false }
}
