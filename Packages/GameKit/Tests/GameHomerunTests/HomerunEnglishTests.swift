import Testing
import Foundation
import Core
@testable import HomerunCore
@testable import GameHomerun

/// 柵越えおじさんの英語の文言（多言語④ #2167）。`swift test` は常に日本語なので、言語を明示して表を引く。
/// `AppLanguageStore.shared` は書き換えない（並列のテストを巻き込む）。
@Suite("柵越えおじさん: 英語の文言（#2167）")
struct HomerunEnglishTests {
    private func en(_ key: String, _ arguments: any CVarArg...) -> String {
        GameHomerun.tr.string(key, arguments: arguments, language: .english)
    }

    @Test("順位の語尾: 日本語は「位」、英語は序数（11〜13 は th）")
    func rankSuffix() {
        #expect(HomerunRankingText.rankSuffix(3, language: .japanese) == "位")
        let expected: [Int: String] = [1: "st", 2: "nd", 3: "rd", 4: "th", 11: "th", 12: "th", 13: "th",
                                       21: "st", 22: "nd", 23: "rd", 101: "st", 111: "th", 112: "th"]
        for (rank, suffix) in expected {
            #expect(HomerunRankingText.rankSuffix(rank, language: .english) == suffix, "\(rank)")
        }
    }

    @Test("週の範囲は英語の曜日と残り日数（1 日は単数）")
    func weekRangeInEnglish() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: now, calendar: calendar, language: .english)
                == "10/5 (Mon) – 10/11 (Sun)  · 3 days left")
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: lastDay, calendar: calendar, language: .english)?
                    .hasSuffix("· 1 day left") == true)
        let last = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: last, calendar: calendar, language: .english)?
                    .hasSuffix("Ends today") == true)
        // 日本語は従来どおり。
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: now, calendar: calendar, language: .japanese)
                == "10/5（月） 〜 10/11（日）　あと 3 日")
    }

    @Test("1 球の言葉と読み上げ")
    func ballWordsInEnglish() {
        #expect(en("柵越え！") == "Homer!")
        #expect(en("%1$lld球目、%2$@、%3$lldメートル、%4$@、%5$@", 2, "Outta here", 160, "Left-center", "Spot On")
                == "Pitch 2, Outta here, 160 meters, Left-center, Spot On")
        #expect(en("柵越え %lld 本", 1) == "1 homer")
        #expect(en("柵越え %lld 本", 7) == "7 homers")
        #expect(en("最長 %1$@（%2$lld 球目・%3$@・%4$@）", "128 m", 3, "Center", "Nice")
                == "Longest: 128 m (pitch 3 · Center · Nice)")
    }

    /// 英語の訳文に他社の商標名を入れない（#2109 の共通の決定）。日本語の文にある「Game Center」も英語では言い換える。
    @Test("英語の訳文に他社の商標名や禁止語を含めない", arguments: [GameHomerun.tr, HomerunCore.tr])
    func noTrademarksInEnglish(table: StringTable) throws {
        let url = try #require(table.catalogURL, "表が同梱されていない")
        let catalog = try #require(StringCatalog(data: try Data(contentsOf: url)))
        for (key, byLanguage) in catalog.entries {
            let forms: [String]
            switch byLanguage["en"] {
            case .text(let text)?: forms = [text]
            case .plural(let byCategory)?: forms = Array(byCategory.values)
            case nil: forms = []
            }
            for form in forms {
                for banned in ["Game Center", "iPhone", "Apple", "Derby", "derby", "®", "™"] {
                    #expect(!form.contains(banned), "「\(key)」の英語に「\(banned)」: \(form)")
                }
            }
        }
    }
}
