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
    ///
    /// **リザルトの手前に演出を挟むゲームでは、演出のあいだ nil に伏せる**（#1143）。画面側の
    /// `task(id:)` は id が nil → 値 に変わった時点で起動するので、伏せを解いた
    /// （＝リザルトに移った）瞬間から条件6の1.0秒が数え始める。
    public var pendingRequestID: Int? { isDeferredUntilResultIsVisible ? nil : issuedRequestID }

    /// 演出中（ゴールの演出・世界の締めなど）で、予定を伏せているか。
    public private(set) var isDeferredUntilResultIsVisible = false

    private var issuedRequestID: Int?
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
        // 演出の途中で画面を離れると伏せ（#1143）が残る。決着のたびに必ず外すことで、
        // それ以降どの画面でも二度と出ない状態にならないようにする。演出を挟むゲームは
        // この直後に `deferUntilResultIsVisible()` を呼んで伏せ直す（`RunnerModel`）。
        isDeferredUntilResultIsVisible = false

        guard issuedRequestID == nil else { return true }
        guard ReviewRequestPolicy.shouldRequest(
            state: log.reviewState,
            currentVersion: appVersion,
            now: now()
        ) else { return false }

        issuedCount += 1
        issuedRequestID = issuedCount
        return true
    }

    /// 予定を伏せる。決着とリザルトのあいだに演出を挟むゲームが、**演出の局面に入る入口**で呼ぶ（#1143）。
    ///
    /// 伏せと解除は局面の出入りに対で付ける（`RunnerModel` の `beginGoalChase` / `beginStory` と
    /// `skipGoalChase` / `finishStory`）。決着の側ではなく局面の側に付けることで、どの経路で
    /// 演出に入っても——QA 用の起動引数が `.cleared` を作ってから締めを被せる形（`-simulateRunner
    /// story-world1`）でも——伏せが揃う。
    public func deferUntilResultIsVisible() {
        isDeferredUntilResultIsVisible = true
    }

    /// 伏せていた予定を表に戻す。演出を挟むゲームが、リザルトに移った出口で呼ぶ（#1143）。
    ///
    /// 予定が無いときに呼んでも害は無い。
    public func resultDidBecomeVisible() {
        isDeferredUntilResultIsVisible = false
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
                issuedRequestID = nil
                return
            }
        }

        guard pendingRequestID != nil else { return }
        issuedRequestID = nil
        // 出たかどうかは OS しか知らないため、呼んだ時点で記録する（条件3〜5の起点）。
        log.markReviewRequested(at: now(), version: appVersion)
        request()
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）。発火条件（勝利数・期間・バージョン）を通さずに予定を立てる。
    /// 実機の条件は生涯1〜2回のため、シミュレータでダイアログを確認する手段がこれしかない。
    public func simulateRequest() {
        issuedCount += 1
        issuedRequestID = issuedCount
    }
    #endif
}
