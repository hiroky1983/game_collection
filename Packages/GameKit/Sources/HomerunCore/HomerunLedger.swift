import Foundation

/// 日次台帳（README §3.4）: 無料 3・アンケート +1（1 日 1 回）・広告でプレイ（1 日 5 本・回数とは別）・月が割れたら +1（#1680・会長決裁 2026-10-04 で +2→+1・回数の上限なし）・0:00 リセット。
/// 回数を使い切ったら「広告を見てプレイ」（#1694）: 広告 1 本でその場の 1 挑戦だけ遊べる。**回数は増やさない**（貯められない）。
/// 減算は打席に立った時点。「プレイ記録を消去」で補充されないよう、保存先は `PlayLog.allKeys` に入れない。
public struct HomerunLedger: Codable, Equatable, Sendable {
    public static let freePerDay = 3
    /// 広告で遊べる 1 日の本数の上限（会長決裁 2026-10-02・#1694 で 10 本→会長決裁 2026-10-04 で 5 本に変更）。**nil にすると無制限**。
    /// 画面には上限の本数を出さない（達したときだけ「今日はここまで」）。
    /// 台帳・ボタン・文言はこの値だけを見るので、変えるのはここ 1 か所。
    public static let adLimitPerDay: Int? = 5
    public static let surveyBonus = 1
    /// 月が割れたとき（#1680）のプレゼント。当日分として足す（0:00 で消える）。1 日の全体の上限は無い（会長決裁 2026-10-01）。
    /// +2 → +1（会長決裁 2026-10-04）。
    public static let moonBonus = 1

    /// 消費する枠の種別（#1685）。
    public enum Credit: Equatable, Sendable {
        case free, bonus, survey, ad
    }

    /// 台帳が属する日（`yyyyMMdd`）。
    public private(set) var dayKey: Int
    /// 回数（`allowance`）から使った数。広告でのプレイ（`adPlays`）はここに数えない。
    public private(set) var used: Int
    /// 以前の版（〜v1.1.7）で「広告を見て挑戦 +1 回」として回数に足した本数。保存のキーは以前のまま `adsWatched`。
    /// 新しい版では増やさない（その日のうちは貯めた分を回数として使え、0:00 で消える）。
    public private(set) var legacyAdGrants: Int
    public private(set) var surveyDone: Bool
    /// 月が割れたプレゼントで足した回数（#1680）。Optional なのは保存の互換のため: 以前の保存（このキーが無い）も読め、
    /// 0 のときは書かない（以前の版で読んでも知らないキーは無視される）。
    private var moonBonusGranted: Int?
    /// 広告を見て始めた挑戦の数（#1694）。保存の互換はボーナスと同じ（0 のときは書かない）。
    private var adPlaysStarted: Int?

    private enum CodingKeys: String, CodingKey {
        case dayKey, used, surveyDone, moonBonusGranted
        case legacyAdGrants = "adsWatched"
        case adPlaysStarted = "adPlays"
    }

    public init(dayKey: Int = 0, used: Int = 0, legacyAdGrants: Int = 0, surveyDone: Bool = false, bonus: Int = 0,
                adPlays: Int = 0) {
        self.dayKey = dayKey
        self.used = used
        self.legacyAdGrants = legacyAdGrants
        self.surveyDone = surveyDone
        moonBonusGranted = bonus > 0 ? bonus : nil
        adPlaysStarted = adPlays > 0 ? adPlays : nil
    }

    /// 今日、月が割れたプレゼントで足した回数。
    public var bonus: Int { moonBonusGranted ?? 0 }
    /// 今日、広告を見て始めた挑戦の数（回数とは別に数える。#1685 の計測で枠を見分ける材料）。
    public var adPlays: Int { adPlaysStarted ?? 0 }
    /// 今日見た広告の本数（以前の版で足した分を含む）。1 日の上限（`adLimitPerDay`）はこれで数える。
    public var adsWatched: Int { legacyAdGrants + adPlays }

    /// `yyyyMMdd` の日付キー。0:00 の境目は `calendar` のタイムゾーンで決まる。
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// 日付が進んでいたら補充する。**戻っていたら何もしない**（時計を戻しても無料分は増えない）。
    public mutating func roll(to today: Int) {
        guard today > dayKey else { return }
        self = HomerunLedger(dayKey: today)
    }

    public var allowance: Int { Self.freePerDay + legacyAdGrants + (surveyDone ? Self.surveyBonus : 0) + bonus }
    public var remaining: Int { max(0, allowance - used) }
    public var canStart: Bool { remaining > 0 }
    /// 今日まだ広告を見られるか（上限が nil なら常に true）。
    public var canWatchAd: Bool { Self.canWatchAd(adsWatched: adsWatched, limit: Self.adLimitPerDay) }
    /// 「広告を見てプレイ」を出すか: 回数を使い切っていて、広告をまだ見られる。
    public var canPlayWithAd: Bool { !canStart && canWatchAd }
    public var canDoSurvey: Bool { !surveyDone }

    /// 上限の判定（上限を入れ直したときの振る舞いをテストで確かめられるよう、上限を引数に取る）。
    public static func canWatchAd(adsWatched: Int, limit: Int?) -> Bool {
        limit.map { adsWatched < $0 } ?? true
    }

    /// 次に打席に立つと消費する枠（#1685）。回数が無ければ nil。
    ///
    /// **使う順は固定**（無料 → ご褒美 → アンケート → 広告）で、もらった順ではない。無料を先に使うので、
    /// 「広告を見て遊んだ」と数えられるのは無料・ご褒美・アンケートを使い切った後の 1 回だけになる。
    /// 使った回数 `used` と今の付与だけから決まるので、保存の形は変えない。
    public var nextCredit: Credit? {
        guard canStart else { return nil }
        var rest = used
        for (credit, size) in [(Credit.free, Self.freePerDay), (.bonus, bonus),
                               (.survey, surveyDone ? Self.surveyBonus : 0)] {
            if rest < size { return credit }
            rest -= size
        }
        return .ad
    }

    /// 打席に立つ。回数が無ければ false（消費しない）。
    @discardableResult
    public mutating func consume() -> Bool {
        guard canStart else { return false }
        used += 1
        return true
    }

    /// 広告を見終えて 1 挑戦を始める（#1694）。回数は増やさず、広告での挑戦として数える。
    /// 回数が残っている（先に回数を使う）・広告の上限に達していれば false（数えない）。
    @discardableResult
    public mutating func consumeAdPlay() -> Bool {
        guard canPlayWithAd else { return false }
        adPlaysStarted = adPlays + 1
        return true
    }

    @discardableResult
    public mutating func grantSurvey() -> Bool {
        guard canDoSurvey else { return false }
        surveyDone = true
        return true
    }

    /// 月が割れた（#1680）プレゼント: 今日の回数を `moonBonus` 増やす。上限は無い。
    public mutating func grantMoonBonus() {
        moonBonusGranted = bonus + Self.moonBonus
    }
}
