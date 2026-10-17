import Core

/// アプリ本体の文言の表（`App/Localization/Localizable.xcstrings`・#2109）。
/// GameKit の各モジュールと同じ仕組みで、表だけがアプリ本体のバンドルにある。足し方は docs/spec-app.md「多言語（#2109）」。
let tr = StringTable(bundle: .main)
