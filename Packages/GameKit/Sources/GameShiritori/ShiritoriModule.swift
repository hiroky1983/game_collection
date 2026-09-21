import SwiftUI
import Core

public struct ShiritoriModule: GameModule {
    // 文字列リテラルで書く（LP の顔ぶれ照合 `Scripts/check-lp-game-list.sh` が静的に読むため）。
    public let id = "shiritori"
    public let title = "カードしりとり"
    public let description = "絵札でしりとり。CPUより多く取ろう"
    public var icon: Image { Image(systemName: "textformat.abc") }
    // 中断データは持たない（1 局が短く、時間制のため戻っても続きにならない）。中断のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ShiritoriView(services: services))
    }
}
