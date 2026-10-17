import Foundation
import Observation

/// アプリの表示言語（多言語① #2109）。
///
/// 開発言語は日本語で、文言の表（String Catalog）の**キーは日本語の原文そのもの**。英語は表の訳を引く。
/// 端末の言語が日本語以外（英語・中国語・フランス語…）のときは英語として扱う（会長決定 2026-10-12）。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case japanese = "ja"
    case english = "en"

    /// 開発言語。表のキー（原文）の言語で、訳が無いときの戻り先でもある。
    public static let development: AppLanguage = .japanese

    public var id: String { rawValue }

    /// 数字・日付の書式に使うロケール。
    public var locale: Locale { Locale(identifier: rawValue) }

    /// 選択肢に出す名前。どの言語で表示していても、その言語自身の呼び名で出す（訳さない）。
    /// 読めない言語に切り替えてしまった人が、自分の言語を見つけて戻れるようにするため。
    public var nativeName: String {
        switch self {
        case .japanese: "日本語"  // i18n-keep: 言語の自称（どの言語で表示していても訳さない）
        case .english: "English"
        }
    }

    /// 端末の言語の並び（`Locale.preferredLanguages`）から決める。先頭が日本語なら日本語、それ以外は英語。
    /// 並びが空（取得できない）なら開発言語。
    public static func matching(preferredLanguages: [String]) -> AppLanguage {
        guard let first = preferredLanguages.first else { return .development }
        return first.lowercased().hasPrefix("ja") ? .japanese : .english
    }
}

/// いま表示に使う言語の置き場（#2109）。アプリ本体・GameKit の全モジュールが同じ 1 つを見る。
///
/// - **即時に切り替わる**: `language` は Observation で見張られるので、`body` の中で文言の表
///   （`StringTable`）を引いた View は、言語を変えた瞬間に描き直される。アプリの再起動は要らない。
///   システムの言語（`AppleLanguages`）には触らず、アプリが自分の文言の表を選び直すだけの方式のため
///   （Apple はアプリ内からシステムの言語を切り替える API を用意していない。経緯は PR #2109 の説明）。
/// - **起動するまでは開発言語（日本語）**: `bootstrap()` を呼ぶのはアプリ本体の起動時だけ。
///   `swift test` は呼ばないので、日本語の文言を確かめている既存のテストは端末（CI の macOS は英語）に
///   左右されない。英語を確かめるテストは `language: .english` を明示して引く。
/// - スレッドをまたいで読まれる（通知の予約など）ので、値は鍵で守る。
public final class AppLanguageStore: Observable, @unchecked Sendable {
    /// アプリ全体で 1 つの置き場。
    public static let shared = AppLanguageStore()

    /// 設定画面で選んだ言語の保存キー。未保存なら端末の言語に合わせる。
    public static let storageKey = "appLanguage_v1"

    private let lock = NSLock()
    private let registrar = ObservationRegistrar()
    private var current: AppLanguage

    public init(language: AppLanguage = .development) {
        self.current = language
    }

    /// いま表示に使う言語。
    public var language: AppLanguage {
        registrar.access(self, keyPath: \.language)
        return lock.withLock { current }
    }

    /// 表示に効かせるだけで保存はしない（起動時の読み込み・プレビュー）。
    public func apply(_ language: AppLanguage) {
        guard lock.withLock({ current }) != language else { return }
        registrar.withMutation(of: self, keyPath: \.language) {
            lock.withLock { current = language }
        }
    }

    /// 設定画面で選んだ言語を保存して、すぐに表示へ効かせる。
    public func select(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: Self.storageKey)
        apply(language)
    }

    /// 起動時に 1 回呼ぶ。保存した選択があればそれ、無ければ端末の言語。
    public func bootstrap(defaults: UserDefaults = .standard,
                          preferredLanguages: [String] = Locale.preferredLanguages) {
        apply(Self.savedOrDeviceLanguage(defaults: defaults, preferredLanguages: preferredLanguages))
    }

    /// 保存した選択（無ければ端末の言語）。設定画面の初期値もこれと同じ規則になる。
    public static func savedOrDeviceLanguage(defaults: UserDefaults = .standard,
                                             preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        if let raw = defaults.string(forKey: storageKey), let saved = AppLanguage(rawValue: raw) {
            return saved
        }
        return .matching(preferredLanguages: preferredLanguages)
    }
}
