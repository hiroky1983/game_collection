import SwiftUI
import Core

public struct SudokuModule: GameModule {
    public let id = "sudoku"
    public let title = "数独"
    public let description = "9×9グリッドを数字で埋めよう！3段階の難易度"
    public var icon: Image { Image(systemName: "puzzlepiece.extension.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(SudokuView(services: services))
    }
}
