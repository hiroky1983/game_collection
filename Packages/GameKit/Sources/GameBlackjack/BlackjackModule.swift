import SwiftUI
import Core

public struct BlackjackModule: GameModule {
    public let id = "blackjack"
    public let title = "ブラックジャック"
    public let description = "ディーラーに勝てるか。チップを稼ごう！"
    public var icon: Image { Image(systemName: "suit.club.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(BlackjackView(services: services))
    }
}
