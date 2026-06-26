import SwiftUI
import Core

public struct PokerModule: GameModule {
    public let id = "poker"
    public let title = "ポーカー"
    public let description = "5カードドロー。チップを稼ごう！"
    public var icon: Image { Image(systemName: "suit.spade.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(PokerView(services: services))
    }
}
