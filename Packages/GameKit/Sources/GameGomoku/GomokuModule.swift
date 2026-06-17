import SwiftUI
import Core

public struct GomokuModule: GameModule {
    public let id = "gomoku"
    public let title = "五目並べ"
    public var icon: Image { Image(systemName: "circle.grid.3x3.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GomokuView(services: services))
    }
}
