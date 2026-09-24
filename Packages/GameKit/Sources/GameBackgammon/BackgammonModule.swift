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
    public let title = "バックギャモン"
    public let description = "サイコロで駒を進めて先にあがれ！CPU と対戦"
    public var icon: Image { Image(systemName: "dice.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(BackgammonView(services: services))
    }
}
