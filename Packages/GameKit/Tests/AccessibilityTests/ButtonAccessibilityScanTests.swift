import Testing
import Foundation
import GameKitTestSupport

/// アイコンだけのボタンの VoiceOver 名と、小さいボタンの押せる範囲が新しく欠けるのを止める（#2529）。
///
/// 画面ごとに同じ欠陥が起票され続けた（文字サイズ #1469〜#1850、押せる範囲 #2360）ので、
/// `FixedFontSizeScanTests`（#1858）と同じ型でソースを縛る。例外は**行末の `// a11y-ok: 理由`**。
/// 検出は行ベースの近傍窓（`Button` / `onTapGesture` の行から `window` 行）で見る。
struct ButtonAccessibilityScanTests {

    /// 起点の行から何行先までをそのボタンの近傍とみなすか。
    static let window = 20
    static let minTapTarget = 44.0

    struct Line {
        let location: String
        let text: String
    }

    private static func scannedFiles() throws -> [[Line]] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [[Line]] = []
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                result.append(source.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated().map { Line(location: "\(file.path):\($0.offset + 1)", text: String($0.element)) })
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると「見つからない」が緑になる。
        #expect(result.count > 100)
        return result
    }

    private static func code(_ line: String) -> String { SourceScan.strippingComments(line) }

    private static func isButtonStart(_ line: String) -> Bool {
        SourceScan.matchCount(of: #"\bButton\s*[({]|\.onTapGesture\b"#, in: code(line)) > 0
    }

    private static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    /// 起点行から `window` 行ぶんの近傍。次のボタンの起点の手前、または起点よりインデントが浅い行
    /// （起点を含む括弧の外＝別の要素）の手前で打ち切る。
    private static func neighborhood(_ lines: [Line], at index: Int, window: Int) -> String {
        let base = indent(lines[index].text)
        var end = index + 1
        while end < lines.count, end < index + window, !isButtonStart(lines[end].text),
              lines[end].text.trimmingCharacters(in: .whitespaces).isEmpty || indent(lines[end].text) >= base {
            end += 1
        }
        return lines[index..<end].map { code($0.text) }.joined(separator: "\n")
    }

    // MARK: 判定（文字列入力の純関数）

    /// 近傍にアイコンしか無く、読み上げ名（Text / Label / accessibilityLabel / accessibilityHidden）が無いか。
    static func isUnlabeledIconButton(_ neighborhood: String) -> Bool {
        neighborhood.contains("Image(systemName:")
            && SourceScan.matchCount(of: #"\bText\(|\bLabel\(|accessibilityLabel|accessibilityHidden"#, in: neighborhood) == 0
    }

    /// 近傍に行末の飾りのシェブロンを `Image(systemName:)` で直書きしていて、読み上げから隠していないか（#3053）。
    /// 隠す手当ては `DisclosureChevron`（隠す処理込み）か `accessibilityHidden` / `accessibilityLabel`。
    static func hasUnhiddenChevron(_ neighborhood: String) -> Bool {
        SourceScan.matchCount(of: #"Image\(systemName:\s*"chevron\.(right|down)""#, in: neighborhood) > 0
            && SourceScan.matchCount(of: #"accessibilityHidden|accessibilityLabel"#, in: neighborhood) == 0
    }

    /// 近傍に 44 未満の固定 frame があり、広げる手当て（contentShape / minTapTarget / 44 以上の frame）が無いか。
    static func isSmallTapTarget(_ neighborhood: String) -> Bool {
        let sizes = frameSizes(in: neighborhood)
        guard sizes.contains(where: { $0 < minTapTarget }) else { return false }
        if sizes.contains(where: { $0 >= minTapTarget }) { return false }
        return !neighborhood.contains("contentShape") && !neighborhood.contains("minTapTarget")
    }

    /// 近傍が余白（`.padding(.vertical, N)`・N は 12 以下）で高さを決めていて、下限の手当て
    /// （`minHeight` / `minTapTarget` / `GameButtonStyle`）が無いか。固定 frame が無いので 44pt を割りやすい（#3105）。
    static func isPaddingSizedButton(_ neighborhood: String) -> Bool {
        let pattern = #"\.padding\(\.vertical,\s*([0-9]+(?:\.[0-9]+)?)\)|\.padding\(\.horizontal,\s*[0-9.]+\)\s*\.padding\(\.vertical,\s*([0-9]+(?:\.[0-9]+)?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(neighborhood.startIndex..., in: neighborhood)
        let small = regex.matches(in: neighborhood, range: range).contains { match in
            (1...2).contains { group in
                Range(match.range(at: group), in: neighborhood)
                    .flatMap { Double(neighborhood[$0]) }.map { $0 <= 12 } ?? false
            }
        }
        guard small else { return false }
        return !neighborhood.contains("GameButtonStyle") && !neighborhood.contains("minHeight")
            && !neighborhood.contains("minTapTarget")
    }

    /// `.frame(width: 28, height: 28)` の数値リテラルを集める（`minWidth` などの下限指定は含めない）。
    private static func frameSizes(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"\.frame\(([^)]*)\)"#),
              let number = try? NSRegularExpression(pattern: #"(?<![A-Za-z])(?:width|height):\s*([0-9]+(?:\.[0-9]+)?)\b(?!\s*[*+/-])"#)
        else { return [] }
        var sizes: [Double] = []
        for frame in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let args = Range(frame.range(at: 1), in: text) else { continue }
            let argText = String(text[args])
            for match in number.matches(in: argText, range: NSRange(argText.startIndex..., in: argText)) {
                if let range = Range(match.range(at: 1), in: argText), let value = Double(argText[range]) {
                    sizes.append(value)
                }
            }
        }
        return sizes
    }

    private static func offenders(_ judge: (String) -> Bool) throws -> [String] {
        var found: [String] = []
        for lines in try scannedFiles() {
            for (index, line) in lines.enumerated() where isButtonStart(line.text) {
                guard !line.text.contains("// a11y-ok:") else { continue }
                if judge(neighborhood(lines, at: index, window: window)) {
                    found.append("\(line.location): \(line.text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return found
    }

    // MARK: 本体のソースへの適用

    @Test("アイコンだけのボタンには VoiceOver 用の名前が要る")
    func iconOnlyButtonsHaveAccessibilityName() throws {
        let found = try Self.offenders(Self.isUnlabeledIconButton)
        #expect(found.isEmpty, """
            Image(systemName:) だけのボタンには .accessibilityLabel か Text/Label が要る。\
            意図的に隠すなら行末に // a11y-ok: 理由。\n\(found.joined(separator: "\n"))
            """)
    }

    @Test("ボタン行末の飾りのシェブロンは VoiceOver から隠す")
    func decorativeChevronsAreHidden() throws {
        let found = try Self.offenders(Self.hasUnhiddenChevron)
        #expect(found.isEmpty, """
            ボタン内の chevron は DisclosureChevron で描く（直書きなら .accessibilityHidden(true)）。\
            意図的なら行末に // a11y-ok: 理由。\n\(found.joined(separator: "\n"))
            """)
    }

    @Test("44pt 未満の固定 frame のボタンには押せる範囲を広げる手当てが要る")
    func smallButtonsExtendTapTarget() throws {
        let found = try Self.offenders(Self.isSmallTapTarget)
        #expect(found.isEmpty, """
            44pt 未満の frame のボタンには .contentShape か GameButtonMetrics.minTapTarget が要る。\
            意図的なら行末に // a11y-ok: 理由。\n\(found.joined(separator: "\n"))
            """)
    }

    @Test("余白で高さが決まる 44pt 未満のボタンは GameButtonStyle か minHeight に寄せる")
    func paddingSizedButtonsHaveMinHeight() throws {
        let found = try Self.offenders(Self.isPaddingSizedButton)
        #expect(found.isEmpty, """
            .padding(.vertical, 12 以下) で高さを決めるボタンは GameButtonStyle(role:shape:) \
            （minHeight 44pt）に寄せる。意図的なら行末に // a11y-ok: 理由。\n\(found.joined(separator: "\n"))
            """)
    }

    /// 対照: ボタンの起点を実際に見つけていること（見つからない検査は何も止めない）。
    @Test("ボタンの起点を実際に検出している")
    func buttonStartsAreDetected() throws {
        var count = 0
        for lines in try Self.scannedFiles() { count += lines.filter { Self.isButtonStart($0.text) }.count }
        #expect(count > 200)
    }

    // MARK: 判定ロジックの確認（違反コードで赤になること）

    @Test("名前の無いアイコンだけのボタンは違反、名前やラベルがあれば通す")
    func iconRuleRules() {
        #expect(Self.isUnlabeledIconButton("Button { go() } label: { Image(systemName: \"gear\") }"))
        #expect(!Self.isUnlabeledIconButton("Button { go() } label: { Image(systemName: \"gear\") }\n.accessibilityLabel(\"設定\")"))
        #expect(!Self.isUnlabeledIconButton("Button { go() } label: { Label(\"設定\", systemImage: \"gear\") }"))
        #expect(!Self.isUnlabeledIconButton("Button { go() } label: { Image(systemName: \"gear\") }\n.accessibilityHidden(true)"))
        #expect(!Self.isUnlabeledIconButton("Button(\"OK\") { go() }"))
    }

    @Test("隠していないシェブロンは違反、DisclosureChevron や accessibilityHidden があれば通す")
    func chevronRules() {
        #expect(Self.hasUnhiddenChevron("Button { go() } label: { HStack { Text(\"a\"); Image(systemName: \"chevron.right\") } }"))
        #expect(!Self.hasUnhiddenChevron("Button { go() } label: { HStack { Text(\"a\"); DisclosureChevron() } }"))
        #expect(!Self.hasUnhiddenChevron("Button { go() } label: { HStack { Text(\"a\"); Image(systemName: \"chevron.down\").accessibilityHidden(true) } }"))
        #expect(!Self.hasUnhiddenChevron("Button { go() } label: { Image(systemName: \"gear\") }"))
    }

    @Test("44 未満の固定 frame は違反、手当てや 44 以上があれば通す")
    func tapTargetRules() {
        #expect(Self.isSmallTapTarget("Button { go() } label: { Image(systemName: \"x\").frame(width: 28, height: 28) }"))
        #expect(!Self.isSmallTapTarget("Button { go() } label: { Image(systemName: \"x\").frame(width: 28, height: 28) }\n.contentShape(Rectangle())"))
        #expect(!Self.isSmallTapTarget("Button { go() } label: { Image(systemName: \"x\").frame(width: 28, height: 28) }\n.frame(minWidth: GameButtonMetrics.minTapTarget)"))
        #expect(!Self.isSmallTapTarget("Button { go() } label: { Image(systemName: \"x\").frame(width: 44, height: 44) }"))
        #expect(!Self.isSmallTapTarget("Button { go() } label: { Text(\"a\").frame(maxWidth: .infinity) }"))
    }

    @Test("余白だけで高さを決めるボタンは違反、GameButtonStyle や minHeight があれば通す")
    func paddingSizedRules() {
        #expect(Self.isPaddingSizedButton("Button { go() } label: { Text(\"a\").padding(.vertical, 10) }"))
        #expect(Self.isPaddingSizedButton("Button { go() } label: { Text(\"a\").padding(.horizontal, 12).padding(.vertical, 7) }"))
        #expect(!Self.isPaddingSizedButton("Button { go() } label: { Text(\"a\").padding(.vertical, 10) }\n.buttonStyle(GameButtonStyle(role: .ad))"))
        #expect(!Self.isPaddingSizedButton("Button { go() } label: { Text(\"a\").padding(.vertical, 10).frame(minHeight: 44) }"))
        #expect(!Self.isPaddingSizedButton("Button { go() } label: { Text(\"a\").padding(.vertical, 16) }"))
    }
}
