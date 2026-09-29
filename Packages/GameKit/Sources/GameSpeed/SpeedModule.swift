import SwiftUI
import Core

/// スピード（#1323）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// 表示名「スピード」は伝統的なトランプゲームの一般名称で、文字商標の登録は無い
/// （patent-i.com の公報データで「スピード」「SPEED」「スピードトランプ」いずれも 0 件。
/// 対照のテトリス 5 件・オセロ 7 件。Issue #1323 の権利チェック）。
public struct SpeedModule: GameModule {
    // **文字列リテラルで書く**（`SpeedModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `SpeedModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "speed"
    public let title = "スピード"
    public let description = "台札と1つ違いの札を、CPU より先に出し切ろう。速さは3段階"
    public var icon: Image { Image(systemName: "hare.fill") }
    /// 中断データは最後に選んだ速さの控えで、ゲームそのものは復元しない（同時進行の駆け引きで
    /// 成り立つゲームなので途中から戻せない）。「途中のままです」のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(SpeedView(services: services))
    }
}
