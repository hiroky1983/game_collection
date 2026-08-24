import SwiftUI
import Core

public struct SudokuModule: GameModule {
    public let id = "sudoku"
    public let title = "数独"
    public let description = "9×9のマスに1〜9を埋めよう"
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }
    public init() {}
    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(SudokuView(services: services))
    }
}
