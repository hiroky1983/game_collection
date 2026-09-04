import Core
import SwiftUI

/// ブロック崩しの `GameModule` 登録口（#463）。
///
/// アクション枠（SpriteKit）の 1 本目。表示名は日本語の一般名称「ブロック崩し」で、
/// ID・LP の slug には元祖アーケード作品の商標（Atari の `Breakout`）を避けて
/// 普通名詞の `blocks` を使う（権利チェックの記録は Issue #463 と
/// `docs/aso/metadata-v1.1.1.md` §3）。
public struct BlocksModule: GameModule {
    public let id = BlocksModel.gameID
    public let title = "ブロック崩し"
    public let description = "パドルではね返して全部くずそう"
    // 球の絵にしてある。ブロックを模した格子（`rectangle.grid.2x2.fill` 等）は、
    // ハブで隣に並ぶ 2048（`square.grid.2x2`）と見分けが付かなかった（実機確認で判明）。
    public var icon: Image { Image(systemName: "tennisball.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(BlocksView(services: services))
    }
}
