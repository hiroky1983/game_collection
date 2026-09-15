import Foundation
import Observation

/// 評価リクエストの司令塔。全ゲームで1つを共有する（画面に出ているゲームは常に1つのため）。
///
/// `RecommendationService` と同じ構造で、決着した瞬間に Model から `gameDidFinish` を呼ぶ。
/// 実際に OS のダイアログを依頼するのは画面側（`reviewRequestPrompt`）で、ここは
/// 「いつ出すか」の判定と記録だけを持つ。中断データの復元で開き直しただけの画面を
/// 「勝った」と数えてしまわないよう、トリガーは必ず Model 側に置く。
@MainActor
@Observable
public final class ReviewRequestService {
    public let log: PlayLog
    private let appVersion: String
    private let now: () -> Date
    /// 条件6: リザルト表示からこれだけ待ってから呼ぶ（連続プレイの操作を遮らない）。
    private let delay: Duration

    /// リクエストの予定が立っている間だけ非 nil。値は毎回変わる連番で、画面側の
    /// `task(id:)` を予定ごとに1回だけ起動させるために使う。
    public private(set) var pendingRequestID: Int?
    private var issuedCount = 0

    public init(
        log: PlayLog,
        appVersion: String,
        now: @escaping () -> Date = { Date() },
        delay: Duration = .seconds(1)
    ) {
        self.log = log
        self.appVersion = appVersion
        self.now = now
        self.delay = delay
    }

    /// 決着したときに各ゲームの Model から呼ぶ。
    ///
    /// - Returns: 評価リクエストを出す予定になったか。同じリザルトに出るレコメンド（#52）を
    ///   next回に送るかの判断に使う（競合したら評価リクエストを優先する）。
    @discardableResult
    public func gameDidFinish(outcome: GameOutcome) -> Bool {
        // 条件1: 勝利・クリアの直後のみ。敗北・投了・ゲームオーバーでは勝利数も増やさない。
        guard outcome == .win else { return false }
        log.recordWin()

        guard pendingRequestID == nil else { return true }
        guard ReviewRequestPolicy.shouldRequest(
            state: log.reviewState,
            currentVersion: appVersion,
            now: now()
        ) else { return false }

        issuedCount += 1
        pendingRequestID = issuedCount
        return true
    }

    /// 予定されたリクエストを実行する。画面側（`reviewRequestPrompt`）から呼ぶ。
    ///
    /// - Parameter request: OS へのリクエスト本体（SwiftUI の `requestReview`）。
    ///   1.0秒待つ前に画面を離れるとキャンセルされ、予定は破棄する（別の画面で不意に出さない）。
    public func performPendingRequest(_ request: () -> Void) async {
        guard pendingRequestID != nil else { return }

        if delay > .zero {
            do {
                try await Task.sleep(for: delay)
            } catch {
                pendingRequestID = nil
                return
            }
        }

        guard pendingRequestID != nil else { return }
        pendingRequestID = nil
        // 出たかどうかは OS しか知らないため、呼んだ時点で記録する（条件3〜5の起点）。
        log.markReviewRequested(at: now(), version: appVersion)
        request()
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）。発火条件（勝利数・期間・バージョン）を通さずに予定を立てる。
    /// 実機の条件は生涯1〜2回のため、シミュレータでダイアログを確認する手段がこれしかない。
    public func simulateRequest() {
        issuedCount += 1
        pendingRequestID = issuedCount
    }
    #endif
}
