import SwiftUI
import Core

public struct SpiderModule: GameModule {
    public let id = "spider"
    public let title = "スパイダーソリティア"
    public let description = "2組104枚を同じスートでK→Aに。1・2・4スートの3難度"
    // 2 組の札を重ねた印。ソリティア（rectangle.stack.fill）・フリーセル（rectangle.grid.1x2.fill）と
    // 並んでも見分けが付くよう、傾けて重ねた 2 枚にする。
    public var icon: Image { Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(SpiderView(services: services))
    }
}
