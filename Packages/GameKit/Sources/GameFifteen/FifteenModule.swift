import SwiftUI
import Core

/// 15 パズルの `GameModule` 登録口。
public struct FifteenModule: GameModule {
    public let id = "fifteen"
    public let title = "15パズル"
    public let description = "タイルをスライドして1から15まで並べよう"
    public var icon: Image { Image(systemName: "square.grid.4x3.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(FifteenView(services: services))
    }
}
