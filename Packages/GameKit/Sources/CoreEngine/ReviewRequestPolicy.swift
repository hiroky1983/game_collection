import Foundation

/// 評価リクエスト（App Store のレビュー依頼）を出す条件。Issue #53 の表が原型で、#1471 で間隔と瞬間を見直した。
///
/// **方針は「見せ場（勝ちの中でも手応えのある瞬間）に、間隔を空けて」**。乱数を使わず状態だけで決まるので、
/// ユニットテストで全分岐を固定できる。
///
/// 条件1（勝利・クリアの直後、かつ見せ場のみ）は呼び出し側（`ReviewRequestService.gameDidFinish`）が、
/// 条件6（リザルトの1.0秒後・進行中には呼ばない）は画面側（`reviewRequestPrompt`）が担う。
public enum ReviewRequestPolicy {
    /// 条件2: 通算これだけ勝つまでは一度も出さない（判断できる程度に遊んだ人にだけ聞く）。
    public static let firstRequestWins = 5
    /// 条件3: 前回リクエストからの最小間隔（15日）。#1471 で 120 日から 60 日へ、#3061 で 15 日へ短縮した。
    /// OS 側の上限（365日で3回）には、出す側の歯止めではなく OS に任せる（会長決裁 2026-10-29）。
    public static let minimumElapsed: TimeInterval = 15 * 24 * 60 * 60
    /// 条件4: 前回リクエストからの最小勝利数（#3061 で 20 勝から 5 勝へ短縮）。期間だけでなく利用実態でも間隔を担保する。
    public static let minimumWinsSinceLast = 5

    /// 条件2〜5 を満たすか。「答えた人」（#3061）には常に出さない。
    public static func shouldRequest(
        state: ReviewRequestState,
        currentVersion: String,
        now: Date
    ) -> Bool {
        // 答えた人（新しいゲームの感想カードで App Store のレビュー画面を開いた人）には二度と出さない。
        guard !state.hasAnswered else { return false }
        // 条件2: 一桁の勝利数で聞かない。
        guard state.totalWins >= firstRequestWins else { return false }
        // 条件5: 同一バージョンでは1回まで（更新のたびに聞き直さない）。
        guard state.lastRequestedVersion != currentVersion else { return false }
        // 一度もリクエストしていなければ、条件2を満たした時点が初回。
        guard let lastRequestedAt = state.lastRequestedAt else { return true }
        // 条件4: 勝利数の歯止め。
        guard state.totalWins - state.lastRequestedWins >= minimumWinsSinceLast else { return false }
        // 条件3: 期間の歯止め。
        return now.timeIntervalSince(lastRequestedAt) >= minimumElapsed
    }

    /// 新しいゲームの感想カード（#3061）を出すか。条件1〜6 は飛び越える（勝敗も問わない）。
    ///
    /// 出すのは、答えていない人が新着のゲームを 1 局最後まで遊んだ直後に、**一人につき一度だけ**
    /// （版ごとにリセットしない）。
    public static func shouldAskAboutNewGame(
        state: ReviewRequestState,
        gameID: String,
        newGameIDs: Set<String> = NewGames.currentVersionIDs
    ) -> Bool {
        !state.hasAnswered && !state.hasAskedAboutNewGame && newGameIDs.contains(gameID)
    }

    /// 遊んだ日数の節目（#3078）。アプリを開いた日の合計がここに達した日に、勝敗を問わず評価のお願いを 1 回出す。
    public static let daysMilestones = [7, 30]

    /// 遊んだ日数の節目の評価のお願い（#3078）を出すなら、その節目（7 または 30）。出さなければ nil。
    ///
    /// 条件1〜6 の勝利数・バージョンの縛りは受けず、#3061 の共通仕様だけを効かせる:
    /// 答えた人には出さない（C）、前回のお願いから 15 日以内なら出さない（A）。
    /// 節目ごとに 1 回まで。間隔で出せなかった節目は、明けた最初の機会で出す。
    /// 7 日と 30 日がまとめて未消化なら、大きい方 1 回で両方を済ませる。
    public static func daysMilestoneToRequest(state: ReviewRequestState, now: Date) -> Int? {
        guard !state.hasAnswered else { return nil }
        if let lastRequestedAt = state.lastRequestedAt,
           now.timeIntervalSince(lastRequestedAt) < minimumElapsed { return nil }
        return daysMilestones.filter { state.openDays >= $0 && $0 > state.daysMilestoneAsked }.max()
    }
}
