import SwiftUI
import Core

/// ルーレット（#1318）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct RouletteModule: GameModule {
    public let id = "roulette"
    public let title = "ルーレット"
    public let description = "数字や色にチップを賭けて、ホイールの出目を当てよう"
    public var icon: Image { Image(systemName: "circle.circle.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(RouletteView(services: services))
    }

    /// 「続きから」で戻れるのは、回転中に中断した局と、口を置いたまま離れた賭け中だけ。
    /// 復活のチップだけを持ち回る中断データ（#1104。口が無い賭け中）は戻った先が賭け待ちで
    /// 「続き」ではないので、ハブの表示にも `game_open` の `resume` にも数えない
    /// （ブラックジャック・ポーカーと同じ扱い・#809）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(RouletteSnapshot.self, for: id) else { return false }
        return snap.phase == .spinning || !snap.bets.isEmpty
    }
}
