import SwiftUI
import Core

public struct ConcentrationModule: GameModule {
    public let id = "concentration"
    public let title = "神経衰弱"
    public let description = "記憶力勝負！CPU と対戦しよう"
    public var icon: Image { Image(systemName: "brain.head.profile") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ConcentrationView(services: services))
    }

    /// 一枚もめくっていない盤は「続き」ではない（#1847）。めくる・揃える・待ったを使うと、
    /// 表向きの札・揃った札・得点・待ったの使用のどれかが変わる。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(ConcentrationSnapshot.self, for: id) else { return false }
        return snap.isFaceUp.contains(true) || snap.isMatched.contains(true)
            || snap.playerScore > 0 || snap.cpuScore > 0 || snap.mattaUsed
    }
}
