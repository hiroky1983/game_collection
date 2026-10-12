import Foundation
import Observation
import Testing
@testable import CoreEngine
@testable import Core

/// 表示言語の決め方と、文言の表の引き方（多言語① #2109）。
///
/// **`AppLanguageStore.shared` は書き換えない**（並列に走る他のテストが日本語の文言を見ているため）。
/// 置き場の振る舞いは、その場で作ったインスタンスと専用の `UserDefaults` で確かめる。
@Suite("表示言語")
struct AppLanguageTests {
    @Test("端末の言語の先頭が日本語なら日本語、それ以外はすべて英語（会長決定 2026-10-12）")
    func matchingDeviceLanguage() {
        #expect(AppLanguage.matching(preferredLanguages: ["ja-JP", "en-US"]) == .japanese)
        #expect(AppLanguage.matching(preferredLanguages: ["ja"]) == .japanese)
        #expect(AppLanguage.matching(preferredLanguages: ["en-US", "ja-JP"]) == .english)
        #expect(AppLanguage.matching(preferredLanguages: ["zh-Hans-CN"]) == .english)
        #expect(AppLanguage.matching(preferredLanguages: ["fr-FR", "ja-JP"]) == .english)
        // 取得できないときは開発言語。
        #expect(AppLanguage.matching(preferredLanguages: []) == .japanese)
    }

    @Test("選択肢の名前はその言語自身の呼び名（どの言語で表示していても訳さない）")
    func nativeNames() {
        #expect(AppLanguage.japanese.nativeName == "日本語")
        #expect(AppLanguage.english.nativeName == "English")
        #expect(AppLanguage.allCases == [.japanese, .english])
    }

    @Test("保存した選択があればそれ、無ければ端末の言語")
    func savedOrDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: "AppLanguageTests.savedOrDevice"))
        defaults.removePersistentDomain(forName: "AppLanguageTests.savedOrDevice")
        #expect(AppLanguageStore.savedOrDeviceLanguage(defaults: defaults, preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguageStore.savedOrDeviceLanguage(defaults: defaults, preferredLanguages: ["ja-JP"]) == .japanese)

        let store = AppLanguageStore()
        store.select(.english, defaults: defaults)
        #expect(store.language == .english)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == "en")
        // 端末が日本語でも、保存した選択が勝つ。
        #expect(AppLanguageStore.savedOrDeviceLanguage(defaults: defaults, preferredLanguages: ["ja-JP"]) == .english)

        let relaunched = AppLanguageStore()
        relaunched.bootstrap(defaults: defaults, preferredLanguages: ["ja-JP"])
        #expect(relaunched.language == .english)

        // 知らない値が入っていたら（将来の言語を消した等）端末の言語に倒す。
        defaults.set("xx", forKey: AppLanguageStore.storageKey)
        #expect(AppLanguageStore.savedOrDeviceLanguage(defaults: defaults, preferredLanguages: ["ja-JP"]) == .japanese)
        defaults.removePersistentDomain(forName: "AppLanguageTests.savedOrDevice")
    }

    @Test("起動するまでは開発言語（日本語）。swift test は bootstrap を呼ばないので、既存の日本語の検査が端末に左右されない")
    func startsInDevelopmentLanguage() {
        #expect(AppLanguageStore().language == .japanese)
        #expect(AppLanguageStore.shared.language == .japanese)
    }

    @Test("言語を変えると、それを読んでいた側へ変更が届く（View が再起動なしで描き直される根拠）")
    func notifiesObservers() {
        let store = AppLanguageStore()
        let changed = Flag()
        withObservationTracking {
            _ = store.language
        } onChange: {
            changed.set()
        }
        store.apply(.english)
        #expect(changed.value)

        // 同じ言語の再設定では知らせない（無駄な描き直しを起こさない）。
        let unchanged = Flag()
        withObservationTracking {
            _ = store.language
        } onChange: {
            unchanged.set()
        }
        store.apply(.english)
        #expect(!unchanged.value)
    }

    @Test("ロケールは数字・日付の書式に使う言語コード")
    func locales() {
        #expect(AppLanguage.japanese.locale.identifier == "ja")
        #expect(AppLanguage.english.locale.identifier == "en")
    }
}

/// `withObservationTracking` の `onChange` から書き込む印（Sendable にするため鍵で守る）。
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func set() { lock.withLock { raised = true } }
    var value: Bool { lock.withLock { raised } }
}

