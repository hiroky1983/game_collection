import SwiftUI
import Core

public struct DaifugoModule: GameModule {
    public let id = "daifugo"
    public var title: String { daifugoGameName() }
    public var description: String { tr("CPU3人と対戦。革命・8切りあり！") }
    public var icon: Image { Image(systemName: "crown.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(DaifugoView(services: services))
    }
}
