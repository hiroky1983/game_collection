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
}
