import Testing
import Foundation
import GameKitTestSupport

/// モーダル（シート）は縦長（`.large`）固定にする（#2096。会長指摘: 「？」の遊び方が半分の高さで開いた）。
///
/// `.presentationDetents(` の引数は `[.large]` だけを通す。`.medium`・`.fraction`・`.height`、変数経由の指定は
/// 例外を作らず失敗させる（どうしても必要なときは会長決裁を取り、`allowed` に理由付きで足す）。
/// detent を指定しない `.sheet` / `.fullScreenCover` は既定で large なので対象外。
/// `.presentationCompactAdaptation` は iPhone でシートを別の見せ方に替えうるので、これも使わせない。
struct ModalDetentScanTests {

    /// 例外の許可リスト（ファイルの末尾パス）。空のまま保つ。
    private static let allowed: [String] = []

    private static func scannedSources() throws -> [(path: String, source: String)] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, String)] = []
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                result.append((file.path, SourceScan.strippingComments(try String(contentsOf: file, encoding: .utf8))))
            }
        }
        #expect(result.count > 100, "走査対象が見つからない（パスの導出が壊れている可能性）")
        return result
    }

    /// `presentationDetents(` の引数（対応する閉じ括弧までの文字列）を全て返す。
    static func detentArguments(in source: String) -> [String] {
        var arguments: [String] = []
        var searchStart = source.startIndex
        while let range = source.range(of: "presentationDetents(", range: searchStart..<source.endIndex) {
            var depth = 1
            var index = range.upperBound
            while index < source.endIndex, depth > 0 {
                if source[index] == "(" { depth += 1 } else if source[index] == ")" { depth -= 1 }
                if depth > 0 { index = source.index(after: index) }
            }
            arguments.append(String(source[range.upperBound..<index]).filter { !$0.isWhitespace })
            searchStart = range.upperBound
        }
        return arguments
    }

    @Test("presentationDetents は [.large] だけ")
    func detentsAreLargeOnly() throws {
        var total = 0
        for (path, source) in try Self.scannedSources() where !Self.allowed.contains(where: path.hasSuffix) {
            for argument in Self.detentArguments(in: source) {
                total += 1
                #expect(argument == "[.large]", "\(path) の presentationDetents が [.large] 以外: \(argument)")
            }
        }
        #expect(total >= 5, "presentationDetents が見つからない（走査が空振りしている）")
    }

    @Test("presentationCompactAdaptation を使わない")
    func noCompactAdaptation() throws {
        for (path, source) in try Self.scannedSources() {
            #expect(!source.contains("presentationCompactAdaptation"), "\(path) が presentationCompactAdaptation を使っている")
        }
    }

    @Test("遊び方シートは large 固定")
    func howToPlayIsLarge() throws {
        let source = try SourceScan.packageSource("Sources/Core/HowToPlay.swift")
        #expect(Self.detentArguments(in: source) == ["[.large]"])
    }

    @Test("検出器が medium・fraction・height・変数を拾う")
    func detectorSelfCheck() {
        let sample = """
        a.presentationDetents([.medium, .large])
        b.presentationDetents([.height(300), .large])
        c.presentationDetents(cond ? [.large] : [.fraction(0.5)])
        d.presentationDetents([.large])
        """
        #expect(Self.detentArguments(in: sample)
            == ["[.medium,.large]", "[.height(300),.large]", "cond?[.large]:[.fraction(0.5)]", "[.large]"])
    }
}
