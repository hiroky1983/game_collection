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

/// プレイ履歴の最小限の記録。
///
/// 保存先は端末内の `UserDefaults` のみ（サーバ送信なし・iCloud 同期なし）。既存の `GameSettings`
/// （`gameOrder_v1` / `hiddenGames_v1`）と同じ場所・同じ命名規則。
///
/// **盤面・スコア・棋譜といったゲームの状態は一切残さない**。持つのは下の5キーだけで、いずれも
/// 追記型ログではなく同じ値の上書きのため、何回遊んでもキー数もデータ量も増えない
/// （`playedGameIDs` だけは増えるが、上限は登録ゲーム数でプレイ回数には依存しない）。
@MainActor
public final class PlayLog {
    public static let totalFinishesKey  = "playLog_totalFinishes_v1"
    public static let playedGameIDsKey  = "playLog_playedGameIDs_v1"
    public static let lastShownCountKey = "recommend_lastShownCount_v1"
    public static let lastShownAtKey    = "recommend_lastShownAt_v1"
    public static let ignoredStreakKey  = "recommend_ignoredStreak_v1"

    /// このクラスが書き込むキーの全量。「プレイ記録を消去」と、キーが増えていないことの検証に使う。
    public static let allKeys = [
        totalFinishesKey, playedGameIDsKey, lastShownCountKey, lastShownAtKey, ignoredStreakKey,
    ]

    private let defaults: UserDefaults

    /// 通算のゲーム終了回数（全ゲーム合算・勝敗を問わない）。
    public private(set) var totalFinishes: Int
    /// 一度でも終局まで遊んだ gameID。
    public private(set) var playedGameIDs: Set<String>
    private var lastShownCount: Int
    private var lastShownAt: Date?
    private var ignoredStreak: Int

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.totalFinishes = defaults.integer(forKey: Self.totalFinishesKey)
        self.playedGameIDs = Set(defaults.stringArray(forKey: Self.playedGameIDsKey) ?? [])
        self.lastShownCount = defaults.integer(forKey: Self.lastShownCountKey)
        // キーが無い = 一度も提示していない。0 秒（1970年）と区別するため object で見る。
        self.lastShownAt = (defaults.object(forKey: Self.lastShownAtKey) as? Double)
            .map { Date(timeIntervalSince1970: $0) }
        self.ignoredStreak = defaults.integer(forKey: Self.ignoredStreakKey)
    }

    public var state: RecommendationState {
        RecommendationState(
            totalFinishes: totalFinishes,
            lastShownCount: lastShownCount,
            lastShownAt: lastShownAt,
            ignoredStreak: ignoredStreak
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

    /// 設定の「プレイ記録を消去」から呼ぶ。保存した5キーをすべて削除する。
    public func clear() {
        for key in Self.allKeys { defaults.removeObject(forKey: key) }
        totalFinishes = 0
        playedGameIDs = []
        lastShownCount = 0
        lastShownAt = nil
        ignoredStreak = 0
    }
}
