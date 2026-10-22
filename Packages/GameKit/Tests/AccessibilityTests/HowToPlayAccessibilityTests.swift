import Testing
import GameKitTestSupport

/// 遊び方・ルール・役一覧の共通部品の VoiceOver（#2641）。
///
/// 項目名が見出しとして読まれること、手順の番号の丸が単独のフォーカスにならないことを、
/// `ButtonAccessibilityScanTests`（#2529）と同じくソースで縛る。
struct HowToPlayAccessibilityTests {

    private static func source() throws -> String {
        SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HowToPlay.swift"))
    }

    /// `Text(<引数>)` の行から次の `Text(` までの間に `.accessibilityAddTraits(.isHeader)` があるか。
    private static func isHeader(_ argument: String, in source: String) throws -> Bool {
        let head = "Text(\(argument))"
        let range = try #require(source.range(of: head), "\(head) が見つからない")
        let rest = source[range.upperBound...]
        let end = rest.range(of: "Text(")?.lowerBound ?? rest.endIndex
        return rest[..<end].contains(".accessibilityAddTraits(.isHeader)")
    }

    @Test("ルール一覧の項目名・図カードの見出し・役一覧の見出しは見出しとして読まれる")
    func headingsAreHeaders() throws {
        let source = try Self.source()
        #expect(try Self.isHeader("rule.0", in: source))
        #expect(try Self.isHeader("title", in: source))
        #expect(try Self.isHeader("header", in: source))
    }

    @Test("番号の丸は読み上げから外れる")
    func numberBadgeIsHidden() throws {
        let source = try Self.source()
        let badge = try #require(SourceScan.declaration(of: "private struct HowToPlayNumberBadge", in: source))
        #expect(badge.contains(".accessibilityHidden(true)"))
    }
}
