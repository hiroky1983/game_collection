import Testing
@testable import GameSevens

@Suite("七並べの読み上げ文")
struct SevensAccessibilityTests {

    @Test("カード名はスートとランクの読みを組み合わせる")
    func cardNameCombinesSuitAndRank() {
        let card = SevensCard(id: 0, suit: .hearts, rank: 12)
        #expect(SevensAccessibility.cardName(card) == "ハートのクイーン")
    }

    @Test("手札の読み上げは出せるかどうかを伝える")
    func handCardLabelStatesPlayability() {
        let card = SevensCard(id: 0, suit: .spades, rank: 7)
        #expect(SevensAccessibility.handCardLabel(card, canPlay: true).contains("出せます"))
        #expect(SevensAccessibility.handCardLabel(card, canPlay: false).contains("いまは出せません"))
    }

    @Test("場の読み上げは未着手と開通済みで文言が変わる")
    func suitRowLabelReflectsRange() {
        #expect(SevensAccessibility.suitRowLabel(.diamonds, range: SevensSuitRange()) == "ダイヤ、まだ出ていません")
        #expect(SevensAccessibility.suitRowLabel(.diamonds, range: SevensSuitRange(low: 7, high: 7)) == "ダイヤ、7だけ")
        #expect(SevensAccessibility.suitRowLabel(.diamonds, range: SevensSuitRange(low: 5, high: 9)) == "ダイヤ、5から9まで")
    }
}
