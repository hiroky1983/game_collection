import SwiftUI
import Core

public struct ConcentrationModule: GameModule {
    public let id = "concentration"
    public let title = "神経衰弱"
    public let description = "記憶力勝負！CPU と対戦しよう"
    public var icon: Image { Image(systemName: "brain.head.profile") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ConcentrationView(services: services))
    }
}
