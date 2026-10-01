import Foundation

/// 日次台帳（README §3.4）: 無料 3・広告 +1（1 日 5 本）・アンケート +1（1 日 1 回）・月が割れたら +2（#1680・回数の上限なし）・0:00 リセット。
/// 減算は打席に立った時点。「プレイ記録を消去」で補充されないよう、保存先は `PlayLog.allKeys` に入れない。
public struct HomerunLedger: Codable, Equatable, Sendable {
    public static let freePerDay = 3
    public static let adLimitPerDay = 5
    public static let surveyBonus = 1
    /// 月が割れたとき（#1680）のプレゼント。当日分として足す（0:00 で消える）。1 日の全体の上限は無い（会長決裁 2026-10-01）。
    public static let moonBonus = 2

    /// 消費する枠の種別（#1685）。
    public enum Credit: Equatable, Sendable {
        case free, bonus, survey, ad
    }

    /// 台帳が属する日（`yyyyMMdd`）。
    public private(set) var dayKey: Int
    public private(set) var used: Int
    public private(set) var adsWatched: Int
    public private(set) var surveyDone: Bool
    /// 月が割れたプレゼントで足した回数（#1680）。Optional なのは保存の互換のため: 以前の保存（このキーが無い）も読め、
    /// 0 のときは書かない（以前の版で読んでも知らないキーは無視される）。
    private var moonBonusGranted: Int?

    public init(dayKey: Int = 0, used: Int = 0, adsWatched: Int = 0, surveyDone: Bool = false, bonus: Int = 0) {
        self.dayKey = dayKey
        self.used = used
        self.adsWatched = adsWatched
        self.surveyDone = surveyDone
        moonBonusGranted = bonus > 0 ? bonus : nil
    }

    /// 今日、月が割れたプレゼントで足した回数。
    public var bonus: Int { moonBonusGranted ?? 0 }

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

    public var allowance: Int { Self.freePerDay + adsWatched + (surveyDone ? Self.surveyBonus : 0) + bonus }
    public var remaining: Int { max(0, allowance - used) }
    public var canStart: Bool { remaining > 0 }
    public var canWatchAd: Bool { adsWatched < Self.adLimitPerDay }
    public var canDoSurvey: Bool { !surveyDone }

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

    @discardableResult
    public mutating func grantAd() -> Bool {
        guard canWatchAd else { return false }
        adsWatched += 1
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
