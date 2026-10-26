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

    /// 10 回勝負の途中（#2551）の中断データだけを「続き」に数える。旧ルールの頃の中断データは
    /// 読めない（`PokerSnapshot` の版が違う）ので数えない。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(PokerSnapshot.self, for: id) else { return false }
        return snap.format == PokerSnapshot.currentFormat && snap.phase != .idle
    }

    /// 10 回勝負の何回目か（#2870）。単発戦は出さない。
    public func resumeProgress(in snapshots: SnapshotStore) -> String? {
        guard let snap = snapshots.load(PokerSnapshot.self, for: id),
              (snap.sessionFormat ?? .tenRounds) == .tenRounds else { return nil }
        return tr("%1$lld/%2$lld回目", min(max(snap.round, 1), PokerModel.roundsPerSession), PokerModel.roundsPerSession)
    }
}
