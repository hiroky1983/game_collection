import Core
import SwiftUI

/// チャリンコおじさんの `GameModule` 登録口（#494）。
///
/// アクション枠（SpriteKit）の 2 本目。表示名・ID とも権利チェック（Issue #494 の記録）の
/// 結論に従い、既存タイトル名（`チャリ走`・Spicysoft）を避けてオリジナルの
/// 「チャリンコおじさん」、ID / LP の slug はジャンルの普通名詞 `runner` にしている。
public struct RunnerModule: GameModule {
    // **文字列リテラルで書く**（`RunnerModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため、
    // 定数参照にすると slug を突き合わせられずに CI が落ちる。
    // `RunnerModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "runner"
    public let title = "チャリンコおじさん"
    public let description = "タップで跳んで15ステージを走りぬけよう"
    // 自転車の絵。ハブで隣に並ぶブロック崩し（`tennisball.fill`）とも見分けが付く。
    public var icon: Image { Image(systemName: "bicycle") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(RunnerView(services: services))
    }
}
