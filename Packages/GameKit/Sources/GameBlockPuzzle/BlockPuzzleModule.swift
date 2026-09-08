import SwiftUI
import Core

/// ブロックならべ（#493）の `GameModule` 登録口。
///
/// 表示名は権利チェック（Issue #493・2026-09-08）で「ブロックならべ」を採用した。
/// ジャンル語の「ブロックパズル」は説明文で使ってよい。「テトリス/Tetris」および
/// 既存タイトル名（1010! / Blockudoku / Block Blast）は名称・配色・形状セットとも使わない。
public struct BlockPuzzleModule: GameModule {
    public let id = "blockpuzzle"
    public let title = "ブロックならべ"
    public let description = "ピースを置いて行と列をそろえよう"
    public var icon: Image { Image(systemName: "puzzlepiece.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(BlockPuzzleView(services: services))
    }
}
