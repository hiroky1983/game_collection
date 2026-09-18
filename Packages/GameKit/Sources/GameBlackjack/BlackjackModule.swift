import SwiftUI
import Core

public struct BlackjackModule: GameModule {
    public let id = "blackjack"
    public let title = "ブラックジャック"
    public let description = "ディーラーに勝てるか。チップを稼ごう！"
    public var icon: Image { Image(systemName: "suit.club.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(BlackjackView(services: services))
    }

    /// 復活（#499）のチップだけを持ち回る中断データ（#1104）は手を持たない。戻った先は
    /// 賭け待ちで「続き」ではないので、ハブの表示にも `game_open` の `resume` にも数えない
    /// （将棋・チェスの見返しと同じ扱い・#809）。旧形式（#439 以前）は `playerHand` に手が入る。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(BlackjackSnapshot.self, for: id) else { return false }
        return !(snap.hands ?? []).isEmpty || !snap.playerHand.isEmpty
    }
}
