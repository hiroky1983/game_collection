import SwiftUI
import Core

public struct BlackjackModule: GameModule {
    public let id = "blackjack"
    public var title: String { tr("ブラックジャック") }
    public var description: String { tr("ディーラーと10回勝負。勝ち数で自己ベストを狙おう！") }
    public var icon: Image { Image(systemName: "suit.club.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(BlackjackView(services: services))
    }

    /// 中断データは 1 回目を配ったあと（10 回勝負の途中）にしか書かないので、読めれば続きがある（#2552）。
    /// #2552 より前の形式は読めず（`BlackjackSnapshot` の注記）、続きには数えない。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(BlackjackSnapshot.self, for: id) else { return false }
        return !snap.hands.isEmpty
    }
}
