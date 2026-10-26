import Testing
import Foundation
import Core
@testable import GameBlackjack

/// 配った時点のディーラーのナチュラル判定（#1377）。
/// 配りは乱数なので、シードを走査して「ディーラーだけが 2 枚 21」の局と「両者ナチュラル」の局を見つける。
@MainActor
struct BlackjackDealerNaturalTests {
    private func dealt(seed: UInt64) -> BlackjackModel {
        let model = BlackjackModel(seed: seed)
        model.deal()
        return model
    }

    @Test("ディーラーだけがナチュラルなら配った時点で決着し、0 点の負け")
    func dealerOnlyNaturalSettlesAtDeal() throws {
        let found = (0..<5000).lazy.map { self.dealt(seed: $0) }.first {
            isBlackjack($0.dealerHand) && !isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .result)
        #expect(model.outcome == .lose)
        #expect(model.points == 0)
        #expect(model.completedRounds == 1)
    }

    @Test("両者ナチュラルならプッシュで 0 点")
    func bothNaturalPushes() throws {
        let found = (0..<200_000).lazy.map { self.dealt(seed: $0) }.first {
            isBlackjack($0.dealerHand) && isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .result)
        #expect(model.outcome == .push)
        #expect(model.points == 0)
    }

    @Test("ディーラーがナチュラルでなければ従来どおりプレイヤーの手番になる")
    func noNaturalContinues() throws {
        let found = (0..<5000).lazy.map { self.dealt(seed: $0) }.first {
            !isBlackjack($0.dealerHand) && !isBlackjack($0.playerHand)
        }
        let model = try #require(found)
        #expect(model.phase == .playerTurn)
    }

    @Test("画面用の間があるときは、21 が出た回も一度プレイヤーの手番のまま伏せ札を残し、待ってから決着する（#2700）")
    func naturalHoldsHoleCardBeforeResolving() async throws {
        let seed = try #require((0..<5000 as Range<UInt64>).first { seed in
            let m = BlackjackModel(seed: seed)
            m.deal()
            return isBlackjack(m.dealerHand) && !isBlackjack(m.playerHand)
        })
        let model = BlackjackModel(seed: seed, dealerDrawInterval: .milliseconds(1))
        model.deal()
        #expect(model.phase == .playerTurn)
        #expect(model.isRevealingNatural)
        model.hit()
        #expect(model.playerHand.count == 2) // 待ちのあいだは操作を受けない
        await model.dealerTask?.value
        #expect(model.phase == .result)
        #expect(!model.isRevealingNatural)
        #expect(model.outcome == .lose)
    }
}
