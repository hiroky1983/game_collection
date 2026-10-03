import Testing
import Foundation
@testable import HomerunCore

@Suite("柵越えおじさん: 戻る時刻と戻ったら知らせる（#1576）")
struct HomerunReturnPolicyTests {

    private func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    @Test("戻る時刻は端末のタイムゾーンの翌 0:00（月末・年またぎを含む）")
    func nextResetIsNextLocalMidnight() {
        let tokyo = calendar("Asia/Tokyo")
        #expect(HomerunReturnPolicy.nextReset(after: date(2026, 9, 30, 21, 30, in: tokyo), calendar: tokyo)
                == date(2026, 10, 1, 0, 0, in: tokyo))
        #expect(HomerunReturnPolicy.nextReset(after: date(2026, 12, 31, 23, 59, 59, in: tokyo), calendar: tokyo)
                == date(2027, 1, 1, 0, 0, in: tokyo))
        // ちょうど 0:00 は「新しい日」なので、次の境目は丸 1 日後。
        #expect(HomerunReturnPolicy.nextReset(after: date(2026, 9, 30, 0, 0, in: tokyo), calendar: tokyo)
                == date(2026, 10, 1, 0, 0, in: tokyo))
    }

    @Test("同じ瞬間でもタイムゾーンが違えば戻る時刻が違い、台帳の日付切り替えと一致する")
    func resetMatchesLedgerRollover() {
        let tokyo = calendar("Asia/Tokyo")
        let la = calendar("America/Los_Angeles")
        let instant = date(2026, 9, 30, 21, 30, in: tokyo)   // LA では同日 05:30
        let tokyoReset = HomerunReturnPolicy.nextReset(after: instant, calendar: tokyo)
        let laReset = HomerunReturnPolicy.nextReset(after: instant, calendar: la)
        #expect(tokyoReset != laReset)
        for cal in [(tokyo, tokyoReset), (la, laReset)] {
            let before = HomerunLedger.dayKey(for: cal.1.addingTimeInterval(-1), calendar: cal.0)
            let after = HomerunLedger.dayKey(for: cal.1, calendar: cal.0)
            #expect(after > before, "戻る時刻の 1 秒前と丁度で日付キーが切り替わっている")
        }
    }

    @Test("夏時間の日は 24 時間ではなく暦の翌日 0:00 になる")
    func daylightSavingDay() {
        let la = calendar("America/Los_Angeles")
        // 2026-11-01 は夏時間の終わり（この日は 25 時間）。
        let now = date(2026, 11, 1, 20, 0, in: la)
        #expect(HomerunReturnPolicy.nextReset(after: now, calendar: la) == date(2026, 11, 2, 0, 0, in: la))
        #expect(HomerunReturnPolicy.minutesUntilReset(from: now, calendar: la) == 4 * 60)
    }

    @Test("残り時間の表示: 時間と分・分だけ・ちょうどの時間・秒は切り上げ")
    func remainingText() {
        let tokyo = calendar("Asia/Tokyo")
        #expect(HomerunReturnPolicy.remainingText(from: date(2026, 9, 30, 21, 30, in: tokyo), calendar: tokyo)
                == "あと約2時間30分で戻ります")
        #expect(HomerunReturnPolicy.remainingText(from: date(2026, 9, 30, 22, 0, in: tokyo), calendar: tokyo)
                == "あと約2時間で戻ります")
        #expect(HomerunReturnPolicy.remainingText(from: date(2026, 9, 30, 23, 15, in: tokyo), calendar: tokyo)
                == "あと約45分で戻ります")
        // 23:59:30 は残り 30 秒。0 分とは出さず 1 分に切り上げる。
        #expect(HomerunReturnPolicy.remainingText(from: date(2026, 9, 30, 23, 59, 30, in: tokyo), calendar: tokyo)
                == "あと約1分で戻ります")
        // 0:00 直後は丸 1 日ぶん（24 時間）。
        #expect(HomerunReturnPolicy.remainingText(from: date(2026, 9, 30, 0, 0, in: tokyo), calendar: tokyo)
                == "あと約24時間で戻ります")
    }

    @Test("通知の予約時刻は翌 0:00 の少し後で、常に 1 点に定まる")
    func reminderFireDate() {
        let tokyo = calendar("Asia/Tokyo")
        let a = HomerunReturnPolicy.reminderFireDate(after: date(2026, 9, 30, 9, 0, in: tokyo), calendar: tokyo)
        let b = HomerunReturnPolicy.reminderFireDate(after: date(2026, 9, 30, 23, 59, in: tokyo), calendar: tokyo)
        #expect(a == date(2026, 10, 1, 0, 1, in: tokyo))
        #expect(a == b, "同じ日の使い切りなら何度求めても同じ時刻（識別子で置き換わり 1 回に収まる）")
    }

    @Test("予約の有無は発火時刻で決まる")
    func offerAndActive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!HomerunReturnPolicy.isReminderActive(pendingFireDate: nil, now: now))
        #expect(HomerunReturnPolicy.isReminderActive(pendingFireDate: now.addingTimeInterval(1), now: now))
        #expect(!HomerunReturnPolicy.isReminderActive(pendingFireDate: now, now: now))
        #expect(!HomerunReturnPolicy.isReminderActive(pendingFireDate: now.addingTimeInterval(-1), now: now))
    }
}
