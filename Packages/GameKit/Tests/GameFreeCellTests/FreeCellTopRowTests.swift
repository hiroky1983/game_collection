import Testing
import Foundation
import CoreGraphics
import GameKitTestSupport
@testable import GameFreeCell

/// 上段（フリーセル 4 枠 + 組札 4 枠）の幅（会長QA #595 の項目9）。
///
/// 上段は下段の 8 列と幅がぴったり揃う設計（`FreeCellMetrics.boardWidth` = 8 枠 + 隙間 7 つ）で、
/// 余りが 1pt も無い。そこへ `Spacer` を 1 つ挟むと `HStack` の子が 9 個になり、**隙間が
/// 8 つぶん**取られて上段だけが盤の幅を +4pt はみ出す。はみ出した分は中央寄せで左右 2pt ずつ
/// 切り落とされ、**左端の枠の左辺と右端の枠の右辺の破線が丸ごと消える**
/// （実測: 角の円弧だけが端に残り、直線部分は 1px も描かれない）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**寸法の算術**と**ソース**の
/// 2 方向から固定する（`FreeCellDragLocationTests` と同じ形）。
@Suite("フリーセルの上段の幅")
struct FreeCellTopRowTests {

    typealias Metrics = FreeCellMetrics

    /// 画面幅から盤の左右の余白（`boardSideInset` 4pt）を引いた、盤に使える幅。
    private static func contentWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - Metrics.boardSideInset * 2
    }

    @Test("8 枠 + 隙間 7 つが盤の幅と一致する（余りが無い）",
          arguments: [CGFloat(375), 393, 402, 430, 440])
    func eightSlotsExactlyFillTheBoardWidth(_ screenWidth: CGFloat) {
        let available = Self.contentWidth(screenWidth: screenWidth)
        let card = Metrics.cardWidth(availableWidth: available)
        let row = card * 8 + Metrics.columnGap * 7
        #expect(row == Metrics.boardWidth(cardWidth: card))
        #expect(row <= available, "上段が使える幅をはみ出している（\(row)pt > \(available)pt）")
    }

    @Test("隙間が 1 つ増えると盤の幅をはみ出す（Spacer を挟めない根拠）")
    func oneExtraGapOverflowsTheBoardWidth() {
        let available = Self.contentWidth(screenWidth: 402)
        let card = Metrics.cardWidth(availableWidth: available)
        let board = Metrics.boardWidth(cardWidth: card)
        // 子が 9 個（8 枠 + Spacer）になると HStack の隙間が 7 → 8 に増える。
        let withSpacer = card * 8 + Metrics.columnGap * 8
        #expect(withSpacer > board)
        #expect(withSpacer - board == Metrics.columnGap, "はみ出しは隙間 1 つぶん = \(Metrics.columnGap)pt")
        // 中央寄せなので左右に半分ずつ切り落とされ、破線（1.5pt）が丸ごと消える幅になる。
        // 列の間隔を 3pt に詰めてからは、切り落とし（1.5pt）が破線の太さとちょうど同じになる。
        #expect((withSpacer - board) / 2 >= 1.5)
    }

    @Test("上段に Spacer を置いていない")
    func topRowHasNoSpacer() throws {
        let source = try Self.viewSource()
        let block = try #require(SourceScan.declaration(of: "private func topRow", in: source))
        #expect(
            !SourceScan.strippingComments(block).contains("Spacer("),
            "上段に Spacer が戻っている。隙間が 1 つ増えて左右の枠の破線が切れる"
        )
        // 取り違え防止: 上段そのものを取れていることを確かめる。
        #expect(block.contains("foundationView"), "topRow の宣言を取れていない")
        #expect(block.contains("cellView"), "topRow の宣言を取れていない")
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        try SourceScan.moduleSources("GameFreeCell")
    }
}
