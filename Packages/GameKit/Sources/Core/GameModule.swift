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
    /// 中断データが**手つかずの盤**（開いただけ・開始しただけで一手も指していない局）か（#2161）。
    ///
    /// `hasResumableSnapshot` が false でも、終局後の見返しのように「手つかずではない」中断データがある。
    /// その区別が要るのは、手つかずの盤を開き直したときに `game_start` を数え直すため。
    /// 既定は false（開いた時点で必ず Model が `game_start` を数えるゲームか、開始の契機が別にあるゲーム）。
    func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool
    /// 「続きから」の中断データの進み具合を 1 行で（例: 「32手目」「残り45マス」「3/10回目」）。ハブのタイルに出す（#2870）。
    ///
    /// `hasResumableSnapshot` が true のときだけ呼ばれる。既定は nil（出さない）。単発戦のように
    /// 進み具合が意味を持たないときも nil を返す。
    func resumeProgress(in snapshots: SnapshotStore) -> String?
}

public extension GameModule {
    var resumesFromSnapshot: Bool { true }

    func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        resumesFromSnapshot && snapshots.exists(for: id)
    }

    func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool { false }

    func resumeProgress(in snapshots: SnapshotStore) -> String? { nil }
}
