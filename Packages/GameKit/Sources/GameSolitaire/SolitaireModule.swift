import SwiftUI
import Core

public struct SolitaireModule: GameModule {
    public let id = "solitaire"
    public let title = "ソリティア"
    public let description = "クロンダイク。52枚を組札に積み上げよう"
    // 重ねた札。スート記号（♠ はポーカー・♣ はブラックジャックが既に使用）は避け、
    // 「札を積み上げる」というこのゲームの中身が出る形にする。
    public var icon: Image { Image(systemName: "rectangle.stack.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(SolitaireView(services: services))
    }
}
