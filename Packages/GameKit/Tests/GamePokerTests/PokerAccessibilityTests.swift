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
        PokerPhase.idle, .dealing, .betting1, .cpuExchange, .betting2, .showdown, .result,
    ])
    func selectionIsNotReadOutsideExchange(phase: PokerPhase) {
        #expect(
            PokerAccessibility.handCardLabel(card: sevenOfHearts, isSelected: true, phase: phase)
                == "ハートの7"
        )
    }

    @Test("選択のヒントは交換フェーズでだけ出す", arguments: [
        PokerPhase.idle, .dealing, .betting1, .exchange, .cpuExchange, .betting2, .showdown, .result,
    ])
    func hintOnlyInExchange(phase: PokerPhase) {
        let hint = PokerAccessibility.handCardHint(phase: phase)
        #expect(PokerAccessibility.acceptsSelection(phase: phase) == (phase == .exchange))
        #expect(hint.isEmpty == (phase != .exchange))
    }
}
