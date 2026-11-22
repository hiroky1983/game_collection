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

    @Test("英訳が `%lld` + 数えられる名詞なのに複数形（one / other）が無いものは、理由つきの除外リストにだけ置ける（#3423）")
    func countedNounsNeedPlural() throws {
        var flagged: Set<String> = []
        for place in Self.places {
            let data = try Data(contentsOf: place.catalog)
            let catalog = try #require(StringCatalog(data: data))
            for (key, translations) in catalog.entries {
                guard case .text(let english)? = translations["en"], Self.countedNoun(in: english) else { continue }
                flagged.insert(key)
                #expect(Self.pluralExemptions[key] != nil,
                        "\(place): 「\(key)」の英語「\(english)」は数 + 名詞なのに単複の別が無い（1 でも複数形になる）。variations.plural の one / other に直す。1 にならない数・単複が同じ語なら `pluralExemptions` に理由つきで足す")
            }
        }
        for key in Self.pluralExemptions.keys where !flagged.contains(key) {
            Issue.record("`pluralExemptions` の「\(key)」はもう検査に掛からない。除外リストから消す")
        }
    }

    /// 単複の検査（`countedNounsNeedPlural`）から外す文言と、その理由。1 にならない数（ルールで決まった定数・
    /// 下限が 2 以上）か、複数形で選ぶ数（最初の整数の引数）と名詞が掛かる数が別のものだけが対象。
    static let pluralExemptions: [String: String] = [
        "円盤%lld枚": "円盤は 3〜7 枚から選ぶ（HanoiLogic.diskRange）",
        "全 %lld 面クリア": "全面数は定数（数十面）",
        "%1$lld×%2$lld・地雷%3$lld": "地雷の数は盤の大きさごとの定数で、複数形を選ぶ最初の整数は盤の幅",
        "%1$lld×%2$lld  %3$lld地雷": "地雷の数は盤の大きさごとの定数で、複数形を選ぶ最初の整数は盤の幅",
        "%lld 回勝負して、勝ち点の合計で競います。": "勝負の回数は 3 回以上の選択肢",
        "もう一度%lld回勝負": "勝負の回数は 3 回以上の選択肢",
        "%lld 回勝負して、合計点の多いほうが勝ちです。": "勝負の回数は 3 回以上の選択肢",
        "ボーナス%1$lld点、上段の小計%2$lld、%3$lld点以上で%4$lld点": "ボーナスの点・基準点はルールの定数",
        "%1$@から上の%2$lld枚": "2 枚以上の列を動かすときだけ使う（呼び出し側が count > 1 で分岐）",
        "左上の %lld つの枠が「フリーセル」です。": "フリーセルの枠数は定数 4",
        "%1$@。金の松どうしがくっつくと 2 つとも消えて %2$lld 点。": "金の松の得点は定数 100",
        "猪鹿蝶・赤短・三光は、どれも %lld 文です。": "役の点は定数",
        "最少 %1$lld手に対して %2$lld手": "最少手数は円盤 3 枚以上で 7 手以上、手数はそれ以上",
        "%lld点で終了": "終了の点は定数（100）",
        "だれかが%lld点に届いたら終了。合計の少ない人が勝ちです": "終了の点は定数（100）",
        "1 手で動く点は全部で %lld 点。だれかが %lld 点に届いたら終わりです。": "点はルールの定数（26・100）",
        "だれかが %lld 点に届いたら、そこで終わりです。": "終了の点は定数（100）",
        "1 挑戦 = %lld 球": "1 挑戦の球数は定数",
        "記録と実績。実績 %1$lld / %2$lld": "「X of Y achievements」は定数の Y に掛かる（1 of 12 は文法どおり）",
        "役満は %1$lld点（子）・%2$lld点（親）。複数そろうと倍になります。": "役満の点は定数（32000・48000）",
        "ノーテン罰符（テンパイ +%1$lld点・ノーテン -%2$lld点）": "罰符の点は 1000 点単位",
        "役は全部で %lld 種類あります。": "役の種類数は定数",
        "ステージ 1 から %1$lld 面を順にクリアして、%2$lld つの世界を先へ進む、いつもの遊び方": "面数・世界数は定数",
        "ノルマは かんたん %1$lld 枚・ふつう %2$lld 枚・むずかしい %3$lld 枚です。": "ノルマの枚数は定数（4・6・9）",
        "制限時間は %lld 秒です。": "制限時間は定数（60）",
        "しりとりが成立すると +%lld 秒。": "加算の秒数は定数（10）",
        "合わない札を選ぶと -%lld 秒です。": "減算の秒数は定数（5）",
        "手札は、最大 %lld 枚です。": "手札の枚数は定数（4）",
        "%lld 組すべて取り除いたら、クリアです。": "組の数は定数（8）",
    ]

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

    /// 英訳に「`%lld` + 数えられる名詞」があるか。`pt(s)` のように（s）を併記した書き方は単複どちらでも通るので除く。
    static func countedNoun(in english: String) -> Bool {
        let nouns = "moves?|seeds?|pts|points?|cards?|stages?|disks?|mistakes?|lives?|cells?|mines?|days?|hours?|tiles?"
            + "|kinds?|suits?|checkers?|seconds?|minutes?|slots?|sets?|pitch(?:es)?|rounds?|achievements?|plays?|undos?"
        let pattern = #"%(?:\d+\$)?lld\s?(?:more\s+|of\s+)?(?:"# + nouns + #")\b(?!\()"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        return regex.firstMatch(in: english, range: NSRange(english.startIndex..., in: english)) != nil
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)      // ひらがな・カタカナ
                || (0x4E00...0x9FFF).contains(scalar.value) // 漢字
                || (0xFF01...0xFF5E).contains(scalar.value) // 全角の記号・英数
        }
    }
}
