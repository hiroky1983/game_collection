import Testing
import Core
@testable import GameDaifugo

/// 大富豪の英語の文言（#2166）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
/// `AppLanguageStore.shared` は書き換えない（並列のテストが巻き込まれる）。
@Suite("大富豪の英語の文言（#2166）")
struct DaifugoEnglishTests {

    @Test("ゲーム名は Daifugo、1 位の階級名は Tycoon")
    func gameNameAndTopRank() {
        // 原文はどちらも「大富豪」なので、ゲーム名だけは表を通さずに持つ。
        #expect(daifugoGameName(language: .english) == "Daifugo")
        #expect(daifugoGameName(language: .japanese) == "大富豪")
        #expect(GameDaifugo.tr("大富豪", language: .english) == "Tycoon")
    }

    @Test("階級名は英語で広く使われる呼び名になる")
    func ranks() {
        #expect(GameDaifugo.tr("富豪", language: .english) == "Rich")
        #expect(GameDaifugo.tr("貧民", language: .english) == "Poor")
        #expect(GameDaifugo.tr("大貧民", language: .english) == "Beggar")
        // 日本語では従来どおり。
        #expect(DaifugoRules.title(forPlace: 3) == "大貧民")
    }

    @Test("ルールの用語")
    func terms() {
        #expect(GameDaifugo.tr("革命", language: .english) == "Revolution")
        #expect(GameDaifugo.tr("8切り", language: .english) == "8-Stop")
        #expect(GameDaifugo.tr("パス", language: .english) == "Pass")
        #expect(GameDaifugo.tr("%lld枚出す", 1, language: .english) == "Play 1 Card")
        #expect(GameDaifugo.tr("%lld枚出す", 3, language: .english) == "Play 3 Cards")
        #expect(GameDaifugo.tr("%1$@の%2$@", "Hearts", "Queen", language: .english) == "Queen of Hearts")
    }

    @Test("直近の動きは中断データに原文で残し、表示の境目で訳す")
    @MainActor
    func actionsStayOriginal() {
        // 日本語では原文のまま（中断データに載る値と同じ）。
        #expect(DaifugoModel.localizedAction("8 8 8 8 革命！ 8切り！") == "8 8 8 8 革命！ 8切り！")
        #expect(DaifugoModel.localizedAction("パス") == "パス")
        // 組み立てに使う言い回しは、どれも英訳を持つ。
        for key in ["パス", "投了", "革命！", "革命返し！", "反則上がり", "あがり！", "（8切り）", "8切り！"] {
            #expect(GameDaifugo.tr.hasTranslation(key, language: .english), "\(key) に英訳が無い")
        }
    }

    @Test("CPU の席の読み上げは手番のときだけ「〜の番」を足す（#2495）")
    func seatLabelAnnouncesTurn() {
        let turn = DaifugoAccessibility.seatLabel(name: "CPU1", remaining: 5, action: "パス", isTurn: true)
        #expect(turn == "CPU1、残り5枚、パス、CPU1の番")
        let idle = DaifugoAccessibility.seatLabel(name: "CPU1", remaining: 5, action: "", isTurn: false)
        #expect(idle == "CPU1、残り5枚")
        #expect(GameDaifugo.tr("%@の番", "CPU1", language: .english) == "CPU1's turn")
    }
}
