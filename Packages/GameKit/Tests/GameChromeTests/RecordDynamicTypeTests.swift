import Foundation
import Testing
import GameKitTestSupport

/// 記録行・バッジ・行き止まりパネル・「⋯」の帯の文字が文字サイズ設定に追従する（#1601）。
///
/// macOS の `ImageRenderer` は `dynamicTypeSize` を `@ScaledMetric` に反映しない（対照の
/// `themeBody` でも高さが変わらない）ので、描画の寸法ではなくソースで固定する。
@Suite("記録行の文字サイズ追従（#1601）")
struct RecordDynamicTypeTests {
    /// 盤・札・絵文字の固定 pt（`.system(size: 52)` など）は対象外なので、直した文字だけを名指しする。
    @Test("記録・バッジ・見出し・帯の説明文が固定 pt に戻っていない",
          arguments: [
              ("RecordLabel", ".system(size: 13"), ("RecordLabel", ".system(size: 12, weight: .bold, design"),
              ("RecordLabel", ".system(size: 10"),
              ("GameDeadEndPanel", ".system(size: 20"), ("GameOverflowBar", ".system(size: 12"),
              ("GameActionRow", ".system(size: 14"), ("GameActionRow", ".system(size: 10"),
          ])
    func noFixedPointFont(file: String, fixed: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/\(file).swift"))
        #expect(!source.contains(fixed), "\(file) に固定 pt のフォント（\(fixed)）が戻っている")
        #expect(source.contains(".themeCaption(") || source.contains(".themeBody("), "\(file) がテーマフォントを通っていない")
    }
}
