import Testing
import CoreGraphics
import Foundation
@testable import GameSudoku

/// タップ標的（#262 の受け入れ条件「数字パッド・グリッドセルとも 44pt 以上」）を、
/// シミュレータを立てずに実寸で検証する（麻雀ソリティア #196/#197・マインスイーパー #203 と同じやり方）。
///
/// 対応 OS は iOS 17 以上なので、いちばん狭い実機は **iPhone SE 第2/第3世代（375pt 幅）**。
@Suite("数独の寸法")
struct SudokuMetricsTests {

    typealias Metrics = SudokuMetrics

    /// 画面幅から `Theme.pad`（16pt）を左右に引いた、コンテンツに使える幅。
    private static func contentWidth(screenWidth: CGFloat) -> CGFloat { screenWidth - 16 * 2 }

    static let iPhoneSE: CGFloat = 375
    static let iPhone17Pro: CGFloat = 402

    // MARK: - 数字パッド

    @Test("数字パッドのボタンは、いちばん狭い実機でも 44pt 以上",
          arguments: [iPhoneSE, iPhone17Pro])
    func padButtonsMeetTapTarget(_ screenWidth: CGFloat) {
        // 5 列 + 列間 6pt × 4。
        let width = (Self.contentWidth(screenWidth: screenWidth) - 6 * CGFloat(Metrics.padColumns - 1))
            / CGFloat(Metrics.padColumns)
        #expect(width >= Metrics.minimumTapTarget, "幅 \(width)pt")
        #expect(Metrics.padButtonMinSide >= Metrics.minimumTapTarget, "高さは定数で下限を張っている")
    }

    @Test("1〜9 と消しゴムを 1 段に並べると 44pt を割る（2 段に割っている根拠）")
    func tenButtonsInOneRowWouldBeTooSmall() {
        let width = (Self.contentWidth(screenWidth: Self.iPhoneSE) - 6 * 9) / 10
        #expect(width < Metrics.minimumTapTarget, "1段だと \(width)pt しかない")
    }

    // MARK: - 盤のマス

    @Test("9 列 × 44pt は、いちばん広い対象実機の幅にも入らない（拡大モードが要る根拠）")
    func nineColumnsCannotFitAt44pt() {
        let required = Metrics.minimumTapTarget * CGFloat(SudokuEngine.size)   // 396pt
        #expect(required > Self.contentWidth(screenWidth: Self.iPhoneSE))
        #expect(required > Self.contentWidth(screenWidth: Self.iPhone17Pro))
    }

    @Test("拡大モードのマスは 44pt 以上")
    func zoomedCellMeetsTapTarget() {
        #expect(Metrics.zoomedCellSide >= Metrics.minimumTapTarget)
    }

    @Test("等倍表示のマスは、いちばん狭い実機でも 38pt 以上ある")
    func fittedCellStaysUsable() {
        // 44pt には届かないが（上のテスト）、9×9 を一望できることを優先した既定表示。
        let side = Self.contentWidth(screenWidth: Self.iPhoneSE) / CGFloat(SudokuEngine.size)
        #expect(side >= 38, "等倍のマスは \(side)pt")
    }

    // MARK: - View との結線
    //
    // 定数だけ見ても意味が無い。View が **この定数を** frame に渡していなければ、
    // ここを 44 のままにして View 側だけ小さくする改変を素通ししてしまう。
    // SwiftUI を実際に描いて測る仕組みがこのパッケージには無いので、結線をソースで固定する。

    @Test("View がタップ標的の定数を実際に使っている")
    func viewIsWiredToMetrics() throws {
        let source = try Self.viewSource()
        for expected in [
            #"minHeight:\s*SudokuMetrics\.padButtonMinSide"#,
            #"minWidth:\s*SudokuMetrics\.padButtonMinSide"#,
            #"cellSide:\s*SudokuMetrics\.zoomedCellSide"#,
            #"\.padding\(\.vertical,\s*SudokuMetrics\.statusBarVerticalPadding\)"#,
        ] {
            #expect(
                source.range(of: expected, options: .regularExpression) != nil,
                "SudokuView が \(expected) を使っていない（タップ標的が Metrics から切れている）"
            )
        }
    }

    @Test("盤の演出は Core の Reduce Motion 追従レイヤー経由で書かれている")
    func animationsGoThroughGameAnimation() throws {
        let source = try Self.viewSource()
        #expect(source.contains(".gameAnimation("), "gameAnimation を使っていない")
        // `.animation(` の生使用は Reduce Motion を無視するので置かない（#210）。
        #expect(
            source.range(of: #"[^e]\.animation\("#, options: .regularExpression) == nil,
            "SwiftUI の .animation( を直接使っている（#210 の共通レイヤーを迂回している）"
        )
    }

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameSudokuTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameSudoku/SudokuView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
