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

    /// 一度もピースを置いていない盤は「続き」ではない（#1912）。配った直後は盤が空・手元 3 つ・得点 0 で、
    /// 1 つ置けば手元に空きができ盤にも得点にも跡が付く。壊れたデータは新規開始に倒れるので続きと言わない。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(BlockPuzzleSnapshot.self, for: id), snap.validated() != nil else { return false }
        let untouched = snap.score == 0 && snap.combo == 0
            && snap.hand.allSatisfy { $0 != nil }
            && snap.board.allSatisfy { row in row.allSatisfy { $0 == 0 } }
        return !untouched
    }
}