@Suite("文言の表の引き方")
struct StringTableTests {
    /// 一時ファイルに書いた表。
    private func table(_ json: String) throws -> StringTable {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StringTableTests-\(UUID().uuidString).xcstrings")
        try Data(json.utf8).write(to: url)
        return StringTable(catalogURL: url)
    }

    private let sample = """
    {
      "sourceLanguage" : "ja",
      "strings" : {
        "設定" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Settings" } } } },
        "「%@」が途中のままです" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Your %@ game is still in progress" } } } },
        "%1$@の%2$@" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "%2$@ of %1$@" } } } },
        "%lld連勝中！" : { "localizations" : { "en" : { "variations" : { "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld win in a row!" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld wins in a row!" } }
        } } } } },
        "訳なし" : { }
      },
      "version" : "1.0"
    }
    """

    @Test("日本語はキー（原文）をそのまま、英語は表の訳を返す")
    func plainText() throws {
        let tr = try table(sample)
        #expect(tr("設定", language: .japanese) == "設定")
        #expect(tr("設定", language: .english) == "Settings")
    }

    @Test("書式付きの文言に引数を埋め込む。英語は語順を入れ替えられる（%1$@ / %2$@）")
    func formatted() throws {
        let tr = try table(sample)
        #expect(tr("「%@」が途中のままです", "2048", language: .japanese) == "「2048」が途中のままです")
        #expect(tr("「%@」が途中のままです", "2048", language: .english) == "Your 2048 game is still in progress")
        #expect(tr("%1$@の%2$@", "スペード", "A", language: .japanese) == "スペードのA")
        #expect(tr("%1$@の%2$@", "spades", "A", language: .english) == "A of spades")
    }

    @Test("複数形は最初の整数で選ぶ（英語は 1 だけ単数）")
    func plural() throws {
        let tr = try table(sample)
        #expect(tr("%lld連勝中！", 1, language: .english) == "1 win in a row!")
        #expect(tr("%lld連勝中！", 3, language: .english) == "3 wins in a row!")
        #expect(tr("%lld連勝中！", 0, language: .english) == "0 wins in a row!")
        #expect(tr("%lld連勝中！", 3, language: .japanese) == "3連勝中！")
    }

    @Test("訳が無い・表に無い・表が読めないときは日本語（キー）のまま出す")
    func fallbacks() throws {
        let tr = try table(sample)
        #expect(tr("訳なし", language: .english) == "訳なし")
        #expect(tr("表に無い", language: .english) == "表に無い")
        #expect(!tr.hasTranslation("表に無い", language: .english))
        #expect(tr.hasTranslation("設定", language: .english))
        #expect(tr.hasTranslation("表に無い", language: .japanese))

        let missing = StringTable(catalogURL: nil)
        #expect(missing("設定", language: .english) == "設定")
        let broken = try table("{ not json")
        #expect(broken("設定", language: .english) == "設定")
    }

    @Test("引数の無い文言は書式として解釈しない（% を含んでも崩れない）")
    func noArgumentsNoFormatting() throws {
        let tr = try table(sample)
        #expect(tr("100%", language: .english) == "100%")
    }

    @Test("各モジュールの同梱の表が実際に読める（CoreEngine・Core）")
    func bundledCatalogsLoad() {
        #expect(CoreEngine.tr.catalogURL != nil, "CoreEngine の表が同梱されていない")
        #expect(Core.tr.catalogURL != nil, "Core の表が同梱されていない")
        #expect(CoreEngine.tr("設定を開く", language: .english) == "Open Settings")
        #expect(Core.tr("キャンセル", language: .english) == "Cancel")
        #expect(Core.tr("%lld連勝中！", 2, language: .english) == "2 wins in a row!")
    }

    @Test("CoreEngine の文言は英語でも組み立てられる（通知・ハブの 1 行）")
    func coreEngineSentencesInEnglish() {
        #expect(CoreEngine.tr("「%@」が途中のままです", "Go", language: .english) == "Your Go game is still in progress")
        #expect(CoreEngine.tr("新しいあそびが%lld本増えました", 1, language: .english) == "1 new game added")
        #expect(CoreEngine.tr("新しいあそびが%lld本増えました", 2, language: .english) == "2 new games added")
        #expect(CoreEngine.tr("%1$@の%2$@", "hearts", "Q", language: .english) == "Q of hearts")
    }
}
