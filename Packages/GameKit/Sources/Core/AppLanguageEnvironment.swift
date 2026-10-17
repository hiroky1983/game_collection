import SwiftUI

public extension View {
    /// 表示言語（`AppLanguageStore`・#2109）のロケールを `\.locale` として配る。アプリの根に 1 回だけ付ける。
    ///
    /// 文言そのものは各モジュールの `tr(...)` が表示言語で引くので、これが効かせるのは数字・日付の書式と
    /// システムの部品（`Picker` などの既定の文字）だけ。言語を切り替えると、この View が描き直されて
    /// 子の `\.locale` も入れ替わる（`language` を Observation が見張っている）。
    func appLanguageEnvironment(_ store: AppLanguageStore = .shared) -> some View {
        modifier(AppLanguageEnvironmentModifier(store: store))
    }
}

private struct AppLanguageEnvironmentModifier: ViewModifier {
    let store: AppLanguageStore

    func body(content: Content) -> some View {
        content.environment(\.locale, store.language.locale)
    }
}
