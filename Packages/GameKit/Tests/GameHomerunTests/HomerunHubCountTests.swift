import Testing
import Foundation
import Core
@testable import HomerunCore
@testable import GameHomerun

/// ハブの横長タイルの右下の残り回数（#2208）。数は打席前と同じ台帳から読み、広告でのプレイは数えない。
@Suite("柵越えおじさん: ハブの残り回数のラベル（#2208）")
struct HomerunHubCountTests {
    private func defaults() -> UserDefaults {
        let name = "HomerunHubCountTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("回数 → 文字（日本語）: 0 回も隠さず「残り 0 回」")
    func labelJapanese() {
        #expect(HomerunHubCount.labelText(remaining: 3, language: .japanese) == "残り 3 回")
        #expect(HomerunHubCount.labelText(remaining: 1, language: .japanese) == "残り 1 回")
        #expect(HomerunHubCount.labelText(remaining: 0, language: .japanese) == "残り 0 回")
        #expect(HomerunHubCount.labelText(remaining: -2, language: .japanese) == "残り 0 回")
    }

    @Test("回数 → 文字（英語）: 1 は単数、0 と 2 以上は複数")
    func labelEnglish() {
        #expect(HomerunHubCount.labelText(remaining: 3, language: .english) == "3 rounds left")
        #expect(HomerunHubCount.labelText(remaining: 1, language: .english) == "1 round left")
        #expect(HomerunHubCount.labelText(remaining: 0, language: .english) == "0 rounds left")
    }

    @Test("保存が無ければ無料の 3 回")
    func freshInstall() {
        #expect(HomerunHubCount.remaining(now: date(13), defaults: defaults(), calendar: calendar)
                == HomerunLedger.freePerDay)
    }

    @Test("使った分だけ減り、広告でのプレイは数に入らない")
    func adPlaysAreNotCounted() {
        let d = defaults()
        let today = HomerunLedger.dayKey(for: date(13), calendar: calendar)
        HomerunStorage.saveLedger(HomerunLedger(dayKey: today, used: 3, adPlays: 2), d)
        #expect(HomerunHubCount.remaining(now: date(13), defaults: d, calendar: calendar) == 0)
        HomerunStorage.saveLedger(HomerunLedger(dayKey: today, used: 1), d)
        #expect(HomerunHubCount.remaining(now: date(13), defaults: d, calendar: calendar) == 2)
    }

    @Test("月のご褒美（無料で足された回数）は数に入る")
    func moonBonusIsCounted() {
        let d = defaults()
        let today = HomerunLedger.dayKey(for: date(13), calendar: calendar)
        HomerunStorage.saveLedger(HomerunLedger(dayKey: today, used: 3, bonus: 1), d)
        #expect(HomerunHubCount.remaining(now: date(13), defaults: d, calendar: calendar) == 1)
    }

    @Test("日付をまたぐと、保存し直さなくても 3 回に戻って見える")
    func rollsOverAtMidnight() {
        let d = defaults()
        let yesterday = HomerunLedger.dayKey(for: date(12), calendar: calendar)
        HomerunStorage.saveLedger(HomerunLedger(dayKey: yesterday, used: 3, adPlays: 5), d)
        #expect(HomerunHubCount.remaining(now: date(12, hour: 23), defaults: d, calendar: calendar) == 0)
        #expect(HomerunHubCount.remaining(now: date(13, hour: 0), defaults: d, calendar: calendar)
                == HomerunLedger.freePerDay)
    }
}
