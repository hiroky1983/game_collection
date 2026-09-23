/// ゲーム画面の世代（#653）。ハブへ戻るたびに 1 つ進む。
///
/// リワード広告のロード〜視聴のあいだも画面は操作でき、ハブへ戻ると Model は捨てられて
/// 次に開いたときに作り直される。一方で広告の完了を待っている `Task` は**古い Model を
/// 強参照したまま生き残る**ため、視聴完了後にその古い Model が救済を適用し、`PlayLog` や
/// `SnapshotStore` といった **gameID で共有されている置き場**を新しい対局の裏で書き換える。
///
/// 各 Model が持つ局の通し番号（麻雀の `gameSerial` 等）は**同じ Model の中**で局が
/// 入れ替わった場合しか弾けない。Model そのものが入れ替わる経路を塞ぐには、Model より
/// 長生きする場所に世代を置いて突き合わせる必要がある。それがこの型。
///
/// 進めるのは `GameServices.gameDidLeave(gameID:)` の 1 か所だけ（ハブの `onChange(of: path)`
/// が唯一の発火点）。照合は `RewardedRescue` と、広告を自分で抱えている 3 つの Model
/// （麻雀・ブラックジャック・ポーカー）が行う。
@MainActor
public final class GameScreenGeneration {
    public private(set) var current = 0

    /// `GameServices.init` の既定値として書けるように nonisolated にする
    /// （既定値は呼び出し側の文脈で評価されるため、MainActor 限定だとテストの
    /// 非 MainActor な組み立てが通らなくなる）。初期値 0 は隔離を必要としない。
    nonisolated public init() {}

