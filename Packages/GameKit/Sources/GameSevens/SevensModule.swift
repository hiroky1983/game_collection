import SwiftUI
import Core

public struct SevensModule: GameModule {
    public let id = "sevens"
    public let title = "七並べ"
    public let description = "CPU3人と対戦。7から並べて早上がり！"
    public var icon: Image { Image(systemName: "7.square.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(SevensView(services: services))
    }
}
