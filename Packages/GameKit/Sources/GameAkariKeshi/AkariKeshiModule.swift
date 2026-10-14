import SwiftUI
import Core

/// 明かり消しパズルの `GameModule` 登録口（#1883・企画倉庫）。
///
/// 一般に「ライツアウト」と呼ばれる遊びだが、その名前は他社の玩具名に当たりうるので使わない（権利チェック・#1883）。
public struct AkariKeshiModule: GameModule {
    // **文字列リテラルで書く**（`AkariKeshiModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `AkariKeshiModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "akarikeshi"
    public var title: String { tr("明かり消しパズル") }
    public var description: String { tr("押したマスと上下左右の明かりが入れ替わる。全部消せばクリア") }
    public var icon: Image { Image(systemName: "lightbulb.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(AkariKeshiView(services: services))
    }
}
