import SwiftUI
import Core

/// マンカラ（#1626・企画倉庫）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct MancalaModule: GameModule {
    // **文字列リテラルで書く**（`MancalaModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `MancalaModel.gameID` との一致は `MancalaModuleTests` が機械的に確かめる。
    public let id = "mancala"
    public var title: String { tr("マンカラ") }
    public var description: String { tr("種をまいて、ストアにたくさん集めよう！CPU と対戦") }
    public var icon: Image { Image(systemName: "circle.grid.3x3.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(MancalaView(services: services))
    }

    /// 人間が一手も打っていない盤は「続き」ではない（#2934）。人間が後手のとき CPU の初手（と続く追加の手番）が
    /// 先に入るので、手数ではなく「待った」の戻り先（人間が打つたびに残る）か使用済みの印で人間の着手を見る。
    /// 人間が先手の局は最初の保存が必ず人間の手の後なので、従来どおり続きとして扱う。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(MancalaSnapshot.self, for: id) else { return false }
        return snap.humanFirst || snap.undoSlots != nil || snap.undoUsed == true
    }

    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
