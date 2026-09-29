import Foundation

/// 日次台帳（README §3.4）: 無料 3・広告 +1（1 日 5 本）・アンケート +1（1 日 1 回）・0:00 リセット。
/// 減算は打席に立った時点。「プレイ記録を消去」で補充されないよう、保存先は `PlayLog.allKeys` に入れない。
public struct HomerunLedger: Codable, Equatable, Sendable {
    public static let freePerDay = 3
    public static let adLimitPerDay = 5
    public static let surveyBonus = 1

    /// 台帳が属する日（`yyyyMMdd`）。
    public private(set) var dayKey: Int
    public private(set) var used: Int
    public private(set) var adsWatched: Int
    public private(set) var surveyDone: Bool

    public init(dayKey: Int = 0, used: Int = 0, adsWatched: Int = 0, surveyDone: Bool = false) {
        self.dayKey = dayKey
        self.used = used
        self.adsWatched = adsWatched
        self.surveyDone = surveyDone
    }

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

    public var allowance: Int { Self.freePerDay + adsWatched + (surveyDone ? Self.surveyBonus : 0) }
    public var remaining: Int { max(0, allowance - used) }
    public var canStart: Bool { remaining > 0 }
    public var canWatchAd: Bool { adsWatched < Self.adLimitPerDay }
    public var canDoSurvey: Bool { !surveyDone }

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
}
