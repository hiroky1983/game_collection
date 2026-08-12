import SwiftUI
import Core

public struct MahjongSolitaireModule: GameModule {
    public let id = "mahjong"
    public let title = "麻雀ソリティア"
    public let description = "同じ牌を2枚ずつ取って全部消そう"
    public var icon: Image { Image(systemName: "square.stack.3d.up.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(MahjongSolitaireView(services: services))
    }
}
