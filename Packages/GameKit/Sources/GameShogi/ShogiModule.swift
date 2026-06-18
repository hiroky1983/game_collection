import SwiftUI
import Core

/// 将棋の `GameModule` 登録口。
public struct ShogiModule: GameModule {
    public let id = "shogi"
    public let title = "将棋"
    public let description = "CPU と本格的な将棋で対決しよう"
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ShogiView(services: services))
    }
}
