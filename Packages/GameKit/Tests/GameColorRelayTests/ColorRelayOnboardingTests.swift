import Testing
import Foundation
import Core
@testable import GameColorRelay
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("いろリレー: はじめての遊び方")
struct ColorRelayOnboardingTests {
    private func makeModel() -> ColorRelayModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        return ColorRelayModel(services: services, cpuDelay: .zero, seed: 42)
    }

    /// あなた以外の 3 人は、番が回ってきても動かない（手を出さない）ように見る側なので、手札だけ持たせる。
    private func others() -> [[RelayCard]] {
        (1...3).map { i in [card(.purple, .number(i)), card(.yellow, .number(i + 3))] }
    }

    /// 手札・場の札に使っていない札から作る山。
    private func pile(excluding used: [RelayCard]) -> [RelayCard] {
        let ids = Set(used.map(\.id))
        return Array(RelayCard.makeDeck().filter { !ids.contains($0.id) }.prefix(20))
    }

    private func setUp(_ model: ColorRelayModel, you: [RelayCard], top: RelayCard) {
        let hands = [you] + others()
        model.configureForTesting(hands: hands, top: top, drawPile: pile(excluding: hands.flatMap { $0 } + [top]))
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(ColorRelayOnboarding.guide.isWellFormed)
        #expect(ColorRelayOnboarding.guide.gameID == "colorrelay")
    }

    @Test("出せる札: 同じ色か同じ数字・記号。色も数字もちがう札は出せない。万能札はどの札にも出せる")
    func playable() {
        let top = card(.red, .number(5))
        #expect(ColorRelayRules.canPlay(card(.red, .number(8)), onto: top, activeColor: .red))
        #expect(ColorRelayRules.canPlay(card(.green, .number(5)), onto: top, activeColor: .red))
        #expect(!ColorRelayRules.canPlay(card(.purple, .number(8)), onto: top, activeColor: .red))
        #expect(ColorRelayRules.canPlay(card(nil, .wild), onto: top, activeColor: .red))
        #expect(ColorRelayRules.canPlay(card(nil, .wildDrawFour), onto: top, activeColor: .red))
    }

    @Test("最初の手札は 7 枚")
    func initialHand() {
        #expect(ColorRelayRules.initialHandCount == 7)
        let model = makeModel()
        model.startGame()
        #expect(model.playerHand.count == ColorRelayRules.initialHandCount)
    }

    @Test("とばしは次の人の番を飛ばし、ぎゃくは向きを逆にする")
    func skipAndReverse() {
        let skip = makeModel()
        setUp(skip, you: [card(.red, .skip), card(.green, .number(1))], top: card(.red, .number(7)))
        skip.toggleSelection(card(.red, .skip))
        skip.playSelected()
        #expect(skip.currentPlayer == 2, "次の人（1）を飛ばして 2 の番")

        let reverse = makeModel()
        setUp(reverse, you: [card(.red, .reverse), card(.green, .number(1))], top: card(.red, .number(7)))
        reverse.toggleSelection(card(.red, .reverse))
        reverse.playSelected()
        #expect(!reverse.isClockwise)
        #expect(reverse.currentPlayer == 3, "逆回りなので 0 の次は 3")
    }

    @Test("+2 は次の人が 2 枚引き、いろがえ+4 は 4 枚引く。引いた人は番を飛ばされる")
    func penalties() {
        #expect(RelayKind.drawTwo.penalty == 2)
        #expect(RelayKind.wildDrawFour.penalty == 4)
        let model = makeModel()
        setUp(model, you: [card(.red, .drawTwo), card(.green, .number(1))], top: card(.red, .number(7)))
        model.toggleSelection(card(.red, .drawTwo))
        model.playSelected()
        #expect(model.pendingDraw == 2)
        #expect(model.currentPlayer == 1)
    }

    @Test("いろがえは次の色を選べる")
    func wildChoosesColor() {
        let model = makeModel()
        setUp(model, you: [card(nil, .wild), card(.green, .number(1))], top: card(.red, .number(7)))
        model.toggleSelection(card(nil, .wild))
        model.playSelected(color: .yellow)
        #expect(model.activeColor == .yellow)
    }

    @Test("手札を先になくした人が勝つ")
    func win() {
        let model = makeModel()
        setUp(model, you: [card(.red, .number(3))], top: card(.red, .number(7)))
        model.toggleSelection(card(.red, .number(3)))
        model.playSelected()
        #expect(model.phase == .result)
        #expect(model.playerHand.isEmpty)
    }

    @Test("文言の数字（最初の手札の枚数）が実装の値から作られ、全部の文言に英語の訳がある")
    func numbersAndEnglish() {
        let key = "配られた %lld 枚の手札を、先になくした人の勝ちです。"
        let lines = ColorRelayOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("配られた \(ColorRelayRules.initialHandCount) 枚の手札を、先になくした人の勝ちです。"))
        #expect(tr.hasTranslation(key, language: .english))
        let filled = tr(key, ColorRelayRules.initialHandCount)
        for text in ColorRelayOnboarding.guide.texts where text != filled {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
