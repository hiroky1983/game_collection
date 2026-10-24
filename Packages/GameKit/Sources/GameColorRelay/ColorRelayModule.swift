import SwiftUI
import Core

/// いろリレー（#1320）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct ColorRelayModule: GameModule {
    // **文字列リテラルで書く**（`ColorRelayModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `ColorRelayModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "colorrelay"
    public var title: String { tr("いろリレー") }
    public var description: String { tr("色か数字をつないで手札を出し切ろう。CPU3人と対戦") }
    public var icon: Image { Image(systemName: "rectangle.on.rectangle.angled") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ColorRelayView(services: services))
    }

    /// 2 ゲーム目以降は CPU が親で、人間が打つ前に CPU の先手が保存される。それだけの局は「続き」ではない
    /// （#2763。チェス・将棋などの #2508 と同じ型）。旧バージョンの保存データは「打った」扱い。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(ColorRelaySnapshot.self, for: id) else { return false }
        return snap.humanHasActed ?? true
    }

    /// 人間が一手も打っていない局（#2161）。開き直したときに `game_start` を数え直すのに使う。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(ColorRelaySnapshot.self, for: id) else { return false }
        return !(snap.humanHasActed ?? true)
    }
}
