import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
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

    @Test("やり直しで配った 21 の演出中に離れても、再開すると結果画面に決着していて、やり直しは使用済みのまま（#2973）")
    func leavingDuringNaturalRevealAfterRetryResumesSettled() async throws {
        let seed = try #require((0..<5000 as Range<UInt64>).first { seed in
            let m = BlackjackModel(seed: seed)
            m.deal()
            return isBlackjack(m.dealerHand) || isBlackjack(m.playerHand)
        })
        let store = MemorySnapshotStore()
        // 「あなた 16 対 ディーラー 18」の 3 回目。スタンドして負け、広告でやり直す。
        let losing = makeBlackjackModel(
            blackjackSnapshot(player: [10, 6], dealer: [10, 8], deck: [],
                              completedRounds: 2, points: 2, streak: 2, handsWon: 2, handsLost: 0),
            store: store
        )
        losing.stand()
        #expect(losing.canRetryRound)
        // 結果画面のまま離れて、演出つき（待ちあり）の画面で開き直す。
        let model = BlackjackModel(
            services: GameServices(snapshots: store, ads: BlackjackStubAds()),
            seed: seed, dealerDrawInterval: .seconds(3600)
        )
        #expect(model.canRetryRound)

        let result = await model.retryRoundAfterAd()
        #expect(result == .granted)
        #expect(model.isRevealingNatural, "配ったのが 21 で、演出の待ちに入っている")

        // 待ちの途中で画面を離れた。保存は負けた回の結果画面のままではなく、配った回になっている。
        let resumed = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()), seed: 1)
        #expect(resumed.phase == .result)
        #expect(resumed.completedRounds == 3)
        #expect(resumed.hasUsedRetry)
        #expect(!resumed.canRetryRound, "やり直しは 1 回まで。中断を挟んでも戻らない")
    }
}
