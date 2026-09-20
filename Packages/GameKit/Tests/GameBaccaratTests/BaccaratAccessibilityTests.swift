import Testing
import Foundation
import GameKitTestSupport
@testable import GameBaccarat

/// VoiceOver の読み上げ文（#1044 と同じ形）。View を組まずに純関数だけを検める。
@Suite("バカラの読み上げ")
struct BaccaratAccessibilityTests {

    @Test("札はスートと数字で読む")
    func cardLabels() {
        #expect(BaccaratAccessibility.cardLabel(card: BaccaratCard(id: 0, suit: .hearts, rank: 7))
                == "ハートの7")
        // 0 点の絵札も、見た目どおり K として読む（点数に読み替えない）。
        let king = BaccaratAccessibility.cardLabel(card: BaccaratCard(id: 1, suit: .spades, rank: 13))
        #expect(!king.isEmpty)
        #expect(king != "0")
    }

    @Test("合計は何の合計かが分かる形で読む")
    func totalLabels() {
        #expect(BaccaratAccessibility.totalLabel(side: .player, total: 5) == "プレイヤーの合計5")
        #expect(BaccaratAccessibility.totalLabel(side: .banker, total: 9) == "バンカーの合計9")
    }

    @Test("賭け先ボタンは配当まで読む")
    func betChoiceLabels() {
        #expect(BaccaratAccessibility.betChoiceLabel(.banker) == "バンカーに賭ける、配当0.95倍")
        #expect(BaccaratAccessibility.betChoiceLabel(.tie) == "タイに賭ける、配当8倍")
    }

    /// 賭け先の表示は「賭け金がいくらになって返るか」の唯一の案内なので、
    /// 配当表（`baccaratChipDelta`）とずれていないことを実際の精算で確かめる。
    @Test("ボタンに出す配当の文言は、実際の精算と一致する")
    func payoutLabelsMatchTheSettlement() {
        #expect(baccaratChipDelta(bet: .player, outcome: .player, amount: 100) == 100)   // 1倍
        #expect(baccaratChipDelta(bet: .banker, outcome: .banker, amount: 100) == 95)    // 0.95倍
        #expect(baccaratChipDelta(bet: .tie, outcome: .tie, amount: 100) == 800)         // 8倍
        #expect(BaccaratBet.player.payoutLabel == "1倍")
        #expect(BaccaratBet.banker.payoutLabel == "0.95倍")
        #expect(BaccaratBet.tie.payoutLabel == "8倍")
    }

    /// 賭け先・ベット額のボタンは毎局必ず押すので、HIG の 44pt を割らせない（#709）。
    @Test("操作ボタンの高さは 44pt を下回らない")
    func actionButtonsKeepTheMinimumTapTarget() {
        #expect(BaccaratMetrics.actionButtonMinHeight >= 44)
        #expect(BaccaratMetrics.actionButtonMinHeight == BaccaratMetrics.minimumTapTarget)
    }

    /// 賭け先を選ぶ画面は色だけで状態を示さない（#220 と同じ理由）。
    @Test("選んでいる賭け先は文字でも示している")
    func selectedBetIsShownInText() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameBaccarat"))
        #expect(source.contains("\"ベット先\""), "賭けている先を文字で示していない")
        #expect(source.contains(".isSelected"), "VoiceOver へ選択状態を伝えていない")
    }
}
