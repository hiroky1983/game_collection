import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameAnzan

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("ぱっと暗算: はじめての遊び方")
struct AnzanOnboardingTests {
    private func makeModel(_ name: String) -> AnzanModel {
        let suite = "asobiba.anzan.onboarding.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: PlayLog(defaults: defaults))
        return AnzanModel(services: services, seed: 2826)
    }

    /// 表示を最後まで進め、見せた数を返す。
    private func flashThrough(_ model: AnzanModel) -> [Int] {
        var shown: [Int] = []
        while model.advanceDisplay() != nil {
            if let number = model.displayedNumber { shown.append(number) }
        }
        return shown
    }

    private func answer(_ value: Int, _ model: AnzanModel) {
        for character in String(value) { model.tapDigit(Int(String(character))!) }
        model.submit()
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(AnzanOnboarding.guide.isWellFormed)
        #expect(AnzanOnboarding.guide.gameID == AnzanModel.gameID)
        #expect(AnzanOnboarding.guide.gameID == AnzanModule().id)
    }

    @Test("目的の図: 図の数を全部足した式と合計。誤答の図の数は合計と違う")
    func sumFigure() {
        let numbers = AnzanHowToFigures.numbers
        #expect(AnzanLogic.expression(numbers) == "3 + 7 + 5 = 15")
        #expect(AnzanLogic.sum(numbers) == 15, "テンキーの図は 15 を入れている")
        #expect(AnzanOnboarding.wrongAnswer != AnzanLogic.sum(numbers))
    }

    @Test("数は 1 つずつ出ては消え（間に空白）、最後の数が消えてから入力に移る")
    func flashOneByOne() {
        let model = makeModel("flash")
        model.start(.standard)
        #expect(AnzanLogic.steps(count: 3) == [.ready, .number(0), .blank, .number(1), .blank, .number(2), .blank])
        let shown = flashThrough(model)
        #expect(shown == model.numbers)
        #expect(model.phase == .answering)
    }

    @Test("難易度: 桁数は 1〜3 桁、個数は 5・10・15 個。初めは 1 桁・5 個・ゆっくり")
    func difficulty() {
        #expect(AnzanDigits.allCases.map(\.rawValue) == [1, 2, 3])
        #expect(AnzanCount.allCases.map(\.rawValue) == [5, 10, 15])
        #expect(AnzanSettings.standard == AnzanSettings(digits: .one, count: .five, speed: .slow))
        #expect(AnzanSpeed.slow.label == "ゆっくり")
    }

    @Test("正解すると連続正解が伸び、間違えると 0 に戻る。見直しは答える前に 1 問 1 回")
    func streakAndReplay() {
        let model = makeModel("streak")
        model.start(.standard)
        _ = flashThrough(model)
        answer(model.sum, model)
        #expect(model.isCorrect)
        #expect(model.streak == 1)

        model.next()
        _ = flashThrough(model)
        #expect(model.canReplay)
        #expect(model.replayAfterAd(forGame: model.questionSerial))
        let replayed = flashThrough(model)
        #expect(replayed == model.numbers, "同じ数をもう一度見せる")
        #expect(!model.canReplay, "1 問 1 回")
        answer(model.sum + 1, model)
        #expect(!model.isCorrect)
        #expect(model.streak == 0)
        #expect(!model.canReplay, "答えたあとは見直せない")
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in AnzanOnboarding.guide.texts + ["せいかい！", "ざんねん…", "決定", "桁数", "個数", "速さ"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
