import Testing
import Core
@testable import GameConcentration

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("神経衰弱: はじめての遊び方")
struct ConcentrationOnboardingTests {
    private let delay: UInt64 = 40_000_000

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(ConcentrationOnboarding.guide.isWellFormed)
        #expect(ConcentrationOnboarding.guide.gameID == "concentration")
    }

    @Test("同じ絵柄の 2 枚でペアになり、もう一度めくれる（手番は変わらない）")
    func matchKeepsTurn() {
        let model = ConcentrationModel(services: nil, autoClearDelay: delay)
        let a = 0
        let b = model.cards.indices.first { $0 != a && model.cards[$0].symbol == model.cards[a].symbol }!
        model.tap(index: a)
        model.tap(index: b)
        #expect(model.cards[a].isMatched && model.cards[b].isMatched)
        #expect(model.playerScore == 1)
        #expect(model.currentPlayer == .human)
    }

    @Test("ちがう絵柄なら、札は伏せ直されて CPU の番になる")
    func mismatchPassesTurn() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: delay)
        let a = 0
        let b = model.cards.indices.first { model.cards[$0].symbol != model.cards[a].symbol }!
        model.tap(index: a)
        model.tap(index: b)
        #expect(!model.mismatchedIndices.isEmpty)
        model.clearMismatch()
        #expect(!model.cards[a].isFaceUp && !model.cards[b].isFaceUp)
        #expect(model.currentPlayer == .cpu)
    }

#if DEBUG
    @Test("すべてのペアが取られたら終わり。多く取ったほうが勝ち、同数は引き分け")
    func finish() {
        let model = ConcentrationModel(services: nil, autoClearDelay: delay)
        #expect(!model.isGameOver)
        // 局面を差し替える撮影用フックは DEBUG だけにあり、テストでは使えるので結果の判定だけ確かめる。
        model.applyDebugScenario("result")
        #expect(model.isGameOver)
        let expected: ConcentrationPlayer? = model.playerScore > model.cpuScore ? .human
            : (model.cpuScore > model.playerScore ? .cpu : nil)
        #expect(model.winner == expected)
        #expect(model.isDraw == (model.playerScore == model.cpuScore))
    }
#endif

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in ConcentrationOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
