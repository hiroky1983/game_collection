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
    /// 中断データから局を**そのまま復元する**か（#663）。既定は true。
    ///
    /// 中断データを記録の控えとして使い、局そのものは必ず頭から始めるゲームは false を返す。
    /// 戻っても続きが無いゲームに「途中のままです」のお知らせを送らないため。
    var resumesFromSnapshot: Bool { get }
    /// 中断データが「続きから」で戻れる**途中の局**か（#809）。ハブの「続きから」表示と
    /// `game_open` の `resume` はすべてこれで決める。
    ///
    /// 既定は「局を復元するゲームで、中断データが在る」。終局後も見返しを中断データに残すゲーム
    /// （将棋・チェス）は、保存された局面を読んで決着済みなら false を返す。**アプリを起動し直しても
    /// 同じ答えになる**よう、判定は保存済みのものだけから作る（新しい保存先は増やさない）。
    func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool
}

public extension GameModule {
    var resumesFromSnapshot: Bool { true }

    func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        resumesFromSnapshot && snapshots.exists(for: id)
    }
}
