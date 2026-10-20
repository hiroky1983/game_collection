import SwiftUI
import Core

public struct PokerModule: GameModule {
    public let id = "poker"
    public var title: String { tr("ポーカー") }
    public var description: String { tr("5カードドロー。10回勝負で役の点を競おう！") }
    public var icon: Image { Image(systemName: "suit.spade.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(PokerView(services: services))
    }

    /// 局を持たない中断データ（`.idle`）は「続き」ではないので、ハブの表示にも `game_open` の
    /// `resume` にも数えない（将棋・チェスの見返しと同じ扱い・#809）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(PokerSnapshot.self, for: id) else { return false }
        return snap.phase != .idle
    }
}
