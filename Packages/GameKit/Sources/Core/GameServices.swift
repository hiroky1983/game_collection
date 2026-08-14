/// 各ゲームに注入する横断サービス束。MVP では永続化と広告のみ。
public struct GameServices {
    public let snapshots: SnapshotStore
    public let ads: AdService
    public let feedback: FeedbackService
    /// ゲーム間レコメンド。テスト・プレビューでは nil（何も起きない）。
    public let recommendations: RecommendationService?
    /// 評価リクエスト。テスト・プレビューでは nil（何も起きない）。
    public let review: ReviewRequestService?
    /// プレイ記録（#115）。テスト・プレビューでは nil（記録しない）。
    public let playLog: PlayLog?

    public init(
        snapshots: SnapshotStore,
        ads: AdService,
        feedback: FeedbackService = NoopFeedbackService(),
        recommendations: RecommendationService? = nil,
        review: ReviewRequestService? = nil,
        playLog: PlayLog? = nil
    ) {
        self.snapshots = snapshots
        self.ads = ads
        self.feedback = feedback
        self.recommendations = recommendations
        self.review = review
        self.playLog = playLog
    }

    /// ゲームが決着したときに各 Model から呼ぶ唯一の入口。
    ///
    /// 同じリザルト画面に出る2つの依頼（評価リクエスト #53 / レコメンド #52）の競合を
    /// ここ1か所で調停する。**評価リクエストを優先**し、その回のレコメンドは提示カウントを
    /// 消費せず次回に送る。
    ///
    /// - Parameter score: そのゲームの成績（#115）。省略すると勝敗だけが記録される。
    /// - Returns: 更新後の自己ベストと更新内訳。リザルトに `RecordLabel` で 1 行出すのに使う。
    ///   記録を持たない構成（テスト・プレビュー）では nil。
    @MainActor
    @discardableResult
    public func gameDidFinish(
        gameID: String,
        outcome: GameOutcome,
        score: GameScore = GameScore()
    ) -> RecordResult? {
        // 記録が先。リザルトは戻り値をそのまま描画するため、他の依頼より前に確定させる。
        let result = playLog?.recordResult(gameID: gameID, outcome: outcome, score: score)
        let willRequestReview = review?.gameDidFinish(outcome: outcome) ?? false
        recommendations?.gameDidFinish(gameID: gameID, isSuppressedByOtherPrompt: willRequestReview)
        return result
    }
}
