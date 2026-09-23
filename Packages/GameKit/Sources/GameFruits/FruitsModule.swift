import Core
import SwiftUI

/// くっつきフルーツ（#1319）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct FruitsModule: GameModule {
    // **文字列リテラルで書く**（`FruitsModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `FruitsModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "fruits"
    public let title = "くっつきフルーツ"
    public let description = "同じくだものをくっつけて、大きく育てよう"
    public var icon: Image { Image(systemName: "leaf.circle.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(FruitsView(services: services))
    }
}
