import Testing
import Foundation
import GameKitTestSupport

/// 開始シート・設定シートの「くわしい説明」開閉行が共通部品を使い続けることを縛る（#3506）。
///
/// 4 か所に `Label` + `lineLimit(1)` の同じ行がコピーされ、大きい文字で末尾が切れていた。
/// 共通部品（折り返し可・44pt 以上・開閉状態の読み上げ内蔵）以外の開閉行が増えるのを止める。
struct SetupDetailsToggleRowScanTests {

    static let modules = ["GameRunner", "GameMahjong", "GameShiritori", "GameOjisanPuzzle"]

    @Test(arguments: modules)
    func detailsToggleUsesSharedRow(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        let toggle = try #require(SourceScan.declaration(of: "private var detailsToggle: some View", in: source))
        #expect(toggle.contains("SetupDetailsToggleRow("), "\(module) の detailsToggle が共通部品を使っていません")
        #expect(!toggle.contains("lineLimit(1)"), "\(module) の開閉行が 1 行固定に戻っています")
    }

    @Test func sharedRowWrapsAndKeepsTapTargetAndState() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/SetupDetailsToggleRow.swift"))
        #expect(!source.contains("lineLimit("))
        #expect(!source.contains("minimumScaleFactor"))
        #expect(source.contains("minHeight: GameButtonMetrics.minTapTarget"))
        #expect(source.contains(".accessibilityValue("))
    }
}
