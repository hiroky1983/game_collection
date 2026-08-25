import SwiftUI
import Core

public struct MahjongModule: GameModule {
    /// 麻雀ソリティア（#90）が既に `"mahjong"` を使っているので別の ID にする。
    /// この ID は中断スナップショットのファイル名・自己ベスト・解析イベントのキーを兼ねるため、
    /// 一度出したら変えられない（変えると過去の記録と結びつかなくなる）。
    public let id = "mahjong4"
    public let title = "麻雀"
    public let description = "CPU3人と東風戦。立直・鳴きあり！"
    /// 並んだ牌に見える記号。将棋が `square.grid.3x3.fill` を使っているので同じ形は避ける
    /// （ハブのカードはアイコンで見分けるため、被ると別のゲームに見える）。
    public var icon: Image { Image(systemName: "rectangle.3.group.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(MahjongView(services: services))
    }
}
