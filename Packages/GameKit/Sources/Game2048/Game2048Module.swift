import SwiftUI
import Core

/// 2048 の `GameModule` 登録口。M2 で中身（ロジック・Model・操作）を実装する。
public struct Game2048Module: GameModule {
    public let id = "2048"
    public let title = "2048"
    public var icon: Image { Image(systemName: "square.grid.2x2") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(Game2048View(services: services))
    }
}
