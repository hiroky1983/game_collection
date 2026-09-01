import SwiftUI
import Core

public struct SolitaireModule: GameModule {
    public let id = "solitaire"
    public let title = "ソリティア"
    public let description = "クロンダイク。52枚を組札に積み上げよう"
    // 重ねた札。スート記号（♠ はポーカー・♣ はブラックジャックが既に使用）は避けつつ、
    // 麻雀ソリティアの「層」（square.stack.3d.up.fill）とも見分けが付く、縦長 = 札の形にする。
    public var icon: Image { Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(SolitaireView(services: services))
    }
}
