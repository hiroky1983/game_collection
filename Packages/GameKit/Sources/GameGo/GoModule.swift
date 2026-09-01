import SwiftUI
import Core

public struct GoModule: GameModule {
    public let id = "go"
    public let title = "囲碁"
    public let description = "9路盤で CPU と対局。ルールも読める"
    public var icon: Image { Image(systemName: "circle.circle.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GoView(services: services))
    }
}
