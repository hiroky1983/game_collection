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
