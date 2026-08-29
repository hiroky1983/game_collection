import SwiftUI
import Core

public struct SudokuModule: GameModule {
    public let id = "sudoku"
    // 表示名は「ナンプレ」。「数独／SUDOKU」は株式会社ニコリの登録商標（日本）のため
    // ユーザーに見える場所では使わない（会長決裁 2026-08-30・リバーシ 5.2.1 の再発防止）。
    // 内部 ID（"sudoku"）は非表示の識別子なので据え置く。
    public let title = "ナンプレ"
    public let description = "9×9のマスに1〜9を埋めよう"
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }
    public init() {}
    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(SudokuView(services: services))
    }
}
