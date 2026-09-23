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
    public let title = "いろリレー"
    public let description = "色か数字をつないで手札を出し切ろう。CPU3人と対戦"
    public var icon: Image { Image(systemName: "rectangle.on.rectangle.angled") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ColorRelayView(services: services))
    }
}
