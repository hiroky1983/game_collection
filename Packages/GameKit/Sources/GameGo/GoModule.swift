import SwiftUI
import Core

public struct GoModule: GameModule {
    public let id = "go"
    public let title = "囲碁"
    public let description = "9路盤で CPU と対局。ルールも読める"
    // 碁石 2 つに見える記号を選ぶ。格子系のアイコンは将棋・ナンプレ・五目並べと
    // ハブ上で見分けが付かない。
    public var icon: Image { Image(systemName: "circlebadge.2.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(GoView(services: services))
    }
}
