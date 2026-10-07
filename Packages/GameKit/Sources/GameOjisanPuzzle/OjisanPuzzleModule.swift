import Core
import SwiftUI

/// 腰痛おじさんパズル（#1016・v1.1.11 で公開 #1904）の `GameModule` 登録口。
///
/// ハブへの登録は `App/AppGameServices.swift` の `registry` の 1 行（倉庫へ戻すときはそこをコメントアウトする）。
/// 解析と記録は `OjisanPuzzleModel` からつないである。Game Center・広告・中断復元にはまだつないでいない。
public struct OjisanPuzzleModule: GameModule {
    // **文字列リテラルで書く**（`OjisanPuzzleModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    public let id = "ojisanpuzzle"
    public let title = "腰痛おじさんパズル"
    public let description = "荷物を4つそろえて腰をいたわろう"
    public var icon: Image { Image(systemName: "shippingbox.fill") }
    // 中断データを持たないので、中断のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(OjisanPuzzleView(services: services))
    }
}
