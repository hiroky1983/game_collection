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

    @Test("勝敗の読み上げは結果ごとに違う文で、負け・引き分けを勝ちと取り違えない", arguments: [
        (BlackjackOutcome.playerBlackjack, "ブラックジャック！勝ちです"),
        (.win, "勝ちです"),
        (.push, "引き分けです"),
        (.lose, "負けです"),
        (.bust, "バストして負けです"),
    ])
    func outcomeAnnouncement(outcome: BlackjackOutcome, expected: String) {
        #expect(BlackjackAccessibility.outcomeAnnouncement(outcome: outcome) == expected)
    }

    @Test("スプリットしたラウンドは収支のまとめであることを添える")
    func splitOutcomeAnnouncement() {
        #expect(BlackjackAccessibility.outcomeAnnouncement(outcome: .win, isSplit: true)
                == "全体の結果は、勝ちです")
    }

    @Test("合計は誰の・何点かを 1 文で読む") func totalLabel() {
        #expect(BlackjackAccessibility.totalLabel(owner: "あなた", value: 17) == "あなたの合計17")
        #expect(BlackjackAccessibility.totalLabel(owner: "ハンド2", value: 21) == "ハンド2の合計21")
    }

    @Test("21 を超えたらバストと読む（赤色だけの伝達にしない）") func totalLabelBust() {
        #expect(BlackjackAccessibility.totalLabel(owner: "ディーラー", value: 22) == "ディーラーの合計22、バスト")
        #expect(!BlackjackAccessibility.totalLabel(owner: "あなた", value: 21).contains("バスト"))
    }

    @Test("10 回勝負の進み具合は回・点・連勝を 1 文で読む（連勝は 2 以上のときだけ）") func statusLabel() {
        #expect(BlackjackAccessibility.statusLabel(round: 3, rounds: 10, score: 2, streak: 0)
                == "第3回、10回中。合計2点")
        #expect(BlackjackAccessibility.statusLabel(round: 3, rounds: 10, score: 2, streak: 1)
                == "第3回、10回中。合計2点")
        #expect(BlackjackAccessibility.statusLabel(round: 3, rounds: 10, score: 4, streak: 3)
                == "第3回、10回中。合計4点、3連勝")
    }
}
