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
    /// App Store のレビュー記入画面を直接開く URL。感想カードの「App Store で感想を書く」と、設定の
    /// 「アプリを評価する」（#1471）が同じものを開く。`requestReview` は OS の上限（365 日で 3 回）に達すると何も出ない。
    public static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6781719499?action=write-review")!

    public let log: PlayLog
    private let appVersion: String
    private let now: () -> Date
    /// 条件6: リザルト表示からこれだけ待ってから呼ぶ（連続プレイの操作を遮らない）。
    private let delay: Duration
    /// 評価のお願いの解析（#3061）。nil なら送らない（テスト・プレビュー）。
    private let analytics: GameAnalytics?

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

    /// 新しいゲームの感想カード（#3061）の予定。`pendingRequestID` と同じ作りで、演出中は伏せる。
    public var pendingNewGameCardID: Int? { isDeferredUntilResultIsVisible ? nil : issuedNewGameCardID }
    private var issuedNewGameCardID: Int?

    /// 感想カードを表示中か。画面側のオーバーレイがこの値を見る。
    public var isNewGameCardPresented = false

    public init(
        log: PlayLog,
        appVersion: String,
        now: @escaping () -> Date = { Date() },
        delay: Duration = .seconds(1),
        analytics: GameAnalytics? = nil
    ) {
        self.analytics = analytics
        self.log = log
        self.appVersion = appVersion
        self.now = now
        self.delay = delay
    }

    /// 決着したときに各ゲームの Model から呼ぶ。
    ///
    /// - Parameters:
    ///   - outcome: 決着の種類。勝利以外は勝利数を数えない（新しいゲームの感想カードの判定だけは勝敗を問わない）。
    ///   - isHighlight: その勝ちが「見せ場」か（#1471）。**勝利数は見せ場でなくても数える**
    ///     （条件2・4は従来どおり勝利で数える）が、リクエストの予定を立てるのは見せ場のときだけ。
    ///   - gameID: 決着したゲーム。新着のゲームかを見るのに使う（#3061）。省略すると感想カードの対象にならない。
    /// - Returns: 評価リクエスト（または感想カード）を出す予定になったか。同じリザルトに出るレコメンド（#52）を
    ///   next回に送るかの判断に使う（競合したら評価のお願いを優先する）。
    @discardableResult
    public func gameDidFinish(outcome: GameOutcome, isHighlight: Bool = true, gameID: String = "") -> Bool {
        // 条件1: 勝利・クリアの直後のみ（さらに見せ場に絞る。下の `isHighlight`）。敗北・投了・ゲームオーバーでは勝利数も増やさない。
        if outcome == .win { log.recordWin() }
        // 演出の途中で画面を離れると伏せ（#1143）が残る。決着のたびに必ず外すことで、
        // それ以降どの画面でも二度と出ない状態にならないようにする。演出を挟むゲームは
        // この直後に `deferUntilResultIsVisible()` を呼んで伏せ直す（`RunnerModel`）。
        isDeferredUntilResultIsVisible = false

        // 新しいゲームの感想カード（#3061）は条件1〜6 を飛び越える。通常の評価リクエストより優先し、
        // 同じリザルトで二重に聞かない。
        if issuedNewGameCardID != nil { return true }
        if ReviewRequestPolicy.shouldAskAboutNewGame(state: log.reviewState, gameID: gameID) {
            issuedRequestID = nil
            issuedCount += 1
            issuedNewGameCardID = issuedCount
            return true
        }

        guard outcome == .win else { return false }
        // すでに予定が立っている間は従来どおり true（同じリザルトのレコメンドを抑え続ける）。
        guard issuedRequestID == nil else { return true }
        // 見せ場でない勝ちは、新しく予定を立てない（予定は見せ場で立てたものだけ）。
        guard isHighlight else { return false }
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
        analytics?.recordReviewPrompt(kind: .regular, step: .osRequested)
        request()
    }

    /// 予定された感想カード（#3061）を出す。画面側（`reviewRequestPrompt`）から呼ぶ。
    ///
    /// 1.0秒待つ前に画面を離れたらキャンセルされ、予定は破棄する（出していないので「出し済み」にも数えない）。
    public func presentPendingNewGameCard() async {
        guard pendingNewGameCardID != nil else { return }
        if delay > .zero {
            do {
                try await Task.sleep(for: delay)
            } catch {
                issuedNewGameCardID = nil
                return
            }
        }
        guard pendingNewGameCardID != nil else { return }
        issuedNewGameCardID = nil
        // 一人につき一度きり。出した時点で記録する。
        log.markNewGameCardAsked()
        isNewGameCardPresented = true
        analytics?.recordReviewPrompt(kind: .newGameCard, step: .shown)
    }

    /// 感想カードの「App Store で感想を書く」を押した。「答えた人」として記録し、以後 A・B とも出さない。
    public func newGameCardWriteReviewTapped() {
        guard isNewGameCardPresented else { return }
        isNewGameCardPresented = false
        log.markReviewAnswered()
        analytics?.recordReviewPrompt(kind: .newGameCard, step: .writeReview)
    }

    /// 感想カードの「あとで」、または背景タップ・画面を離れて閉じた。答えた人には数えない。
    public func newGameCardDismissed() {
        guard isNewGameCardPresented else { return }
        isNewGameCardPresented = false
        analytics?.recordReviewPrompt(kind: .newGameCard, step: .later)
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）。発火条件（勝利数・期間・バージョン）を通さずに予定を立てる。
    /// 実機の条件は生涯1〜2回のため、シミュレータでダイアログを確認する手段がこれしかない。
    public func simulateRequest() {
        issuedCount += 1
        issuedRequestID = issuedCount
    }

    /// 撮影用（DEBUG 限定）。条件を通さずに感想カードの予定を立てる。
    public func simulateNewGameCard() {
        issuedCount += 1
        issuedNewGameCardID = issuedCount
    }
    #endif
}
