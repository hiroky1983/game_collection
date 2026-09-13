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
    // ステージ数は #674 で 15 → 18 に増えた（乗れる台座の枠）。ハブの一覧に出る文言なので
    // `RunnerRules.stageCount` と食い違わないようにする（`RunnerModuleTests` が縛る）。
    public let description = "タップで跳んで18ステージを走りぬけよう"
    // おじさんの顔（#700）。18 本のカードで唯一キャラが出る。描けない環境では自転車の記号。
    public var icon: Image { MainActor.assumeIsolated { OjisanBitmap.hubIcon } ?? Image(systemName: "bicycle") }
    // 中断データはステージ番号とベストタイムの控えで、走行は必ずステージの頭から始まる
    // （`RunnerModel.press()` の `gameWillNotResume`）。中断のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(RunnerView(services: services))
    }
}
