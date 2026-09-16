import Testing
import Core
@testable import GameBlackjack

/// カードと点数の読み上げ文（#1044）。
@Suite("ブラックジャック: 読み上げ文")
struct BlackjackAccessibilityTests {

    @Test("表の札はスートとランクを読む", arguments: [
        (BlackjackSuit.hearts, 7, "ハートの7"),
        (.spades, 1, "スペードのA"),
        (.clubs, 12, "クラブのQ"),
        (.diamonds, 10, "ダイヤの10"),
    ])
    func faceUp(suit: BlackjackSuit, rank: Int, expected: String) {
        let card = BlackjackCard(id: 0, suit: suit, rank: rank)
        #expect(BlackjackAccessibility.cardLabel(card: card, faceUp: true) == expected)
    }

    @Test("伏せた札は中身を読まない")
    func faceDownHidesCard() {
        let card = BlackjackCard(id: 0, suit: .spades, rank: 1)
        let label = BlackjackAccessibility.cardLabel(card: card, faceUp: false)
        #expect(label == "伏せたカード")
        #expect(!label.contains("スペード") && !label.contains("A"), "伏せ札のスートもランクも漏らさない")
    }

    @Test("伏せ札があるあいだのディーラーの点数は、記号ではなく文で読む")
    func dealerPartialValue() {
        #expect(BlackjackAccessibility.dealerPartialValueLabel(visibleValue: 7)
                == "見えているカードの合計7、1枚は伏せています")
    }
}
