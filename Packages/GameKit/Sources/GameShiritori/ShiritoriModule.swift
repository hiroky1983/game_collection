import SwiftUI
import Core

public struct ShiritoriModule: GameModule {
    // 文字列リテラルで書く（LP の顔ぶれ照合 `Scripts/check-lp-game-list.sh` が静的に読むため）。
    public let id = "shiritori"
    public let title = "カードしりとり"
    public let description = "絵札でしりとり。CPUと取り合おう"
    // "textformat.abc" は横長で、他ゲームと同じ正方形のアイコンチップ（44×44pt・HubView.swift）
    // からはみ出ていた（会長指摘・2026-09-22）。しりとり＝言葉をつなぐ遊びなので "link" に差し替える。
    public var icon: Image { Image(systemName: "link") }
    // 中断データは持たない（1 局が短く、時間制のため戻っても続きにならない）。中断のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ShiritoriView(services: services))
    }
}
