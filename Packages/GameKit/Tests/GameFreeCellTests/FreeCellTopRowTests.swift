import Testing
import Foundation
import CoreGraphics
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

    /// 画面幅から `Theme.pad`（16pt）を左右に引いた、盤に使える幅。
    private static func contentWidth(screenWidth: CGFloat) -> CGFloat { screenWidth - 16 * 2 }

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
        #expect((withSpacer - board) / 2 > 1.5)
    }

    @Test("上段に Spacer を置いていない")
    func topRowHasNoSpacer() throws {
        let source = try Self.viewSource()
        let block = try #require(Self.declaration(of: "private func topRow", in: source))
        #expect(
            !Self.strippingComments(block).contains("Spacer("),
            "上段に Spacer が戻っている。隙間が 1 つ増えて左右の枠の破線が切れる"
        )
        // 取り違え防止: 上段そのものを取れていることを確かめる。
        #expect(block.contains("foundationView"), "topRow の宣言を取れていない")
        #expect(block.contains("cellView"), "topRow の宣言を取れていない")
    }

    // MARK: - ヘルパー（`FreeCellDragLocationTests` と同じもの）

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameFreeCellTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameFreeCell/FreeCellView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `header` で始まる宣言の本体（対応する閉じ括弧まで）を取り出す。
    private static func declaration(of header: String, in source: String) -> String? {
        guard let start = source.range(of: header) else { return nil }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// 行コメント（`//` 以降）を落とす。禁じ手を説明した注記まで「使っている」と数えないため。
    private static func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            if let slashes = line.range(of: "//") { return line[line.startIndex..<slashes.lowerBound] }
            return line[...]
        }.joined(separator: "\n")
    }
}