    /// ゲーム画面から離れた。
    public func advance() { current += 1 }
}

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
    /// ゲーム画面の世代（#653）。`GameServices` は値型だがこれは参照型なので、
    /// コピーされても同じ世代を指す（各ゲームへ渡った先で別々に進むことはない）。
    public let screenGeneration: GameScreenGeneration
    /// 中断したゲームのお知らせ（#663）。テスト・プレビューでは nil（予約しない）。
    public let reminders: ResumeReminderService?
    /// よく遊んでいたのに最近開いていないゲームへの再エンゲージメント通知（#1193）。
    /// テスト・プレビューでは nil（予約しない）。
    public let reengagement: ReengagementReminderService?

    public init(
        snapshots: SnapshotStore,
        ads: AdService,
        feedback: FeedbackService = NoopFeedbackService(),
        recommendations: RecommendationService? = nil,
        review: ReviewRequestService? = nil,
        playLog: PlayLog? = nil,
        analytics: GameAnalytics? = nil,
        gameCenter: GameCenterReporter? = nil,
        screenGeneration: GameScreenGeneration = GameScreenGeneration(),
        reminders: ResumeReminderService? = nil,
        reengagement: ReengagementReminderService? = nil
    ) {
        self.snapshots = snapshots
        self.ads = ads
        self.feedback = feedback
        self.recommendations = recommendations
        self.review = review
        self.playLog = playLog
        self.analytics = analytics
        self.gameCenter = gameCenter
        self.screenGeneration = screenGeneration
        self.reminders = reminders
        self.reengagement = reengagement
    }

    /// ゲーム画面を開いて新規にプレイが始まったときに各 Model から呼ぶ（#158）。
    /// 冪等なので、再描画で Model が作り直されても `game_start` は増えない。
    /// 中断スナップショットから復元したときは**呼ばない**（新しいプレイではないため）。
    ///
    /// - Parameters:
    ///   - level: 難易度・段階（#500）。持たないゲームは省略し、`level` の鍵ごと送らない。
    ///   - mode: 遊び方の区分（#783・#820。値の全量は `AnalyticsMode`）。持たないゲームは省略。
    @MainActor
    public func gameDidStart(gameID: String, level: AnalyticsLevel? = nil, mode: AnalyticsMode? = nil) {
        analytics?.startPlay(gameID: gameID, level: level, mode: mode)
        reminders?.gameDidBeginPlay(gameID: gameID)
    }

    /// 「新しいゲーム」「次のラウンド」で次のプレイを始めたときに各 Model から呼ぶ（#158）。
    /// 冪等ではなく、呼ぶたびに1プレイとして数える。
    ///
    /// 前のプレイが未決着のまま捨てられていれば、始め直す前に `game_end`（`quit`）が出る（#500）。
    @MainActor
    public func gameDidRestart(gameID: String, level: AnalyticsLevel? = nil, mode: AnalyticsMode? = nil) {
        analytics?.restartPlay(gameID: gameID, level: level, mode: mode)
        reminders?.gameDidBeginPlay(gameID: gameID)
    }

    /// そのプレイで**1手指した**（盤面が動いた）ときに各 Model から呼ぶ（#500）。冪等。
    ///
    /// この1点だけが「捨てたら途中離脱として数える盤面か」を決める。配っただけ・開いただけの
    /// 盤面を捨てても離脱には数えない（ソリティア #397 の敗北記録と同じ境目）。
    @MainActor
    public func gameDidProgress(gameID: String) {
        analytics?.recordProgress(gameID: gameID)
        reminders?.gameDidBeginPlay(gameID: gameID)
    }

    /// 無料ヒントを**1回使った**ときに各 Model から呼ぶ（#1326）。`game_end` の `hints_used` に載る。
    ///
    /// 途中離脱の `game_end` は Model を経由せず共通経路で出るため、決着時に値を渡す形ではなく
    /// 使うたびにここへ伝えて `GameAnalytics` に覚えさせる。
    @MainActor
    public func gameDidUseHint(gameID: String) {
        analytics?.recordHintUsed(gameID: gameID)
    }

    /// この局は**画面を離れたら失われる**ことを各 Model から伝える（#500）。
    ///
    /// 既定の判定は「中断データが在る = 続きから戻れる」（`gameDidLeave`）だが、中断データを
    /// 記録の控えとして使っていて局そのものは復元しないゲームは、これを呼んで打ち消す。
    @MainActor
    public func gameWillNotResume(gameID: String) {
        analytics?.markUnresumable(gameID: gameID)
    }

    /// 決着済みの局を**見返しとして復元した**ことを各 Model から伝える（#663）。
    ///
    /// 将棋・チェスは終局後の検討画面を中断データに残すため、中断データが在っても続きは無い。
    /// 復元では記録を二重に数えないよう `gameDidFinish` を呼ばないので、決着済みであることを別に伝え、
    /// 「途中のままです」のお知らせを予約させない。
    /// 麻雀は、その先が終局になる局のリザルト（記録は「結果を見る」で付ける）に入ったときと、
    /// そこから復元したときにも呼ぶ（#811）。
    @MainActor
    public func gameDidRestoreFinished(gameID: String) {
        reminders?.gameDidFinish(gameID: gameID)
    }

    /// ゲーム画面から離れたときにハブから呼ぶ（#158）。次に開いたときを新しいプレイとして数え直す。
    ///
    /// 中断データが残っているかをここで `SnapshotStore` に聞き、**休憩（あとで続きから再開できる）**と
    /// **離脱（盤面を捨てた）**を切り分ける（#500）。呼び出し側（ハブ）は判定を持たない。
    @MainActor
    public func gameDidLeave(gameID: String) {
        let hasSnapshot = snapshots.exists(for: gameID)
        analytics?.leaveGame(gameID: gameID, isResumable: hasSnapshot)
        // 中断データを持って戻ったときだけ、1 日ほど後のお知らせを予約する（#663）。
        reminders?.gameDidLeave(gameID: gameID, hasSnapshot: hasSnapshot)
        // 画面の世代を進める（#653）。次に開いたときは別の Model になるので、いま広告の
        // 完了を待っている救済は、視聴が終わっても適用してはいけない。
        screenGeneration.advance()
    }

    /// ハブからゲーム画面を開いたときにハブから呼ぶ（#659）。`game_open` を送り、そのゲームの
    /// 中断のお知らせを取り消す（#663）。プレイの数え方にも画面の世代にも触らない。
    ///
    /// - Parameters:
    ///   - position: 導線の中での位置（1 始まり）。並びを持たない導線では nil。
    ///   - resume: 開いた時点で「続きから」だったか。**タップした時点の値**を渡す
    ///     （開いた後に聞くと、ゲーム側の復元処理と順序が前後しうるため）。
    @MainActor
    public func gameDidOpen(gameID: String, source: GameOpenSource, position: Int?, resume: Bool) {
        analytics?.recordGameOpen(gameID: gameID, source: source, position: position, resume: resume)
        reminders?.gameDidOpen(gameID: gameID)
        reengagement?.gameDidOpen(gameID: gameID)
    }

    /// リザルトの共有ボタンを押したときに呼ぶ（#1043）。`share_tap` を送るだけで、プレイの数え方にも
    /// 画面の世代にも触らない。呼ぶのは `RecordLabel` の共有ボタンの 1 か所（ハブが `RecordShareContext` で配る）。
    @MainActor
    public func gameDidTapShare(gameID: String) {
        analytics?.recordShareTap(gameID: gameID)
    }

    /// リワード広告を出し、**要求した時点で** `reward_request`、**視聴完了したときだけ**
    /// `reward_ad` を送る（#500 / #659）。
    ///
    /// 各ゲームは `services.ads.showRewardedAd()` を直接呼ばず必ずここを通す。広告を出す判断と
    /// 計測を1か所に束ねることで、面が増えるたびに計測を付け忘れる経路を作らない。
    ///
    /// - Returns: 視聴完了なら true。ロード失敗・途中で閉じた場合は false（`AdService` と同じ）。
    @MainActor
    public func showRewardedAd(gameID: String, purpose: RewardPurpose) async -> Bool {
        // 要求は広告の結果を待つ前に送る。ロード失敗や途中で閉じた回こそ数えたいので、
        // 結果を見てから送ると完了率の分母から落ちる。
        analytics?.recordRewardRequest(gameID: gameID, purpose: purpose)
        guard await ads.showRewardedAd() else { return false }
        analytics?.recordRewardAd(gameID: gameID, purpose: purpose)
        return true
    }

    /// リワード広告の提示が終わったときに `RewardedRescue` から呼ぶ（#780）。`reward_offer` を送る。
    ///
    /// - Parameter accepted: 広告ボタンを押して終わったか。押したときは**広告を出す前に**呼ぶこと
    ///   （出したあとだと先読みの広告が使われて、`not_ready` と区別できなくなる）。
    @MainActor
    public func rewardOfferDidEnd(gameID: String, purpose: RewardPurpose, accepted: Bool) {
        let result: RewardOfferResult = accepted
            ? (ads.isRewardedAdReady ? .accepted : .notReady)
            : .declined
        analytics?.recordRewardOffer(gameID: gameID, purpose: purpose, result: result)
    }

    /// ゲームでミスした（穴に落ちた・ぶつかった）ときに各 Model から呼ぶ（#796）。
    ///
    /// 決着ではない（`gameDidFinish` は呼ばない）。解析が原因を覚えておき、そのプレイの
    /// `game_end` に「最後のミスの原因」（`cause`）として載せる。イベントの種類は増やさない。
    @MainActor
    public func gameDidMiss(gameID: String, cause: AnalyticsEndCause) {
        analytics?.recordMissCause(gameID: gameID, cause: cause)
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
        // 決着した局には「途中のままです」を予約しない（#663）。将棋・チェスは終局後も見返しを
        // 中断データに残すため、中断データの有無だけでは途中の局と見分けられない。
        reminders?.gameDidFinish(gameID: gameID)
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

    /// 決着とリザルトのあいだに演出を挟むゲーム（チャリンコおじさんのゴールの演出・世界の締め）が、
    /// **演出の局面に入る入口**で呼ぶ（#1143）。評価リクエストは予定だけ立てて伏せ、
    /// `resultDidBecomeVisible()` を呼ぶまで出さない。記録・解析・順位表の順序（#1092）は変えない。
    @MainActor
    public func deferReviewRequestUntilResultIsVisible() {
        review?.deferUntilResultIsVisible()
    }

    /// 上の演出が終わってリザルトに移った瞬間に呼ぶ（#1143）。伏せていなければ何も起きない。
    @MainActor
    public func resultDidBecomeVisible() {
        review?.resultDidBecomeVisible()
    }
}
