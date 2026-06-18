import SwiftUI

/// ハブに登録される 1 ゲームの定義。ハブは登録された `GameModule` を動的に列挙するだけで、
/// 個々のゲームの中身を知らない。新ゲーム追加 = 1 モジュール追加 + レジストリ登録で完結する。
public protocol GameModule {
    /// 永続化キーや一意識別に使う ID（例: "2048" / "shogi"）。
    var id: String { get }
    /// ハブに表示するタイトル。
    var title: String { get }
    /// ハブカードに表示する一言説明。
    var description: String { get }
    /// ハブに表示するアイコン。
    var icon: Image { get }
    /// 横断サービスを注入してゲーム画面を生成する。
    @MainActor func makeView(services: GameServices) -> AnyView
}
