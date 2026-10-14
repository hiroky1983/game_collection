import SwiftUI
import Core

/// 線つなぎ（#2235）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// 表示名に「ナンバーリンク」（ニコリのペンシルパズルの名前）・「Numberlink」・「Flow」を使わない
/// （Issue #2235 の権利チェック）。一般語の「線つなぎ」/ "Connect Pairs" にする。
public struct TsunagiModule: GameModule {
    // **文字列リテラルで書く**（`TsunagiModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `TsunagiModel.gameID` との一致は `TsunagiModuleTests` が機械的に確かめる。
    public let id = "tsunagi"
    public var title: String { tr("線つなぎ") }
    public var description: String { tr("同じ数字を線でつないで、マスを全部うめよう") }
    public var icon: Image { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(TsunagiView(services: services))
    }

    /// 開いただけで一度も線を引いていない盤は「続き」ではない（#1847）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(TsunagiSnapshot.self, for: id) else { return false }
        return snap.moves > 0
    }

    /// 保存はあるが一度も線を引いていない盤（#2161）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(TsunagiSnapshot.self, for: id) else { return false }
        return snap.moves == 0
    }
}
