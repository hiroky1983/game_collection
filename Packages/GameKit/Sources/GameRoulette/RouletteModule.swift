import SwiftUI
import Core

/// ルーレット（#1318）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
public struct RouletteModule: GameModule {
    public let id = "roulette"
    public let title = "ルーレット"
    public let description = "数字や色にチップを賭けて、ホイールの出目を当てよう"
    public var icon: Image { Image(systemName: "circle.circle.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(RouletteView(services: services))
    }
}
