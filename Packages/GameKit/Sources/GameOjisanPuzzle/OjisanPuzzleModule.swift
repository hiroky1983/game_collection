import Core
import SwiftUI

/// 腰痛おじさんパズル（プロトタイプ）の `GameModule` 登録口。
///
/// **まだ試作**なので、ハブへの登録は `App/AppGameServices.swift` 側で `#if DEBUG` に閉じてある。
/// 記録・Game Center・広告・解析・中断復元にはつないでいないため、製品版に出すときは
/// 他の 21 本と同じ横断サービスの結線（`gameDidStart` / `gameDidFinish` / スナップショット）が要る。
public struct OjisanPuzzleModule: GameModule {
    // **文字列リテラルで書く**（`OjisanPuzzleModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    public let id = "ojisanpuzzle"
    public let title = "腰痛おじさんパズル"
    public let description = "荷物を4つそろえて腰をいたわろう"
    public var icon: Image { Image(systemName: "shippingbox.fill") }
    // 中断データを持たない試作なので、中断のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OjisanPuzzleView(services: services))
    }
}
