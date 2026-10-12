import Testing
import Foundation
@testable import CoreEngine

@Suite("連続プレイ日数（#1625）")
@MainActor
struct PlayDayStreakTests {
    private func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, in c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test("連続の数え方: 今日まで・昨日まで・1日空き・空")
    func currentStreak() {
        #expect(PlayDayStreak.current(days: [], today: 100) == 0)
        #expect(PlayDayStreak.current(days: [98, 99, 100], today: 100) == 3)
        #expect(PlayDayStreak.current(days: [97, 98, 99], today: 100) == 3, "今日はまだ。昨日までの連続は残る")
        #expect(PlayDayStreak.current(days: [97, 98], today: 100) == 0, "1日空くと0")
        #expect(PlayDayStreak.current(days: [90, 91, 99, 100], today: 100) == 2, "途切れより前は数えない")
        #expect(PlayDayStreak.current(days: [100], today: 100) == 1)
    }

    @Test("端末時刻を戻しても、未来の日が連続を水増ししない")
    func clockRolledBack() {
        // 日 98〜102 を遊んだあと、端末を 99 日に戻した。
        #expect(PlayDayStreak.current(days: [98, 99, 100, 101, 102], today: 99) == 2)
        // 戻した先が遊んでいない日なら 0。
        #expect(PlayDayStreak.current(days: [100, 101], today: 95) == 0)
    }

    @Test("日番号: 深夜をまたぐ前後で日が変わり、同じ日の朝夕は同じ")
    func dayBoundary() {
        let tokyo = calendar("Asia/Tokyo")
        let late = PlayDayStreak.dayNumber(for: date(2026, 10, 12, 23, 59, in: tokyo), calendar: tokyo)
        let early = PlayDayStreak.dayNumber(for: date(2026, 10, 13, 0, 1, in: tokyo), calendar: tokyo)
        let morning = PlayDayStreak.dayNumber(for: date(2026, 10, 12, 0, 0, in: tokyo), calendar: tokyo)
        #expect(early == late + 1)
        #expect(morning == late)
    }

    @Test("日番号: 同じ瞬間でもタイムゾーンで日が違えば、端末のローカル日付で数える")
    func dayNumberFollowsLocalCalendar() {
        let tokyo = calendar("Asia/Tokyo")
        let la = calendar("America/Los_Angeles")
        let instant = date(2026, 10, 12, 8, 0, in: tokyo) // 東京 10/12 08:00 = LA 10/11 16:00
        #expect(PlayDayStreak.dayNumber(for: instant, calendar: tokyo)
                == PlayDayStreak.dayNumber(for: instant, calendar: la) + 1)
    }

    @Test("月・年・うるう日をまたいでも連続する")
    func crossesMonthYearLeapDay() {
        let c = calendar("Asia/Tokyo")
        func n(_ y: Int, _ m: Int, _ d: Int) -> Int { PlayDayStreak.dayNumber(for: date(y, m, d, in: c), calendar: c) }
        #expect(n(2027, 1, 1) == n(2026, 12, 31) + 1)
        #expect(n(2028, 3, 1) == n(2028, 2, 29) + 1)
        #expect(n(2026, 11, 1) == n(2026, 10, 31) + 1)
    }

    @Test("夏時間の切り替え日（23時間・25時間の日）でも1日は1日")
    func daylightSavingDay() {
        let la = calendar("America/Los_Angeles")
        let before = PlayDayStreak.dayNumber(for: date(2026, 11, 1, 12, in: la), calendar: la) // 秋の戻り日（25時間）
        let after = PlayDayStreak.dayNumber(for: date(2026, 11, 2, 0, 30, in: la), calendar: la)
        #expect(after == before + 1)
        let spring = PlayDayStreak.dayNumber(for: date(2026, 3, 8, 12, in: la), calendar: la) // 春の進み日（23時間）
        #expect(PlayDayStreak.dayNumber(for: date(2026, 3, 9, 0, 30, in: la), calendar: la) == spring + 1)
    }

    @Test("保存する日は昇順・重複なしで、366個を超えたら古い日から捨てる")
    func insertingBounds() {
        #expect(PlayDayStreak.inserting(5, into: [3, 5]) == [3, 5])
        #expect(PlayDayStreak.inserting(4, into: [3, 5]) == [3, 4, 5])
        let full = Array(1...366)
        let next = PlayDayStreak.inserting(367, into: full)
        #expect(next.count == 366)
        #expect(next.first == 2 && next.last == 367)
    }

    @Test("ハブの1行は2日以上のときだけ")
    func hubText() {
        #expect(PlayDayStreak.hubText(streak: 0) == nil)
        #expect(PlayDayStreak.hubText(streak: 1) == nil)
        #expect(PlayDayStreak.hubText(streak: 2) == "連続 2 日あそび中")
    }

    // MARK: PlayLog との結線

    private func makeLog(_ name: String) -> (PlayLog, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (PlayLog(defaults: defaults), defaults)
    }

    @Test("決着を記録すると遊んだ日が1キーに入る。同じ日は何局でも1個・再起動で復元・消去で消える")
    func playLogStoresDays() {
        let name = "asobiba.playdaystreak.tests.log"
        let (log, defaults) = makeLog(name)
        let now = Date()
        for _ in 0..<5 {
            log.recordResult(gameID: "g", outcome: .win, score: GameScore(), at: now)
        }
        #expect(log.playDays.count == 1)
        #expect(log.playStreak(now: now) == 1)

        let yesterday = now.addingTimeInterval(-86_400)
        log.recordResult(gameID: "g", outcome: .win, score: GameScore(), at: yesterday)
        #expect(log.playStreak(now: now) == 2)
        #expect(Set((defaults.persistentDomain(forName: name) ?? [:]).keys).contains(PlayLog.playDaysKey))

        let reopened = PlayLog(defaults: defaults)
        #expect(reopened.playDays == log.playDays)
        #expect(reopened.playStreak(now: now) == 2)

        reopened.clear()
        #expect(defaults.object(forKey: PlayLog.playDaysKey) == nil)
        #expect(reopened.playStreak(now: now) == 0)
        #expect(PlayLog.allKeys.contains(PlayLog.playDaysKey))
        defaults.removePersistentDomain(forName: name)
    }

    @Test("1年ぶん毎日遊んでも保存は366個まで")
    func playLogBounded() {
        let name = "asobiba.playdaystreak.tests.bounded"
        let (log, defaults) = makeLog(name)
        let start = Date()
        for i in 0..<400 {
            log.recordResult(gameID: "g", outcome: .win, score: GameScore(),
                             at: start.addingTimeInterval(Double(i) * 86_400))
        }
        #expect(log.playDays.count == PlayDayStreak.maxStoredDays)
        #expect((defaults.array(forKey: PlayLog.playDaysKey) as? [Int])?.count == PlayDayStreak.maxStoredDays)
        defaults.removePersistentDomain(forName: name)
    }
}
