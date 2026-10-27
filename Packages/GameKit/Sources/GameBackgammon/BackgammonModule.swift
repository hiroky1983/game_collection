import SwiftUI
import Core

/// バックギャモン（#1322）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct BackgammonModule: GameModule {
    // **文字列リテラルで書く**（`BackgammonModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `BackgammonModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "backgammon"
    public var title: String { tr("バックギャモン") }
    public var description: String { tr("サイコロで駒を進めて先にあがれ！CPU と対戦") }
    public var icon: Image { Image(systemName: "dice.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(BackgammonView(services: services))
    }

    /// 人間が一手も動かしていない局（オープニングロールで CPU が先手を取って先に動いただけ）は「続き」ではない（#2934）。
    /// 鍵を持たない旧形式の中断データは従来どおり続きとして扱う。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(BackgammonSnapshot.self, for: id) else { return false }
        return snap.humanMoved ?? true
    }

    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
