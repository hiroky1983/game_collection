import SwiftUI
import Core

/// ババ抜き（#1577）の `GameModule` 登録口。
///
/// 企画倉庫から v1.1.14 でハブに公開（会長決裁 2026-10-22）。
///
/// 表示名「ババ抜き」（英語 Old Maid）は伝統的なトランプ遊びの一般名称で、Web 検索で文字商標の登録は
/// 見つからなかった（Issue #1577 の権利チェック）。ババの図案は共通部品のジョーカー（道化帽・#397）。
public struct OldMaidModule: GameModule {
    // **文字列リテラルで書く**（`OldMaidModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `OldMaidModel.gameID` との一致は `OldMaidModuleTests` が機械的に確かめる。
    public let id = "oldmaid"
    public var title: String { tr("ババ抜き") }
    public var description: String { tr("CPUの顔を読んで、ジョーカーをよけよう。CPU3人と対戦") }
    public var icon: Image { Image(systemName: "theatermasks.fill") }

    public init() {}

    /// あなたが一度も引いていない局（2 ゲーム目以降で CPU が先に引いただけ）は「続き」ではない（#3000）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.load(OldMaidSnapshot.self, for: id)?.game.humanHasDrawn ?? false
    }

    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.load(OldMaidSnapshot.self, for: id).map { !$0.game.humanHasDrawn } ?? false
    }

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OldMaidView(services: services))
    }
}
