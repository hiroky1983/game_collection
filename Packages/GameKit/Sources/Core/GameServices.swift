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
    /// 解析イベントの送信（#158）。テスト・プレビューでは nil（送信しない）。
    public let analytics: GameAnalytics?
    /// Game Center のリーダーボード・実績（#289）。テスト・プレビューでは nil（送信しない）。
    public let gameCenter: GameCenterReporter?

    public init(
        snapshots: SnapshotStore,
        ads: AdService,
        feedback: FeedbackService = NoopFeedbackService(),
        recommendations: RecommendationService? = nil,
        review: ReviewRequestService? = nil,
        playLog: PlayLog? = nil,
        analytics: GameAnalytics? = nil,
        gameCenter: GameCenterReporter? = nil
    ) {
        self.snapshots = snapshots
        self.ads = ads
        self.feedback = feedback
        self.recommendations = recommendations
        self.review = review
        self.playLog = playLog
        self.analytics = analytics
        self.gameCenter = gameCenter
    }

    /// ゲーム画面を開いて新規にプレイが始まったときに各 Model から呼ぶ（#158）。
    /// 冪等なので、再描画で Model が作り直されても `game_start` は増えない。
    /// 中断スナップショットから復元したときは**呼ばない**（新しいプレイではないため）。
    @MainActor
    public func gameDidStart(gameID: String) {
        analytics?.startPlay(gameID: gameID)
    }

    /// 「新しいゲーム」「次のラウンド」で次のプレイを始めたときに各 Model から呼ぶ（#158）。
    /// 冪等ではなく、呼ぶたびに1プレイとして数える。
    @MainActor
    public func gameDidRestart(gameID: String) {
        analytics?.restartPlay(gameID: gameID)
    }

    /// ゲーム画面から離れたときにハブから呼ぶ（#158）。次に開いたときを新しいプレイとして数え直す。
    @MainActor
    public func gameDidLeave(gameID: String) {
        analytics?.leaveGame(gameID: gameID)
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
        // 解析（#158）。スコアの生値は渡さず、勝敗と経過秒だけを送る。
        analytics?.finishPlay(gameID: gameID, outcome: outcome)
        let willRequestReview = review?.gameDidFinish(outcome: outcome) ?? false
        recommendations?.gameDidFinish(gameID: gameID, isSuppressedByOtherPrompt: willRequestReview)
        // Game Center（#289）は**最後**に呼ぶ。実績の進捗は `PlayLog` の通算値から作るため、
        // 勝利数を増やす `review`（`recordWin`）と、遊んだゲームを記録する `recommendations`
        // （`recordFinish`）より後でないと 1 回ぶん古い値を送ることになる。
        // 記録を持たない構成（`playLog` が nil）では実績の進捗は 0 として扱い、
        // リーダーボードだけが動く（`GameCenterAchievements.progress` が 0 件を返す）。
        gameCenter?.gameDidFinish(
            gameID: gameID,
            outcome: outcome,
            score: score,
            totalWins: playLog?.totalWins ?? 0,
            playedGameCount: playLog?.playedGameIDs.count ?? 0
        )
        return result
    }
}
