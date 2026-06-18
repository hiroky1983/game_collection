import SwiftUI
import Core

public struct OthelloModule: GameModule {
    public let id = "othello"
    public let title = "オセロ"
    public let description = "石を挟んでひっくり返せ！CPU に挑戦"
    public var icon: Image { Image(systemName: "circle.lefthalf.filled") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OthelloView(services: services))
    }
}
