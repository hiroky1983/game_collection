import SwiftUI
import Core

public struct PokerModule: GameModule {
    public let id = "poker"
    public let title = "ポーカー"
    public let description = "5カードドロー。チップを稼ごう！"
    public var icon: Image { Image(systemName: "suit.spade.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(PokerView(services: services))
    }

    /// 復活（#499）のチップだけを持ち回る中断データ（#1104）は局を持たない（`.idle`）。
    /// 戻った先は次の局の開始シートで「続き」ではないので、ハブの表示にも `game_open` の
    /// `resume` にも数えない（将棋・チェスの見返しと同じ扱い・#809）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(PokerSnapshot.self, for: id) else { return false }
        return snap.phase != .idle
    }
}
