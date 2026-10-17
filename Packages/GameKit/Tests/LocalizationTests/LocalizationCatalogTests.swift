import Foundation
import Testing
import CoreEngine
import GameKitTestSupport

/// リポジトリにある全部の文言の表（App と GameKit の全モジュール）の検査（多言語① #2109）。
///
/// ②〜⑥で文言を足すときに落ちるのはここ。落ちたら、メッセージにあるモジュールの
/// `Resources/Localization/Localizable.xcstrings`（App は `App/Localization/Localizable.xcstrings`）を直す。
@Suite("文言の表の検査")
struct LocalizationCatalogTests {
    /// 表を持つ場所（表示名・表のファイル・その表を引くソースのディレクトリ）。
    struct Place: CustomStringConvertible {
        let name: String
        let catalog: URL
        let sources: URL
        var description: String { name }
    }

    static var places: [Place] {
        let sourcesDir = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = (try? FileManager.default.contentsOfDirectory(atPath: sourcesDir.path)) ?? []
        var result = modules.sorted().compactMap { module -> Place? in
            let dir = sourcesDir.appendingPathComponent(module)
            let catalog = dir.appendingPathComponent("Resources/Localization/Localizable.xcstrings")
            guard FileManager.default.fileExists(atPath: catalog.path) else { return nil }
            return Place(name: module, catalog: catalog, sources: dir)
        }
        let app = SourceScan.repositoryRoot.appendingPathComponent("App")
        result.append(Place(name: "App", catalog: app.appendingPathComponent("Localization/Localizable.xcstrings"),
                            sources: app))
        return result
    }

    /// 文言を持ちうるモジュール（製品のソースのターゲット）。テスト用の部品は除く。
    static let productModules: [String] = {
        let sourcesDir = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = (try? FileManager.default.contentsOfDirectory(atPath: sourcesDir.path)) ?? []
        return modules.filter { !$0.hasPrefix(".") && $0 != "CoreTestSupport" }.sorted()
    }()

    @Test("製品のモジュールは全部、自分の表と `tr` を持ち、Package.swift で同梱している")
    func everyModuleHasItsTable() throws {
        #expect(Self.productModules.count >= 30, "Sources の数え方が外れている")
        let manifest = try SourceScan.packageSource("Package.swift")
        let places = Set(Self.places.map(\.name))
        for module in Self.productModules {
            #expect(places.contains(module), "\(module) に Resources/Localization/Localizable.xcstrings が無い")
            let code = try SourceScan.moduleSources(module)
            #expect(code.contains("let tr = StringTable(bundle: .module)"), "\(module) に Localization.swift（tr の定義）が無い")
            // `.target(name: "<module>"` から次の `.target(` / `.testTarget(` までに同梱の指定があること。
            let start = try #require(manifest.range(of: ".target(name: \"\(module)\""), "\(module) のターゲットが無い")
            let rest = manifest[start.upperBound...]
            let end = [rest.range(of: ".target("), rest.range(of: ".testTarget(")]
                .compactMap { $0?.lowerBound }.min() ?? rest.endIndex
            #expect(rest[..<end].contains(".copy(\"Resources/Localization\")"),
                    "\(module) の resources に .copy(\"Resources/Localization\") が無い")
        }
    }

    @Test("表の形が正しい（JSON・開発言語は ja・全部のキーに英語の訳）", arguments: places)
    func catalogIsComplete(place: Place) throws {
        let data = try Data(contentsOf: place.catalog)
        let catalog = try #require(StringCatalog(data: data), "\(place) の表が JSON として読めない")
        #expect(catalog.sourceLanguage == "ja", "\(place) の sourceLanguage が ja でない")
        for (key, translations) in catalog.entries {
            guard let english = translations["en"] else {
                Issue.record("\(place): 「\(key)」に英語の訳が無い")
                continue
            }
            let forms: [String]
            switch english {
            case .text(let text): forms = [text]
            case .plural(let byCategory):
                #expect(byCategory["other"] != nil, "\(place): 「\(key)」の複数形に other が無い")
                forms = Array(byCategory.values)
            }
            for form in forms {
                #expect(!form.trimmingCharacters(in: .whitespaces).isEmpty || key.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(place): 「\(key)」の英語が空")
                #expect(!Self.containsJapanese(form), "\(place): 「\(key)」の英語に日本語が残っている: \(form)")
                #expect(Self.specifiers(form) == Self.specifiers(key),
                        "\(place): 「\(key)」と英語「\(form)」で書式指定（%@・%lld）が食い違う")
            }
        }
    }

    @Test("ソースで `tr(\"…\")` に書いたキーは全部、そのモジュールの表にある", arguments: places)
    func everyKeyIsInTheTable(place: Place) throws {
        let data = try Data(contentsOf: place.catalog)
        let catalog = try #require(StringCatalog(data: data))
        for key in try Self.literalKeys(in: place.sources) {
            #expect(!key.contains("\\("), "\(place): 「\(key)」はキーに文字列補間を使っている。%@ / %lld の書式にして引数で渡す")
            #expect(catalog.entries[key] != nil, "\(place): 「\(key)」が表に無い（英語のときも日本語のまま出る）")
        }
    }

    // MARK: - 検査の部品

    /// `dir` 以下（`Resources` を除く）の Swift ソースから、`tr("…")` のキーを取り出す。
    static func literalKeys(in dir: URL) throws -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var keys = Set<String>()
        let pattern = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])tr\(\s*"((?:[^"\\]|\\.)*)""#)
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let code = SourceScan.strippingComments(try String(contentsOf: url, encoding: .utf8))
            let range = NSRange(code.startIndex..., in: code)
            for match in pattern.matches(in: code, range: range) {
                guard let r = Range(match.range(at: 1), in: code) else { continue }
                keys.insert(unescape(String(code[r])))
            }
        }
        return keys
    }

    /// Swift の文字列リテラルのエスケープを戻す（表のキーは実際の文字で持つため）。
    static func unescape(_ literal: String) -> String {
        var result = ""
        var iterator = literal.makeIterator()
        while let c = iterator.next() {
            guard c == "\\", let next = iterator.next() else { result.append(c); continue }
            switch next {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            default: result.append("\\"); result.append(next)
            }
        }
        return result
    }

    /// 書式指定の種類の並び（位置指定 `%1$@` は位置で並べ、`%%` は数えない）。
    static func specifiers(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"%(?:(\d+)\$)?(@|lld|ld|d|f|\.\d+f|s|%)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var positional: [(Int, String)] = []
        var index = 0
        for match in regex.matches(in: text, range: range) {
            guard let typeRange = Range(match.range(at: 2), in: text) else { continue }
            let type = String(text[typeRange])
            if type == "%" { continue }
            index += 1
            if let posRange = Range(match.range(at: 1), in: text), let pos = Int(text[posRange]) {
                positional.append((pos, type))
            } else {
                positional.append((index, type))
            }
        }
        return positional.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)      // ひらがな・カタカナ
                || (0x4E00...0x9FFF).contains(scalar.value) // 漢字
                || (0xFF01...0xFF5E).contains(scalar.value) // 全角の記号・英数
        }
    }
}
