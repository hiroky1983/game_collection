import SwiftUI
import Core

public struct MinesweeperModule: GameModule {
    public let id = "minesweeper"
    public var title: String { tr("マインスイーパー") }
    public var description: String { tr("地雷を避けながら全マスを開けよう") }
    public var icon: Image { Image(systemName: "flag.fill") }
    public init() {}
    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(MinesweeperView(services: services))
    }
}
