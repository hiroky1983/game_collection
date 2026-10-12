import Foundation

/// 1 モジュール分の文言の表（多言語① #2109）。
///
/// 表の実体は各モジュールの `Resources/Localization/Localizable.xcstrings`（Xcode の String Catalog と同じ形式の JSON）。
/// 各モジュールは自分の表を 1 つだけ持ち、`Localization.swift` で次の 1 行を置いて使う:
///
/// ```swift
/// let tr = StringTable(bundle: .module)   // アプリ本体は `.main`
///
/// Text(tr("設定"))                          // 引数なし
/// Text(tr("「%@」が途中のままです", title))  // 書式付き（%@ = 文字列、%lld = 整数）
/// ```
///
/// - **キーは日本語の原文**。日本語のときはキーをそのまま返し、英語のときは表の `en` を返す。
///   `en` が無いキーは日本語のまま出る（訳し漏れは `LocalizationCatalogTests` が落とす）。
/// - **表はコンパイルせず、そのまま同梱して実行時に読む**（Package.swift は `.copy`、project.yml は folder 参照）。
///   Xcode がコンパイルした `.lproj` はシステムの言語で引かれ、アプリ内で選んだ言語に追従させるには
///   結局自前の引き分けが要る。それなら同じ JSON を `swift test`（CI）とアプリの両方で同じコードが読む形にして、
///   英語の表示をテストで確かめられるようにする。
/// - 複数形は String Catalog の `variations.plural`（`one` / `other`）に対応する。最初の整数の引数で選ぶ。
public struct StringTable: Sendable {
    /// 表のファイル。見つからない（同梱漏れ）ときは nil で、そのときは常にキー（日本語）を返す。
    public let catalogURL: URL?

    /// `bundle` の `Localization/<catalog>.xcstrings` を表にする。
    public init(bundle: Bundle, catalog: String = "Localizable") {
        self.catalogURL = bundle.url(forResource: catalog, withExtension: "xcstrings", subdirectory: "Localization")
    }

    /// 表のファイルを直接指定する（テスト用）。
    public init(catalogURL: URL?) {
        self.catalogURL = catalogURL
    }

    /// `key`（日本語の原文）を `language`（省略時はいまの表示言語）の文言にする。
    /// `arguments` があれば訳文を書式として埋め込む。
    public func callAsFunction(_ key: String, _ arguments: any CVarArg..., language: AppLanguage? = nil) -> String {
        string(key, arguments: arguments, language: language ?? AppLanguageStore.shared.language)
    }

    /// `callAsFunction` の本体。可変長引数を配列で渡したいとき用。
    public func string(_ key: String, arguments: [any CVarArg], language: AppLanguage) -> String {
        let catalog = catalogURL.flatMap { StringCatalogCache.shared.catalog(at: $0) }
        let template = catalog?.template(for: key, language: language, arguments: arguments) ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, locale: language.locale, arguments: arguments)
    }

    /// 表に `language` の訳があるか（日本語は常に true）。
    public func hasTranslation(_ key: String, language: AppLanguage) -> Bool {
        if language == .development { return true }
        let catalog = catalogURL.flatMap { StringCatalogCache.shared.catalog(at: $0) }
        return catalog?.entries[key]?[language.rawValue] != nil
    }
}

/// String Catalog（`.xcstrings`）の中身のうち、表示に要る部分だけを持つ。
public struct StringCatalog: Sendable, Equatable {
    /// 1 言語分の訳。
    public enum Translation: Sendable, Equatable {
        case text(String)
        /// 複数形のカテゴリ（`zero` / `one` / `two` / `few` / `many` / `other`）ごとの訳。
        case plural([String: String])
    }

    public let sourceLanguage: String
    /// キー → 言語コード → 訳。
    public let entries: [String: [String: Translation]]

    public init(sourceLanguage: String, entries: [String: [String: Translation]]) {
        self.sourceLanguage = sourceLanguage
        self.entries = entries
    }

    /// `.xcstrings` の JSON を読む。形が崩れていれば nil。
    public init?(data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return nil }
        var entries: [String: [String: Translation]] = [:]
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            var byLanguage: [String: Translation] = [:]
            for (language, body) in localizations {
                guard let body = body as? [String: Any] else { continue }
                if let unit = body["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                    byLanguage[language] = .text(text)
                } else if let variations = body["variations"] as? [String: Any],
                          let plural = variations["plural"] as? [String: Any] {
                    var forms: [String: String] = [:]
                    for (category, form) in plural {
                        if let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any],
                           let text = unit["value"] as? String {
                            forms[category] = text
                        }
                    }
                    if !forms.isEmpty { byLanguage[language] = .plural(forms) }
                }
            }
            entries[key] = byLanguage
        }
        self.init(sourceLanguage: root["sourceLanguage"] as? String ?? AppLanguage.development.rawValue,
                  entries: entries)
    }

    /// 書式に使う訳文。訳が無ければキー（原文）。
    func template(for key: String, language: AppLanguage, arguments: [any CVarArg]) -> String {
        guard let translation = entries[key]?[language.rawValue] else { return key }
        switch translation {
        case .text(let text):
            return text
        case .plural(let forms):
            let category = Self.pluralCategory(for: arguments.lazy.compactMap(Self.integer).first, language: language)
            return forms[category] ?? forms["other"] ?? key
        }
    }

    /// 複数形のカテゴリ。今の対象は日本語（区別なし）と英語（1 だけ単数）だけなので、その 2 つの規則を持つ。
    static func pluralCategory(for count: Int64?, language: AppLanguage) -> String {
        switch language {
        case .japanese: return "other"
        case .english: return count == 1 ? "one" : "other"
        }
    }

    private static func integer(_ value: any CVarArg) -> Int64? {
        switch value {
        case let v as Int: return Int64(v)
        case let v as Int64: return v
        case let v as Int32: return Int64(v)
        case let v as UInt: return Int64(exactly: v)
        default: return nil
        }
    }
}

/// 読んだ表の置き場。1 つの表は最初に引いたときに 1 回だけ読む。
final class StringCatalogCache: @unchecked Sendable {
    static let shared = StringCatalogCache()

    private let lock = NSLock()
    private var catalogs: [URL: StringCatalog?] = [:]

    func catalog(at url: URL) -> StringCatalog? {
        lock.withLock {
            if let cached = catalogs[url] { return cached }
            let loaded = (try? Data(contentsOf: url)).flatMap(StringCatalog.init(data:))
            catalogs[url] = loaded
            return loaded
        }
    }
}
