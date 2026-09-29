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
    /// 条件3: 前回リクエストからの最小間隔（60日）。OS 側の上限（365日で3回）には、
    /// 前回から 20 勝の歯止め（条件4）と合わせても当たらない（#1471 で 120 日から短縮）。
    public static let minimumElapsed: TimeInterval = 60 * 24 * 60 * 60
    /// 条件4: 前回リクエストからの最小勝利数。期間だけでなく利用実態でも間隔を担保する。
    public static let minimumWinsSinceLast = 20

    /// 条件2〜5 を満たすか。
    public static func shouldRequest(
        state: ReviewRequestState,
        currentVersion: String,
        now: Date
    ) -> Bool {
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
}
