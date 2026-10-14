import SwiftUI
import Core

/// ハーツ（Issue #1884）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct HeartsModule: GameModule {
    // **文字列リテラルで書く**（`HeartsModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `HeartsModel.gameID` との一致は `HeartsModuleTests` が機械的に確かめる。
    public let id = "hearts"
    public var title: String { tr("ハーツ") }
    public var description: String { tr("ハートとスペードのQを取らないように札を出そう。CPU3人と対戦") }
    public var icon: Image { Image(systemName: "suit.heart.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(HeartsView(services: services))
    }
}
