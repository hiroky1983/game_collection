import Testing
import Foundation
import Core
@testable import GameBlackjack

/// 配った時点のディーラーのナチュラル判定（#1377）。
/// 配りは乱数なので、シードを走査して「ディーラーだけが 2 枚 21」の局と「両者ナチュラル」の局を見つける。
@MainActor
struct BlackjackDealerNaturalTests {
    private func dealt(seed: UInt64, bet: Int = 100) -> BlackjackModel {
        let model = BlackjackModel(seed: seed)
        model.placeBet(bet)
        return model
    }

    @Test("ディーラーだけがナチュラルなら配った時点で精算し、賭け金だけ負ける")
    func dealerOnlyNaturalSettlesAtDeal() throws {
        let found = (0..<5000).lazy.map { self.dealt(seed: $0) }.first {
            isBlackjack($0.dealerHand) && !isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .result)
        #expect(model.outcome == .lose)
        #expect(model.chips == 1000 - 100)
    }

    @Test("両者ナチュラルならプッシュで賭け金は動かない")
    func bothNaturalPushes() throws {
        let found = (0..<200_000).lazy.map { self.dealt(seed: $0) }.first {
            isBlackjack($0.dealerHand) && isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .result)
        #expect(model.outcome == .push)
        #expect(model.chips == 1000)
    }

    @Test("ディーラーがナチュラルでなければ従来どおりプレイヤーの手番になる")
    func noNaturalContinues() throws {
        let found = (0..<5000).lazy.map { self.dealt(seed: $0) }.first {
            !isBlackjack($0.dealerHand) && !isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .playerTurn)
    }
}
