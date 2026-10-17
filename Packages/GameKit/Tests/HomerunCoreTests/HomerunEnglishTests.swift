import Testing
import Foundation
import Core
@testable import HomerunCore

/// 柵越えおじさんの英語の文言（多言語④ #2167）。`swift test` は常に日本語なので、言語を明示して表を引く。
@Suite("柵越えおじさん: 英語の文言（#2167）")
struct HomerunCoreEnglishTests {
    private func en(_ key: String, _ arguments: any CVarArg...) -> String {
        HomerunCore.tr.string(key, arguments: arguments, language: .english)
    }

    @Test("戻るまでの残りは、単位ごと文で訳し、1 のときは単数")
    func remainingTextInEnglish() {
        #expect(en("あと約%lld時間%lld分で戻ります", 2, 30) == "Back in about 2h 30m")
        #expect(en("あと約%lld時間で戻ります", 1) == "Back in about 1 hour")
        #expect(en("あと約%lld時間で戻ります", 24) == "Back in about 24 hours")
        #expect(en("あと約%lld分で戻ります", 1) == "Back in about 1 minute")
        #expect(en("あと%lld分で無料枠が戻ります", 45) == "Free plays return in 45 minutes")
        #expect(en("あと%lld時間%lld分で無料枠が戻ります", 2, 30) == "Free plays return in 2h 30m")
    }

    @Test("実績の名前と条件は全部英語になり、通算の本数は複数形")
    func achievementsInEnglish() {
        #expect(en("はじめての柵越え") == "First Homer")
        #expect(en("通算 柵越え %lld本", 1) == "1 Career Homer")
        #expect(en("通算 柵越え %lld本", 30) == "30 Career Homers")
        #expect(en("1 挑戦で %@", "1,000m") == "1,000m in One Round")
    }

    @Test("方向の呼び名")
    func sectorsInEnglish() {
        #expect(en("レフト") == "Left")
        #expect(en("左中間") == "Left-center")
        #expect(en("センター") == "Center")
    }
}
