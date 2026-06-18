import SwiftUI
import Core

public struct GomokuModule: GameModule {
    public let id = "gomoku"
    public let title = "五目並べ"
    public let description = "先に5つ並べた方が勝ち！CPU に挑戦"
    public var icon: Image { Image(systemName: "circle.grid.3x3.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GomokuView(services: services))
    }
}
