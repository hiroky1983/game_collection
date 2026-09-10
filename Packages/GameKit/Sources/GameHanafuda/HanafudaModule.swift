import Core
import SwiftUI

/// 花札こいこいの `GameModule` 登録口（#495）。
///
/// 表示名・ID は権利チェック（Issue #495 の記録）の結論に従う。`花札` `こいこい` とも
/// ゲーム区分の商標は確認できなかったため通称をそのまま採るが、**「花札オンライン」型の
/// 名称だけは避ける**（そらいろ㈱ 登録5903259 が「花札 ONLINE」の組合せ商標を第9類で保有）。
public struct HanafudaModule: GameModule {
    // **文字列リテラルで書く**（`HanafudaModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため、
    // 定数参照にすると slug を突き合わせられずに CI が落ちる。
    // `HanafudaModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "hanafuda"
    public let title = "花札こいこい"
    public let description = "CPUと役を競う。こいこいで倍を狙おう"
    // 和風の看板。ハブに並ぶ他ゲームに草花のアイコンは無く、ひと目で見分けられる。
    public var icon: Image { Image(systemName: "leaf.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(HanafudaView(services: services))
    }
}
