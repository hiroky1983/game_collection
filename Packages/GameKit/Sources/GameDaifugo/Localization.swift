import Core

/// このモジュールの文言の表（`Resources/Localization/Localizable.xcstrings`・#2109）。
/// 足し方は docs/spec-app.md「多言語（#2109）」。
let tr = StringTable(bundle: .module)

/// ゲーム名（ハブ・ヘッダー）。
///
/// 原文の「大富豪」が階級名（1 位・英語は Tycoon）と同じで、表（キー = 原文）では 1 つの訳しか持てないため、
/// ゲーム名だけは表を通さずここで言語ごとに持つ（#2166。英語の呼び名は会長決裁で "Daifugo"）。
func daifugoGameName(language: AppLanguage = AppLanguageStore.shared.language) -> String {
    language == .english ? "Daifugo" : "大富豪"  // i18n-keep: ゲーム名の日本語（身分の「大富豪」と表のキーが重なるため直書き）
}
