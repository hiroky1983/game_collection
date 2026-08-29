import Foundation

/// レコメンドの提示可否を決めるのに必要な状態だけを切り出した値。
/// 判定を純粋関数（`RecommendationPolicy`）に閉じ込め、永続化と分離してテストできるようにする。
public struct RecommendationState: Equatable, Sendable {
    /// 通算のゲーム終了回数（全ゲーム合算）。
    public var totalFinishes: Int
    /// 前回提示した時点の終了回数。
    public var lastShownCount: Int
    /// 前回提示した時刻。一度も提示していなければ nil。
    public var lastShownAt: Date?
    /// 提示したのにタップされなかった連続回数。
    public var ignoredStreak: Int

    public init(
        totalFinishes: Int = 0,
        lastShownCount: Int = 0,
        lastShownAt: Date? = nil,
        ignoredStreak: Int = 0
    ) {
        self.totalFinishes = totalFinishes
        self.lastShownCount = lastShownCount
        self.lastShownAt = lastShownAt
        self.ignoredStreak = ignoredStreak
    }
}

/// 評価リクエストの発火可否を決めるのに必要な状態だけを切り出した値。
/// `RecommendationState` と同じ考えで、判定を純粋関数（`ReviewRequestPolicy`）に閉じ込める。
public struct ReviewRequestState: Equatable, Sendable {
    /// 通算の勝利・クリア回数（全ゲーム合算）。
    public var totalWins: Int
    /// 前回リクエストした時刻。一度もリクエストしていなければ nil。
    public var lastRequestedAt: Date?
    /// 前回リクエストした時点の勝利数。
    public var lastRequestedWins: Int
    /// 前回リクエストしたときのアプリバージョン。一度もリクエストしていなければ nil。
    public var lastRequestedVersion: String?

    public init(
        totalWins: Int = 0,
        lastRequestedAt: Date? = nil,
        lastRequestedWins: Int = 0,
        lastRequestedVersion: String? = nil
    ) {
        self.totalWins = totalWins
        self.lastRequestedAt = lastRequestedAt
        self.lastRequestedWins = lastRequestedWins
        self.lastRequestedVersion = lastRequestedVersion
    }
}

/// プレイ履歴の最小限の記録。
///
/// 保存先は端末内の `UserDefaults` のみ（サーバ送信なし・iCloud 同期なし）。既存の `GameSettings`
/// （`gameOrder_v1` / `hiddenGames_v1`）と同じ場所・同じ命名規則。
///
/// **盤面・棋譜といったゲームの途中状態は一切残さない**。持つのは下の11キー
/// （レコメンド #52 の5キー + 評価リクエスト #53 の4キー + プレイ記録 #115 の1キー
/// + 遊び方ガイド #118 の1キー）だけで、
/// いずれも追記型ログではなく同じ値の上書きのため、何回遊んでもキー数もデータ量も増えない
/// （`playedGameIDs` と `records` と `guidedGameIDs` だけは増えるが、上限は登録ゲーム数
/// （+ 難易度数）でプレイ回数には依存しない）。
@MainActor
public final class PlayLog {
    public static let totalFinishesKey  = "playLog_totalFinishes_v1"
    public static let playedGameIDsKey  = "playLog_playedGameIDs_v1"
    public static let lastShownCountKey = "recommend_lastShownCount_v1"
    public static let lastShownAtKey    = "recommend_lastShownAt_v1"
    public static let ignoredStreakKey  = "recommend_ignoredStreak_v1"

    public static let totalWinsKey            = "playLog_totalWins_v1"
    public static let lastRequestedAtKey      = "review_lastRequestedAt_v1"
    public static let lastRequestedWinsKey    = "review_lastRequestedWins_v1"
    public static let lastRequestedVersionKey = "review_lastRequestedVersion_v1"

    /// ゲーム間レコメンド（#52）が書き込むキー。
    public static let recommendationKeys = [
        totalFinishesKey, playedGameIDsKey, lastShownCountKey, lastShownAtKey, ignoredStreakKey,
    ]

    /// 評価リクエスト（#53）が書き込むキー。
    public static let reviewRequestKeys = [
        totalWinsKey, lastRequestedAtKey, lastRequestedWinsKey, lastRequestedVersionKey,
    ]

    /// ゲーム別のプレイ記録（#115）。全ゲームぶんを JSON にまとめて**1キー**に入れる。
    /// ゲームごとにキーを切ると登録ゲームが増えるたびにキーが増え、消去漏れの温床になるため。
    public static let recordsKey = "playLog_records_v1"

    /// プレイ記録（#115）が書き込むキー。
    public static let playRecordKeys = [recordsKey]

    /// 「遊び方」のミニガイド（#118）を出し終えた gameID。ゲームごとにキーを切らず**1キー**に配列で入れる
    /// （`playedGameIDs` と同じ方針。登録ゲームが増えてもキーは増えない）。
    public static let guidedGameIDsKey = "playLog_guidedGameIDs_v1"

    /// 遊び方ガイド（#118）が書き込むキー。
    public static let howToPlayKeys = [guidedGameIDsKey]

