import Testing
@testable import GamePoker

/// ポーカーの手札の読み上げ文（#710）。
///
/// 捨てる札の選択は見た目では枠色と浮き沈みでしか分からないので、交換フェーズでは
/// 選択中かどうかを読み、ほかのフェーズでは選べることを案内しない。
struct PokerAccessibilityTests {

    private let aceOfSpades = PokerCard(id: 0, suit: .spades, rank: 14)
    private let sevenOfHearts = PokerCard(id: 1, suit: .hearts, rank: 7)

    @Test("交換フェーズで選択中の札は「捨てる札に選択中」と読む")
    func selectedCardInExchange() {
        #expect(
            PokerAccessibility.handCardLabel(card: sevenOfHearts, isSelected: true, phase: .exchange)
                == "ハートの7、捨てる札に選択中"
        )
    }

    @Test("交換フェーズで選んでいない札は札の名前だけを読む（A は 14 ではなく A と読む）")
    func unselectedCardInExchange() {
        #expect(
            PokerAccessibility.handCardLabel(card: aceOfSpades, isSelected: false, phase: .exchange)
                == "スペードのA"
        )
    }

    @Test("交換フェーズ以外では選択の状態を読まない", arguments: [
        PokerPhase.idle, .drawn, .result,
    ])
    func selectionIsNotReadOutsideExchange(phase: PokerPhase) {
        #expect(
            PokerAccessibility.handCardLabel(card: sevenOfHearts, isSelected: true, phase: phase)
                == "ハートの7"
        )
    }

    @Test("役一覧の見本 5 枚は札の名前を順に 1 つの文で読む")
    func handGuideCardsLabel() {
        let cards = [aceOfSpades, sevenOfHearts]
        #expect(PokerAccessibility.handGuideCardsLabel(cards: cards) == "スペードのA、ハートの7")
    }

    @Test("選択のヒントは交換フェーズでだけ出す", arguments: [
        PokerPhase.idle, .exchange, .drawn, .result,
    ])
    func hintOnlyInExchange(phase: PokerPhase) {
        let hint = PokerAccessibility.handCardHint(phase: phase)
        #expect(PokerAccessibility.acceptsSelection(phase: phase) == (phase == .exchange))
        #expect(hint.isEmpty == (phase != .exchange))
    }

    @Test("上の帯は回数と点を 1 文で読む（#2551）") func scoreboardLabel() {
        #expect(PokerAccessibility.scoreboardLabel(round: 3, playerPoints: 12, cpuPoints: 8)
                == "3回目 / 10、合計12点、CPU 8点")
    }

    @Test("決着時の役名は「主体、役名、勝敗」の 1 文で読む（#2589）")
    func handRankLabelWithVerdict() {
        #expect(
            PokerAccessibility.handRankLabel(subject: "あなた", rank: .threeOfAKind, side: .player, winner: .player)
                == "あなた、\(PokerHandRank.threeOfAKind.description)、勝ち！"
        )
        #expect(
            PokerAccessibility.handRankLabel(subject: "CPU", rank: .twoPair, side: .cpu, winner: .player)
                == "CPU、\(PokerHandRank.twoPair.description)、負け"
        )
        #expect(
            PokerAccessibility.handRankLabel(subject: "CPU", rank: .twoPair, side: .cpu, winner: .tie)
                == "CPU、\(PokerHandRank.twoPair.description)、引き分け"
        )
    }

    @Test("勝敗の印を出さないショーダウンでは主体と役名だけを読む")
    func handRankLabelWithoutVerdict() {
        #expect(
            PokerAccessibility.handRankLabel(subject: "あなた", rank: .flush, side: .player, winner: nil)
                == "あなた、\(PokerHandRank.flush.description)"
        )
    }
}
