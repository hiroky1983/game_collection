import Foundation
import Testing
import GameKitTestSupport

/// 「くわしいルール」（`.howToPlay(_:extra:)` の `extra`）が共通部品 `RuleListSheet` で組まれていること
/// （#1231 で ScrollView とカード背景を確かめていたものを、#1414 で共通部品の使用そのものに強化）。
/// あわせて役の早見表（麻雀・花札・ポーカー）が `YakuTableSheet` で組まれていること。
///
/// チェス（`ScrollView` 自体が無く下が切れて読めない）・囲碁（`ScrollView` はあるがセクションの
/// カード背景が無い）で、会長QAが同種の崩れを複数回見つけていた。毎回QAで見つかるのではなく、
/// 新しいゲームを足したときに機械的に落ちるようにする。
@Suite("くわしいルールは共通部品 RuleListSheet で組む（#1231・#1414）")
struct RuleDetailScrollAndCardSourceTests {

    @Test("howToPlay の extra はすべて RuleListSheet で始まる")
    func extraViewsUseRuleListSheet() throws {
        let files = try Self.swiftFiles()

        var allSource = ""
        var typeNames: Set<String> = []
        for file in files {
            let text = try String(contentsOf: Self.sourcesDirectory.appendingPathComponent(file), encoding: .utf8)
            allSource += text + "\n"
            typeNames.formUnion(Self.extractExtraTypeNames(from: text))
        }

        // 空振り防止。件数が極端に減ったらパスの導出か抽出ロジックが壊れている。
        #expect(typeNames.count >= 10, "howToPlay の extra 抽出が空振りしている可能性: \(typeNames.sorted())")

        for typeName in typeNames.sorted() {
            guard let declaration = SourceScan.declaration(of: "struct \(typeName)", in: allSource) else {
                Issue.record("\(typeName) の定義が見つからない（howToPlay の extra から抽出された型名）")
                continue
            }
            // コメント中の語（「ScrollView 自体が無く…」等）で素通りしないよう、コメントを除いて判定する（#1273）。
            let body = SourceScan.strippingComments(declaration)
            // 共通部品（`RuleListSheet`）の呼び出しで body が始まっていること（#1414）。
            // 共通部品自身が ScrollView・カード背景・題名「くわしいルール」を持つので、それだけ確かめれば足りる。
            // 独自の見た目を許す例外は作らない（許可リストは空）。
            #expect(Self.bodyStarts(with: "RuleListSheet(", in: body),
                    "\(typeName) の body が RuleListSheet で始まっていない（くわしいルールは共通部品を使う）")
        }
    }

    @Test("役の早見表（*YakuSheet・*BonusTableSheet）は YakuTableSheet で始まる（#1414）")
    func yakuTablesUseSharedFrame() throws {
        var allSource = ""
        var typeNames: Set<String> = []
        let regex = try NSRegularExpression(pattern: #"struct\s+(\w*(?:Yaku|BonusTable)Sheet)\s*:\s*View"#)
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: Self.sourcesDirectory.appendingPathComponent(file), encoding: .utf8)
            allSource += text + "\n"
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { typeNames.insert(String(text[range])) }
            }
        }
        // 麻雀・花札・ポーカーの 3 本。減ったら抽出が壊れている。
        #expect(typeNames.count >= 3, "役の早見表の抽出が空振りしている可能性: \(typeNames.sorted())")
        for typeName in typeNames.sorted() {
            guard let declaration = SourceScan.declaration(of: "struct \(typeName)", in: allSource) else {
                Issue.record("\(typeName) の定義が見つからない")
                continue
            }
            #expect(Self.bodyStarts(with: "YakuTableSheet(", in: SourceScan.strippingComments(declaration)),
                    "\(typeName) の body が YakuTableSheet で始まっていない（役の早見表は共通部品を使う）")
        }
    }

    // MARK: - ヘルパー

    /// `var body: some View {` の直後の最初の式が `call` で始まるか（コメント除去済みのソースを渡す）。
    private static func bodyStarts(with call: String, in declaration: String) -> Bool {
        guard let head = declaration.range(of: "var body: some View {") else { return false }
        return declaration[head.upperBound...]
            .drop(while: { $0.isWhitespace })
            .hasPrefix(call)
    }

    private static var sourcesDirectory: URL {
        SourceScan.packageRoot.appendingPathComponent("Sources")
    }

    private static func swiftFiles() throws -> [String] {
        try FileManager.default
            .subpathsOfDirectory(atPath: sourcesDirectory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    /// `.howToPlay(.xxx) { ... }`（`extra:` があればそちらのクロージャ）の中で最初に出てくる
    /// 型初期化（`TypeName(` ）を「くわしいルール」の型とみなして拾う。
    ///
    /// `.howToPlay(.othello)` のように「遊び方」3行だけで `extra` を持たないゲームは、
    /// 呼び出しの直後にクロージャが無く、次の行は無関係な別モディファイア（`.sheet { ... }` 等）に
    /// なる。引数リストの閉じ括弧 `)` の直後が `{` かどうかを見て、直後にクロージャが無ければ
    /// そのゲームは対象外として扱う（後続の無関係なクロージャを拾わないため）。
    private static func extractExtraTypeNames(from source: String) -> [String] {
        var results: [String] = []
        var searchStart = source.startIndex
        while let callRange = source.range(of: ".howToPlay(", range: searchStart..<source.endIndex) {
            let openParen = source.index(before: callRange.upperBound)
            guard let argsEnd = matchingParen(in: source, openAt: openParen) else {
                searchStart = callRange.upperBound
                continue
            }
            var cursor = source.index(after: argsEnd)
            while cursor < source.endIndex, source[cursor].isWhitespace {
                cursor = source.index(after: cursor)
            }
            guard cursor < source.endIndex, source[cursor] == "{",
                  let firstBlockEnd = matchingBrace(in: source, openAt: cursor) else {
                // extra を持たない呼び出し（`.howToPlay(.othello)` 等）。対象外。
                searchStart = argsEnd
                continue
            }
            var block = String(source[cursor...firstBlockEnd])
            var afterBlock = source.index(after: firstBlockEnd)
            while afterBlock < source.endIndex, source[afterBlock].isWhitespace {
                afterBlock = source.index(after: afterBlock)
            }
            // `.howToPlay(_:onPresent:extra:)` は 1 つ目のクロージャが onPresent なので、
            // `extra:` ラベルがあればそちらを「くわしいルール」の中身として使う。
            if source[afterBlock...].hasPrefix("extra:") {
                var extraCursor = source.index(afterBlock, offsetBy: "extra:".count)
                while extraCursor < source.endIndex, source[extraCursor].isWhitespace {
                    extraCursor = source.index(after: extraCursor)
                }
                if extraCursor < source.endIndex, source[extraCursor] == "{",
                   let extraBlockEnd = matchingBrace(in: source, openAt: extraCursor) {
                    block = String(source[extraCursor...extraBlockEnd])
                    afterBlock = source.index(after: extraBlockEnd)
                }
            }
            if let typeName = firstTypeInstantiation(in: block) {
                results.append(typeName)
            }
            searchStart = afterBlock
        }
        return results
    }

    private static func matchingParen(in source: String, openAt: String.Index) -> String.Index? {
        var depth = 0
        var index = openAt
        while index < source.endIndex {
            if source[index] == "(" { depth += 1 }
            if source[index] == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func firstTypeInstantiation(in block: String) -> String? {
        let stripped = SourceScan.strippingComments(block)
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z][A-Za-z0-9_]*\("#) else { return nil }
        let range = NSRange(stripped.startIndex..., in: stripped)
        guard let match = regex.firstMatch(in: stripped, range: range),
              let matchRange = Range(match.range, in: stripped) else { return nil }
        return String(stripped[matchRange].dropLast())
    }

    private static func matchingBrace(in source: String, openAt: String.Index) -> String.Index? {
        var depth = 0
        var index = openAt
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }
}

// MARK: - 設定シートの命名規則（#1231）

/// `*SetupSheet`・`*NewGameSheet` という命名の View（対局・ゲーム開始前の設定を持つシート）は
/// `GameSetupSheet` を使うこと。
///
/// `Packages/GameKit/Tests/ThemeTests/GameSetupSheetTests.swift` の既存テストは、共通枠へ
/// 載せ替え済みのゲームをハードコードしたリストで確認している。こちらは**命名規則から機械的に
/// 対象を拾う**ことで、新しいゲームがこの命名でシートを増やしたときに自動的に検査対象へ入る。
@Suite("設定シートは *SetupSheet・*NewGameSheet 命名なら GameSetupSheet を使う（#1231）")
struct SetupSheetNamingConventionSourceTests {

    /// 意図的に `GameSetupSheet` を使わない例外。理由をここに書く（現在は無い。ソリティアも #1416 で載せ替え済み）。
    private static let exceptions: Set<String> = []

    @Test("*SetupSheet・*NewGameSheet という命名の View は GameSetupSheet を使う")
    func namedSheetsUseSharedFrame() throws {
        let sourcesDirectory = SourceScan.packageRoot.appendingPathComponent("Sources")
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: sourcesDirectory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        guard let regex = try? NSRegularExpression(
            pattern: #"struct\s+(\w*(?:SetupSheet|NewGameSheet))\s*:\s*View"#
        ) else {
            Issue.record("正規表現が不正")
            return
        }

        var allSource = ""
        var typeNames: Set<String> = []
        for file in files {
            let text = try String(contentsOf: sourcesDirectory.appendingPathComponent(file), encoding: .utf8)
            allSource += text + "\n"
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
                typeNames.insert(String(text[nameRange]))
            }
        }

        // 空振り防止。件数が極端に減ったらパスの導出か正規表現が壊れている。
        #expect(typeNames.count >= 8, "*SetupSheet・*NewGameSheet の抽出が空振りしている可能性: \(typeNames.sorted())")

        for typeName in typeNames.sorted() where !Self.exceptions.contains(typeName) {
            guard let body = SourceScan.declaration(of: "struct \(typeName)", in: allSource) else {
                Issue.record("\(typeName) の定義が見つからない")
                continue
            }
            #expect(body.contains("GameSetupSheet("), "\(typeName) が GameSetupSheet を使っていない")
        }
    }
}