    /// このクラスが書き込むキーの全量。「プレイ記録を消去」と、キーが増えていないことの検証に使う。
    public static let allKeys = recommendationKeys + reviewRequestKeys + playRecordKeys + howToPlayKeys

    private let defaults: UserDefaults

    /// 通算のゲーム終了回数（全ゲーム合算・勝敗を問わない）。
    public private(set) var totalFinishes: Int
    /// 一度でも終局まで遊んだ gameID。
    public private(set) var playedGameIDs: Set<String>
    private var lastShownCount: Int
    private var lastShownAt: Date?
    private var ignoredStreak: Int

    /// 通算の勝利・クリア回数（全ゲーム合算）。
    public private(set) var totalWins: Int
    private var lastRequestedAt: Date?
    private var lastRequestedWins: Int
    private var lastRequestedVersion: String?

    /// ゲーム別の記録。キーは `recordKey(gameID:variant:)`。
    public private(set) var records: [String: PlayRecord]

    /// 初回のミニガイド（#118）を出し終えた gameID。
    public private(set) var guidedGameIDs: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.totalFinishes = defaults.integer(forKey: Self.totalFinishesKey)
        self.playedGameIDs = Set(defaults.stringArray(forKey: Self.playedGameIDsKey) ?? [])
        self.lastShownCount = defaults.integer(forKey: Self.lastShownCountKey)
        // キーが無い = 一度も提示していない。0 秒（1970年）と区別するため object で見る。
        self.lastShownAt = (defaults.object(forKey: Self.lastShownAtKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        self.ignoredStreak = defaults.integer(forKey: Self.ignoredStreakKey)

        self.totalWins = defaults.integer(forKey: Self.totalWinsKey)
        self.lastRequestedAt = (defaults.object(forKey: Self.lastRequestedAtKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        self.lastRequestedWins = defaults.integer(forKey: Self.lastRequestedWinsKey)
        self.lastRequestedVersion = defaults.string(forKey: Self.lastRequestedVersionKey)

        self.guidedGameIDs = Set(defaults.stringArray(forKey: Self.guidedGameIDsKey) ?? [])

        // 壊れた JSON（旧形式・書き込み途中の中断）で起動できなくならないよう、失敗したら空に倒す。
        // 記録は再取得できない代わりに失っても遊べるため、可用性を優先する。
        if let data = defaults.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([String: PlayRecord].self, from: data) {
            self.records = decoded
        } else {
            self.records = [:]
        }
    }

    public var state: RecommendationState {
        RecommendationState(
            totalFinishes: totalFinishes,
            lastShownCount: lastShownCount,
            lastShownAt: lastShownAt,
            ignoredStreak: ignoredStreak
        )
    }

    public var reviewState: ReviewRequestState {
        ReviewRequestState(
            totalWins: totalWins,
            lastRequestedAt: lastRequestedAt,
            lastRequestedWins: lastRequestedWins,
            lastRequestedVersion: lastRequestedVersion
        )
    }

    /// ゲームを1つ遊び終えた（リザルトが表示された）ときに呼ぶ。
    public func recordFinish(gameID: String) {
        totalFinishes += 1
        defaults.set(totalFinishes, forKey: Self.totalFinishesKey)
        if playedGameIDs.insert(gameID).inserted {
            // 並びを固定して保存し、同じ集合なら常に同じバイト列になるようにする。
            defaults.set(playedGameIDs.sorted(), forKey: Self.playedGameIDsKey)
        }
    }

    /// 勝利・クリアで終わったときに呼ぶ（敗北・投了・ゲームオーバーでは呼ばない）。
    public func recordWin() {
        totalWins += 1
        defaults.set(totalWins, forKey: Self.totalWinsKey)
    }

    /// 評価リクエストを呼んだときに記録する。
    ///
    /// `SKStoreReviewController` 系の API は OS 側で表示可否が決まり、**実際に出たかをアプリから
    /// 知る手段が無い**。そのため「呼んだ時点」で記録する（記録しないと握り潰されるたびに呼び続ける）。
    public func markReviewRequested(at date: Date, version: String) {
        lastRequestedAt = date
        lastRequestedWins = totalWins
        lastRequestedVersion = version
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastRequestedAtKey)
        defaults.set(totalWins, forKey: Self.lastRequestedWinsKey)
        defaults.set(version, forKey: Self.lastRequestedVersionKey)
    }

    /// レコメンドを提示したときに呼ぶ。
    ///
    /// 提示は既定で「無視された」として数え、タップされた時点で `markAccepted()` が 0 に戻す。
    /// ×で閉じた場合と黙って戻った場合を区別せずに済み、判定が状態だけで決まる（テストで固定できる）。
    public func markShown(at date: Date) {
        lastShownCount = totalFinishes
        lastShownAt = date
        ignoredStreak += 1
        defaults.set(lastShownCount, forKey: Self.lastShownCountKey)
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastShownAtKey)
        defaults.set(ignoredStreak, forKey: Self.ignoredStreakKey)
    }

    /// 提示したレコメンドがタップされたときに呼ぶ。
    public func markAccepted() {
        ignoredStreak = 0
        defaults.set(ignoredStreak, forKey: Self.ignoredStreakKey)
    }

    // MARK: - ゲーム別の記録（#115）

    /// `records` のキー。区分（マインスイーパーの難易度）があるゲームは区分ごとに 1 件持つ。
    public static func recordKey(gameID: String, variant: String?) -> String {
        guard let variant, !variant.isEmpty else { return gameID }
        return "\(gameID)#\(variant)"
    }

    /// 1 件ぶんの記録を取り出す。まだ遊んでいなければ nil。
    public func record(gameID: String, variant: String? = nil) -> PlayRecord? {
        records[Self.recordKey(gameID: gameID, variant: variant)]
    }

    /// そのゲームの全区分の記録。キー順で安定させる（表示のちらつき防止）。
    public func records(gameID: String) -> [PlayRecord] {
        let prefix = "\(gameID)#"
        return records
            .filter { $0.key == gameID || $0.key.hasPrefix(prefix) }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    /// ハブのカードに出す 1 行。記録がまだ無ければ nil。
    public func summaryLine(gameID: String) -> String? {
        RecordFormat.hubLine(records(gameID: gameID))
    }

    /// ゲームごとの最終プレイ日時（#335）。区分があるゲームは最も新しいものを代表にする。
    ///
    /// 日付を持たない記録（この項目が入る前に保存されたもの）は含めない。呼び出し側は
    /// 「載っていない = いつ遊んだか分からないくらい前」として扱う。
    public var lastPlayedAtByGame: [String: Date] {
        var result: [String: Date] = [:]
        for (key, record) in records {
            guard let date = record.lastPlayedAt else { continue }
            let gameID = key.split(separator: "#", maxSplits: 1).first.map(String.init) ?? key
            if let existing = result[gameID], existing >= date { continue }
            result[gameID] = date
        }
        return result
    }

    /// 決着 1 回を記録して、更新後の記録と更新内訳を返す。
    ///
    /// 判定そのものは `PlayRecord.applying` に閉じ込め、ここは永続化だけを担う。
    @discardableResult
    public func recordResult(
        gameID: String,
        outcome: GameOutcome,
        score: GameScore,
        at date: Date = Date()
    ) -> RecordResult {
        let key = Self.recordKey(gameID: gameID, variant: score.variant)
        let result = PlayRecord.applying(outcome: outcome, score: score, to: records[key], at: date)
        records[key] = result.record
        persistRecords()
        return result
    }

    /// リワード広告のコンティニューで「その負けが無かったことになった」ときに呼ぶ。
    ///
    /// 2048・マインスイーパーは**同じ盤面のまま**再開するため、先に記録した敗北をそのままにすると
    /// 1回のプレイが2回（負け + 最終結果）として数えられる。決着の通知そのもの
    /// （`gameDidFinish`）はレコメンド #52・評価リクエスト #53 の発火点で従来どおり動かす必要があるため、
    /// 記録側だけをここで巻き戻す。
    ///
    /// - Note: **自己ベスト（スコア・タイム）は巻き戻さない**。コンティニュー前に実際に到達した
    ///   値なので取り消す理由がない。連勝も戻さないが、コンティニューを持つ2ゲームはどちらも
    ///   連勝を表示しない指標（スコア / 最短タイム）のため表示への影響はない。
    public func cancelLoss(gameID: String, variant: String? = nil) {
        let key = Self.recordKey(gameID: gameID, variant: variant)
        guard var record = records[key], record.plays > 0, record.losses > 0 else { return }
        record.plays -= 1
        record.losses -= 1
        records[key] = record
        persistRecords()
    }

    // MARK: - 遊び方のミニガイド（#118）

    /// そのゲームのミニガイドを既に出したか。
    public func hasShownGuide(for gameID: String) -> Bool {
        guidedGameIDs.contains(gameID)
    }

    /// ミニガイドを出したことを記録する。
    ///
    /// - Returns: 今回が初回だったか（true のときだけ画面に出す）。判定と記録を 1 回の呼び出しに
    ///   まとめてあるため、画面側が「読んでから書く」の間に二重表示することがない。
    @discardableResult
    public func markGuideShown(for gameID: String) -> Bool {
        guard guidedGameIDs.insert(gameID).inserted else { return false }
        // 並びを固定して保存し、同じ集合なら常に同じバイト列になるようにする。
        defaults.set(guidedGameIDs.sorted(), forKey: Self.guidedGameIDsKey)
        return true
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey)
    }

    /// 設定の「プレイ記録を消去」から呼ぶ。保存した10キーをすべて削除する。
    public func clear() {
        for key in Self.allKeys { defaults.removeObject(forKey: key) }
        totalFinishes = 0
        playedGameIDs = []
        lastShownCount = 0
        lastShownAt = nil
        ignoredStreak = 0
        totalWins = 0
        lastRequestedAt = nil
        lastRequestedWins = 0
        lastRequestedVersion = nil
        records = [:]
        guidedGameIDs = []
    }
}
