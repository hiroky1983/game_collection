import SwiftUI
import Core

public struct BlackjackModule: GameModule {
    public let id = "blackjack"
    public var title: String { tr("ブラックジャック") }
    public var description: String { tr("ディーラーに勝てるか。10回勝負で何勝できる？") }
    public var icon: Image { Image(systemName: "suit.club.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(BlackjackView(services: services))
    }

    /// ラウンドの合間の中断データ（回数・点・連勝だけで手を持たない）は「続き」ではないので、
    /// ハブの表示にも `game_open` の `resume` にも数えない（将棋・チェスの見返しと同じ扱い・#809）。
    /// チップ制だった頃の中断データはデコードできず、ここでも false になる。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(BlackjackSnapshot.self, for: id) else { return false }
        return !snap.hands.isEmpty
    }
}
