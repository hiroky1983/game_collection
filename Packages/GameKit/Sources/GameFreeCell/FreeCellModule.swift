import SwiftUI
import Core

public struct FreeCellModule: GameModule {
    public let id = "freecell"
    public let title = "フリーセル"
    public let description = "全部見える52枚。詰まない配札を読み切ろう"
    // 4 つのフリーセルに札を1枚ずつ置く形。ソリティアの「重ねた札」
    // （rectangle.portrait.on.rectangle.portrait.fill）と並んでも見分けが付く、
    // 「枠が並んでいる」印にする。
    public var icon: Image { Image(systemName: "rectangle.grid.1x2.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(FreeCellView(services: services))
    }
}
