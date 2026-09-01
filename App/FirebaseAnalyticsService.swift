import Core
import FirebaseAnalytics

/// `AnalyticsService` の Firebase 実装（#158）。
///
/// GameKit 側は Firebase を知らず、この 1 ファイルだけが SDK に触る。
/// 送るイベント名・パラメータは `AnalyticsEvent` が組み立てたものをそのまま渡すだけで、
/// ここでキーや値を足さない（送信データの全量が Core の enum を読めば分かる状態を保つ）。
struct FirebaseAnalyticsService: AnalyticsService {
    @MainActor
    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: Self.parameters(event))
    }

    /// SDK 全体の収集状態を切り替える。
    ///
    /// `GatedAnalyticsService` が止められるのは `game_start` / `game_end` の**明示イベントだけ**で、
    /// `FirebaseApp.configure()` が有効にする自動収集イベント（`session_start` / `first_open` 等）は
    /// 素通りしてしまう。設定の「利用状況の送信」をオフにしたときはそれも止める必要があるため、
    /// SDK 側のスイッチもトグルと同じ値へ揃える（PR #162 の CodeRabbit 指摘）。
    ///
    /// - Note: この値は SDK 側でアプリのセッションをまたいで永続化され、`Info.plist` の
    ///   `FIREBASE_ANALYTICS_COLLECTION_ENABLED` より優先される。そのため起動時に必ず
    ///   こちらの設定値で上書きし、アプリの設定画面が唯一の正とする。
    ///   `Info.plist` 側は `NO`（既定オフ）にしてあり、上書きが効くまでの窓
    ///   （= 永続化された値がまだ無い初回起動）でも自動収集イベントが出ない（#382）。
    @MainActor
    static func setCollectionEnabled(_ isEnabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    /// 配布経路（`BuildChannel`）をユーザープロパティとして付与する（#347）。
    ///
    /// イベントのパラメータは従来どおり Core の `AnalyticsEvent` に閉じたまま、
    /// これだけが App 層で足す唯一の追加送信データ。値は `appstore` / `testflight` / `debug` の
    /// 3値 enum に閉じており、端末・個人を識別しうる情報は含まない。
    /// GA4 では比較（`build_channel = appstore`）で実ユーザーだけを抽出して読む。
    @MainActor
    static func setBuildChannel(_ channel: String) {
        Analytics.setUserProperty(channel, forName: "build_channel")
    }

    /// `AnalyticsValue` を Firebase が受け取る型へ落とす。
    /// 変換の対象は文字列と整数の2種だけで、それ以外の型は `AnalyticsValue` に存在しない。
    private static func parameters(_ event: AnalyticsEvent) -> [String: Any] {
        event.parameters.mapValues { value in
            switch value {
            case let .string(text): return text as Any
            case let .int(number):  return number as Any
            }
        }
    }
}
