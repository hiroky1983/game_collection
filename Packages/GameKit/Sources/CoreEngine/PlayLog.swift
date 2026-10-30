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
    /// 「答えた人」か（#3061）。新しいゲームの感想カードで「App Store で感想を書く」を押した人。
    /// iOS は実際に評価したかを教えないため、これを答えた印にして以後の評価のお願いを出さない。
    public var hasAnswered: Bool
    /// 新しいゲームの感想カード（#3061）を一度出したか。1 人につき一度きり（版ごとにリセットしない）。
    public var hasAskedAboutNewGame: Bool
    /// アプリを開いた日の数の合計（#3078）。1 日に何度開いても 1。
    public var openDays: Int
    /// 遊んだ日数の節目（7・30）のうち、評価のお願いを出し終えた最大のもの（#3078）。0 なら未。
    public var daysMilestoneAsked: Int

    public init(
        totalWins: Int = 0,
        lastRequestedAt: Date? = nil,
        lastRequestedWins: Int = 0,
        lastRequestedVersion: String? = nil,
        hasAnswered: Bool = false,
        hasAskedAboutNewGame: Bool = false,
        openDays: Int = 0,
        daysMilestoneAsked: Int = 0
    ) {
        self.openDays = openDays
        self.daysMilestoneAsked = daysMilestoneAsked
        self.hasAnswered = hasAnswered
        self.hasAskedAboutNewGame = hasAskedAboutNewGame
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
/// **盤面・棋譜といったゲームの途中状態は一切残さない**。持つのは下の13キー
/// （レコメンド #52 の5キー + 評価リクエスト #53 の4キー + プレイ記録 #115 の1キー
/// + 遊び方ガイド #118 の1キー + 新しいゲームの印 #723 の1キー + 連続プレイ日数 #1625 の1キー）だけで、
/// いずれも追記型ログではなく同じ値の上書きのため、何回遊んでもキー数もデータ量も増えない
/// （`playedGameIDs` と `records` と `guidedGameIDs` と `knownGameIDs` だけは増えるが、上限は登録ゲーム数
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
    /// 「答えた人」の印（#3061）。真偽値 1 個。端末内のみ・サーバ送信なし・「プレイ記録を消去」で消える。
    public static let reviewAnsweredKey       = "review_answered_v1"
    /// 新しいゲームの感想カードを出し済みの印（#3061）。真偽値 1 個。扱いは上と同じ。
    public static let newGameCardAskedKey     = "review_newGameCardAsked_v1"
    /// アプリを開いた日の数（#3078）。整数 1 個。`playDays`（決着した日・最大 366 個）とは別に数える
    /// （節目の 30 日を、決着の無い日を含めて数えるため）。端末内のみ・サーバ送信なし・「プレイ記録を消去」で消える。
    public static let openDaysKey             = "review_openDays_v1"
    /// 最後に数えた日の日番号（#3078）。整数 1 個。同じ日を二度数えないための印。扱いは上と同じ。
    public static let lastOpenDayKey          = "review_lastOpenDay_v1"
    /// 遊んだ日数の節目を出し終えた最大の値（#3078）。整数 1 個。扱いは上と同じ。
    public static let daysMilestoneAskedKey   = "review_daysMilestoneAsked_v1"

    /// ゲーム間レコメンド（#52）が書き込むキー。
    public static let recommendationKeys = [
        totalFinishesKey, playedGameIDsKey, lastShownCountKey, lastShownAtKey, ignoredStreakKey,
    ]

    /// 評価リクエスト（#53）が書き込むキー。
    public static let reviewRequestKeys = [
        totalWinsKey, lastRequestedAtKey, lastRequestedWinsKey, lastRequestedVersionKey,
    ]

    /// 評価のお願いの強化（#3061・#3078）が書き込むキー。いずれも真偽値か整数 1 個で、回数に依らずキー数・データ量は増えない。
    public static let reviewPromptKeys = [
        reviewAnsweredKey, newGameCardAskedKey, openDaysKey, lastOpenDayKey, daysMilestoneAskedKey,
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

    /// 前回ハブを出した時点の登録ゲーム ID（#723）。`guidedGameIDs` と同じく**1キー**に配列で入れる。
    public static let knownGameIDsKey = "playLog_knownGameIDs_v1"

    /// 新しいゲームの印（#723）が書き込むキー。
    public static let newGameKeys = [knownGameIDsKey]

    /// 遊んだ日の日番号（#1625・`PlayDayStreak.dayNumber`）。整数の配列を**1キー**に入れる。
    /// 1 日に何局遊んでも 1 個で、直近 `PlayDayStreak.maxStoredDays`（366）個を超えたら古い日から捨てる
    /// （最大 366 個の整数）。端末内のみ・サーバ送信なし・「プレイ記録を消去」で消える。
    public static let playDaysKey = "playLog_playDays_v1"

    /// 連続プレイ日数（#1625）が書き込むキー。
    public static let playDayKeys = [playDaysKey]

    /// 柵越えおじさんの蓄積（#1348・通算・集計・直近 20 挑戦）。ゲームのフォルダはここを参照できない（`Core` が上流）ので
    /// 文字列で持ち、`GameHomerunTests` が `HomerunStorage.recordsKey` と一致することを確かめる。
    /// **日次台帳（`homerun_ledger_v1`）は入れない**（消去で回数が補充される穴になるため）。
    /// 解除済みの実績（#1794・`homerun_achievements_v1`）も同じく消去の対象（Game Center に連携している人は、次に開いたときに
    /// Game Center 側の解除済みが端末へ戻る）。
    public static let homerunKeys = ["homerun_records_v1", "homerun_achievements_v1"]

    /// ゲームごとの「最後に選んだ開始条件」（#2611）。gameID → JSON の辞書を**1キー**に入れる。
    /// 中断データ（`SnapshotStore`）とは別で、終局しても消えない。端末内のみ・サーバ送信なし・
    /// 件数はゲーム数で頭打ち・「プレイ記録を消去」で消える。
    public static let lastStartKey = "playLog_lastStart_v1"

    /// 開始条件の記憶（#2611）が書き込むキー。
    public static let lastStartKeys = [lastStartKey]

    /// このクラスが書き込むキーの全量。「プレイ記録を消去」と、キーが増えていないことの検証に使う。
    public static let allKeys = recommendationKeys + reviewRequestKeys + reviewPromptKeys + playRecordKeys + howToPlayKeys + newGameKeys + playDayKeys + homerunKeys + lastStartKeys

    private let defaults: UserDefaults

    /// この起動で「増えた」と判定したゲーム（#723）。最初の問い合わせで決め、以後は同じ値を返す。
    private var sessionNewGameIDs: Set<String>?

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
    private var hasAnswered: Bool
    private var hasAskedAboutNewGame: Bool
    private var openDays: Int
    private var lastOpenDay: Int?
    private var daysMilestoneAsked: Int

    /// ゲーム別の記録。キーは `recordKey(gameID:variant:)`。
    public private(set) var records: [String: PlayRecord]

    /// 初回のミニガイド（#118）を出し終えた gameID。
    public private(set) var guidedGameIDs: Set<String>

    /// 遊んだ日の日番号（昇順・重複なし・最大 366 個）。
    public private(set) var playDays: [Int]

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
        self.hasAnswered = defaults.bool(forKey: Self.reviewAnsweredKey)
        self.hasAskedAboutNewGame = defaults.bool(forKey: Self.newGameCardAskedKey)
        self.openDays = defaults.integer(forKey: Self.openDaysKey)
        self.lastOpenDay = defaults.object(forKey: Self.lastOpenDayKey) as? Int
        self.daysMilestoneAsked = defaults.integer(forKey: Self.daysMilestoneAskedKey)

        self.guidedGameIDs = Set(defaults.stringArray(forKey: Self.guidedGameIDsKey) ?? [])
        // 壊れた値は空に倒す。上限を超えて入っていても読み込み時に切り詰める。
        self.playDays = Array(((defaults.array(forKey: Self.playDaysKey) as? [Int]) ?? []).sorted().suffix(PlayDayStreak.maxStoredDays))

        // 壊れた JSON（旧形式・書き込み途中の中断）で起動できなくならないよう、失敗したら空に倒す。
        // 記録は再取得できない代わりに失っても遊べるため、可用性を優先する。
        let stored: [String: PlayRecord]
        if let data = defaults.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([String: PlayRecord].self, from: data) {
            stored = decoded
        } else {
            stored = [:]
        }
        self.records = Self.droppingRetiredRecords(Self.renamingStaleVariantLabels(Self.migratingLegacyRecords(stored)))
        // 移し替えが起きた回だけ書き戻す。次の起動では旧キーが無いので何も起きない。
        if self.records != stored { persistRecords() }
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
            lastRequestedVersion: lastRequestedVersion,
            hasAnswered: hasAnswered,
            hasAskedAboutNewGame: hasAskedAboutNewGame,
            openDays: openDays,
            daysMilestoneAsked: daysMilestoneAsked
        )
    }

    /// 今日を「アプリを開いた日」として数える（#3078）。同じ日は何度呼んでも増えない。
    ///
    /// 端末の時計を戻された場合に水増しされないよう、最後に数えた日より前の日は数えない。
    public func recordAppOpenDay(at date: Date, calendar: Calendar = .current) {
        let day = PlayDayStreak.dayNumber(for: date, calendar: calendar)
        if let lastOpenDay, day <= lastOpenDay { return }
        openDays += 1
        lastOpenDay = day
        defaults.set(openDays, forKey: Self.openDaysKey)
        defaults.set(day, forKey: Self.lastOpenDayKey)
    }

    /// 遊んだ日数の節目（7・30）の評価のお願いを出したときに記録する（#3078）。それ以下の節目も出し済みとして扱う。
    public func markDaysMilestoneAsked(_ milestone: Int) {
        guard milestone > daysMilestoneAsked else { return }
        daysMilestoneAsked = milestone
        defaults.set(milestone, forKey: Self.daysMilestoneAskedKey)
    }

    /// 新しいゲームの感想カード（#3061）を出したときに記録する。1 人につき一度きり。
    public func markNewGameCardAsked() {
        hasAskedAboutNewGame = true
        defaults.set(true, forKey: Self.newGameCardAskedKey)
    }

    /// 感想カードで「App Store で感想を書く」を押したときに記録する（#3061）。以後、評価のお願いはどれも出さない。
    public func markReviewAnswered() {
        hasAnswered = true
        defaults.set(true, forKey: Self.reviewAnsweredKey)
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

    /// 区分（`GameScore.variant`）を**後から**導入したゲームの、旧記録の引き継ぎ先（#383）。
    ///
    /// 区分が無かった頃の記録は `gameID` 単独のキーに入っている。区分を入れた版に更新すると
    /// 書き込み先が `gameID#variant` に変わるため、そのままでは旧記録がどこからも参照されず、
    /// 更新後の初回クリアが無条件に「新記録」になる（麻雀ソリティアが #239 で該当した）。
    /// 値は「区分が無かった頃に遊べた唯一の区分」= 既定区分を指す。
    static let legacyRecordMigrations: [String: (variant: String, label: String)] = [
        "mahjong": (variant: "turtle", label: RecordVariantLabels.stored(gameID: "mahjong", variant: "turtle")),
    ]

    /// 区分の表示名を改名したゲームの、保存済みの旧表示名（#2176）。キーは `recordKey`、値は (旧名, 新名)。
    ///
    /// `variantLabel` は保存した時点の文字列で、次に遊んで記録を更新するまで書き換わらない。改名後も
    /// ハブに旧名が出続けるので、読み込み時に新名へ直す。区分キー（`backpain`）は変えない。
    static let renamedVariantLabels: [String: (old: String, new: String)] = [
        "ojisanpuzzle#backpain": (old: "腰痛モード", new: "荷運びモード"),  // i18n-keep: 記録に保存済みの区分名の読み替え
    ]

    /// ルールが変わって**記録の数値の意味が変わった**ため読み飛ばす記録のキー（#2551・#2552）。
    ///
    /// ポーカーはチップ制（持ち点の枚数）から 10 回勝負の点数制に変わった。旧記録は桁が違い、残すと
    /// 自己ベストもハブの「ベスト」もいつまでも旧記録のままになる。新しい記録は `poker#round10` に書く。
    ///
    /// ブラックジャックも 10 回勝負の勝ち点（`blackjack#match10`）に変えたため、以前の記録（区分なしの
    /// `blackjack`）は点の意味が違う。残すとハブの 1 行が旧記録を代表に選び、新しい自己ベストが永久に更新されない。
    ///
    /// 新しい記録は別のキーに書くので、毎回捨てても新しい記録には触れない。
    static let retiredRecordKeys: Set<String> = ["blackjack", "poker", "poker#bonus"]

    /// 読み飛ばす記録を除いた結果を返す純粋関数（#2551・#2552）。
    static func droppingRetiredRecords(_ records: [String: PlayRecord]) -> [String: PlayRecord] {
        records.filter { !retiredRecordKeys.contains($0.key) }
    }

    /// 保存済みの旧表示名を新表示名へ直した結果を返す純粋関数（#2176）。旧名以外のラベルには触れない。
    static func renamingStaleVariantLabels(_ records: [String: PlayRecord]) -> [String: PlayRecord] {
        var result = records
        for (key, rename) in renamedVariantLabels where result[key]?.variantLabel == rename.old {
            result[key]?.variantLabel = rename.new
        }
        return result
    }

    /// 旧キーの記録を既定区分のキーへ移し替えた結果を返す純粋関数（#383）。
    ///
    /// 引き継ぎ先に既に記録があれば**両方を合成**する。区分を入れた版で一度でも遊んでいると
    /// 新旧のキーが並存するため、片方を捨てると自己ベストか通算成績のどちらかが失われる。
    /// 合成後は旧キーを消すので、ハブに同じゲームの行が2つ出ることもなくなる。
    static func migratingLegacyRecords(_ records: [String: PlayRecord]) -> [String: PlayRecord] {
        var result = records
        for (gameID, destination) in legacyRecordMigrations {
            guard var legacy = result[gameID] else { continue }
            legacy.variantLabel = destination.label
            let key = recordKey(gameID: gameID, variant: destination.variant)
            result[key] = result[key].map { legacy.merged(into: $0) } ?? legacy
            result[gameID] = nil
        }
        return result
    }

    /// 1 件ぶんの記録を取り出す。まだ遊んでいなければ nil。
    public func record(gameID: String, variant: String? = nil) -> PlayRecord? {
        let key = Self.recordKey(gameID: gameID, variant: variant)
        return records[key].map { Self.keyed($0, key) }
    }

    /// 表示用に保存先のキーを添えた記録（保存はしない。`PlayRecord.recordKey`）。
    private static func keyed(_ record: PlayRecord, _ key: String) -> PlayRecord {
        var record = record
        record.recordKey = key
        return record
    }

    /// そのゲームの全区分の記録。キー順で安定させる（表示のちらつき防止）。
    public func records(gameID: String) -> [PlayRecord] {
        let prefix = "\(gameID)#"
        return records
            .filter { $0.key == gameID || $0.key.hasPrefix(prefix) }
            .sorted { $0.key < $1.key }
            .map { Self.keyed($0.value, $0.key) }
    }

    /// ハブのカードに出す 1 行。記録がまだ無ければ nil。
    public func summaryLine(gameID: String) -> String? {
        RecordFormat.hubLine(records(gameID: gameID), gameID: gameID)
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

    /// そのゲームを一度でも決着まで遊んだか（ハブのタイルの「未プレイ」の印・#2849）。
    /// 「きろく」の `isPlayed` と同じ規則で、`playedGameIDs` か記録のどちらかがあれば遊んだとみなす。
    /// 区分があるゲームの記録キー（`gameID#区分`）も見る。新しく何も保存しない。
    public func hasPlayed(gameID: String) -> Bool {
        playedGameIDs.contains(gameID) || records.keys.contains { key in
            key == gameID || key.hasPrefix(gameID + "#")
        }
    }

    /// ゲームごとの通算プレイ回数（再エンゲージメント通知 #1193）。区分があるゲームは合算する。
    public var totalPlaysByGame: [String: Int] {
        var result: [String: Int] = [:]
        for (key, record) in records {
            let gameID = key.split(separator: "#", maxSplits: 1).first.map(String.init) ?? key
            result[gameID, default: 0] += record.plays
        }
        return result
    }

    /// `game_start` に載せる、そのゲームの遊び込み具合（#1195）。読むだけで何も保存しない。
    ///
    /// 最終プレイ日時が無い（旧データ・未プレイ）ゲームは経過日数を nil にする。
    public func engagement(gameID: String, now: Date) -> AnalyticsEngagement {
        let days = lastPlayedAtByGame[gameID].map { Int(now.timeIntervalSince($0) / 86_400) }
        return AnalyticsEngagement(playCount: totalPlaysByGame[gameID] ?? 0, daysSinceLastPlay: days)
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
        recordPlayDay(at: date)
        return RecordResult(record: Self.keyed(result.record, key), update: result.update)
    }

    /// 決着した日を遊んだ日として足す（#1625）。同じ日は何局目でも増えない。
    private func recordPlayDay(at date: Date, calendar: Calendar = .current) {
        let updated = PlayDayStreak.inserting(PlayDayStreak.dayNumber(for: date, calendar: calendar), into: playDays)
        guard updated != playDays else { return }
        playDays = updated
        defaults.set(playDays, forKey: Self.playDaysKey)
    }

    /// 今日時点の連続プレイ日数（#1625）。1 日空くと 0。保存は `playDays` だけで、開くたびに計算し直す。
    public func playStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        PlayDayStreak.current(days: playDays, today: PlayDayStreak.dayNumber(for: now, calendar: calendar))
    }

    /// 保存している範囲での最長の連続プレイ日数（#2886）。
    public func longestPlayStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        PlayDayStreak.longest(days: playDays, today: PlayDayStreak.dayNumber(for: now, calendar: calendar))
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
        // 取り消した負けは連敗にも数えない（コンティニューで続きを遊ぶので、負けは確定していない）。
        record.currentLossStreak = record.lossStreak > 1 ? record.lossStreak - 1 : nil
        records[key] = record
        persistRecords()
    }

    /// リワード広告のコンティニューで「その勝ちが無かったことになった」ときに呼ぶ（#1359）。
    ///
    /// くっつきフルーツはメロンを作った回を勝ちとして記録するが、その回もコンティニューで続きを遊べる。
    /// 巻き戻さないと、再び終局したときにもう 1 勝が加わり、1 プレイが 2 勝として数えられる。
    /// 勝ちは記録（`plays` / `wins` / 連勝）に加え、評価リクエストと実績の元になる通算勝利数
    /// （`totalWins`）にも入っているので、両方を戻す。
    ///
    /// - Note: 自己ベストと最長連勝は巻き戻さない（`cancelLoss` と同じ理由。続きの終局で改めて勝ちを
    ///   記録すれば、最長連勝は同じ値に戻る）。
    public func cancelWin(gameID: String, variant: String? = nil) {
        let key = Self.recordKey(gameID: gameID, variant: variant)
        guard var record = records[key], record.plays > 0, record.wins > 0 else { return }
        record.plays -= 1
        record.wins -= 1
        record.currentStreak = max(0, record.currentStreak - 1)
        records[key] = record
        persistRecords()
        if totalWins > 0 {
            totalWins -= 1
            defaults.set(totalWins, forKey: Self.totalWinsKey)
        }
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

    // MARK: - 新しいゲームの印（#723）

    /// 更新で増えたゲームの ID。判定の規則は `NewGames.ids` が持つ。
    ///
    /// 最初の呼び出しで前回の登録ゲームと比べ、**その場でいまの登録ゲームを保存する**。
    /// そのため同じ起動の中では何度呼んでも同じ値を返し、次の起動では同じゲームを NEW にしない
    /// （ハブを出した時点で「見た」とみなす）。
    public func newGameIDs(registeredIDs: [String]) -> Set<String> {
        if let sessionNewGameIDs { return sessionNewGameIDs }
        let known = defaults.stringArray(forKey: Self.knownGameIDsKey).map(Set.init)
        // 記録を持たない版からの更新と新規インストールを、プレイの痕跡の有無で見分ける。
        let hasPlayHistory = totalFinishes > 0 || !guidedGameIDs.isEmpty || !records.isEmpty
        let result = NewGames.ids(registeredIDs: registeredIDs, knownIDs: known, hasPlayHistory: hasPlayHistory)
        // 並びを固定して保存し、同じ集合なら常に同じバイト列になるようにする。
        defaults.set(Set(registeredIDs).sorted(), forKey: Self.knownGameIDsKey)
        sessionNewGameIDs = result
        return result
    }

    /// 最後に選んだ開始条件（#2611）。記録が無い・読めない（旧形式など）ときは nil で、呼び側が既定値に倒す。
    public func lastStart<T: Decodable>(_ type: T.Type = T.self, gameID: String) -> T? {
        guard let data = (defaults.dictionary(forKey: Self.lastStartKey) as? [String: Data])?[gameID] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 開始条件を覚える（#2611）。ゲームを始めた時点で呼ぶ。同じ gameID は上書き。
    public func saveLastStart<T: Encodable>(_ value: T, gameID: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        var all = (defaults.dictionary(forKey: Self.lastStartKey) as? [String: Data]) ?? [:]
        all[gameID] = data
        defaults.set(all, forKey: Self.lastStartKey)
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey)
    }

    /// 設定の「プレイ記録を消去」から呼ぶ。保存したキーをすべて削除する。
    ///
    /// 新しいゲームの印（#723）の記録も消える。消去後はプレイの痕跡も無いため、次の起動は
    /// 新規インストールと同じ扱いになり、何も NEW にならない。
    public func clear() {
        for key in Self.allKeys { defaults.removeObject(forKey: key) }
        sessionNewGameIDs = []
        totalFinishes = 0
        playedGameIDs = []
        lastShownCount = 0
        lastShownAt = nil
        ignoredStreak = 0
        totalWins = 0
        lastRequestedAt = nil
        lastRequestedWins = 0
        lastRequestedVersion = nil
        hasAnswered = false
        hasAskedAboutNewGame = false
        openDays = 0
        lastOpenDay = nil
        daysMilestoneAsked = 0
        records = [:]
        guidedGameIDs = []
        playDays = []
    }
}
