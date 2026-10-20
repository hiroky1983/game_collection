import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// スプリット用に、同ランク2枚の手を注入して作る。
@MainActor
private func makeSplitReadyModel(rank: Int, dealer: [Int], deck: [Int]) -> BlackjackModel {
    makeInjectedModel(player: [rank, rank], dealer: dealer, deck: deck).0
}

@Suite("ブラックジャックのスプリット")
@MainActor
struct BlackjackSplitTests {

    @Test("同じ点数2枚のときだけ選べる")
    func onlyOnSameValuePair() {
        let pair = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9])
        #expect(pair.isSplitApplicable)

        // 点数が違えば割れない
        let mixed = makeInjectedModel(player: [9, 10], dealer: [10, 7], deck: [3, 9]).0
        #expect(!mixed.isSplitApplicable)
    }

    @Test("10・J・Q・K は10値同士なので割れる（#497）", arguments: [
        [10, 13], [11, 12], [10, 11], [12, 13],
    ])
    func splitsAcrossTenValueRanks(pair: [Int]) {
        let model = makeInjectedModel(player: pair, dealer: [10, 7], deck: [3, 9]).0

        #expect(model.isSplitApplicable)

        model.split()

        #expect(model.hands.count == 2)
        #expect(model.hands[0].cards.map(\.rank) == [pair[0], 3])
        #expect(model.hands[1].cards.map(\.rank) == [pair[1], 9])
    }

    @Test("10値と A は点数が違うので割れない（#497）")
    func doesNotSplitTenWithAce() {
        let model = makeInjectedModel(player: [1, 10], dealer: [10, 7], deck: [3, 9]).0
        #expect(!model.isSplitApplicable)
    }

    @Test("2ハンドに分かれ、1枚ずつ配る")
    func splitsIntoTwoHands() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9])

        model.split()

        #expect(model.hands.count == 2)
        #expect(model.hands.allSatisfy { $0.cards.count == 2 })
        #expect(model.hands[0].cards[1].rank == 3, "山札の先頭から順に配られる")
        #expect(model.hands[1].cards[1].rank == 9)
        #expect(model.activeHandIndex == 0, "1つ目の手から操作する")
        #expect(model.phase == .playerTurn)
    }

    @Test("再スプリットはできない")
    func cannotResplit() {
        // 8,8 を割った後、1つ目の手が 8,8 になる配り
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [8, 9])
        model.split()

        #expect(model.hands[0].cards.map(\.rank) == [8, 8])
        #expect(!model.isSplitApplicable, "同ランク2枚でも2手目以降は割れない")
        model.split()
        #expect(model.hands.count == 2)
    }

    @Test("2ハンドが順に進行する")
    func playsHandsInOrder() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9, 10, 2])
        model.split()

        #expect(model.activeHandIndex == 0)
        #expect(model.playerHand.map(\.rank) == [8, 3], "playerHand は操作中の手を指す")

        model.hit()  // ハンド1（8+3=11）に 10 → 21
        #expect(model.activeHandIndex == 0, "バストしない限り同じ手を続ける")
        #expect(model.playerValue == 21)

        model.stand()
        #expect(model.activeHandIndex == 1, "スタンドで次の手へ移る")
        #expect(model.playerHand.map(\.rank) == [8, 9])
        #expect(model.phase == .playerTurn, "2つ目が残っているのでまだ決着しない")

        model.stand()
        #expect(model.phase == .result, "両方終わればディーラーの番を経て決着する")
    }

    @Test("独立に判定される（片方勝ち・片方負けなら 1 点でまとめは勝ち）")
    func settlesEachHandIndependently() {
        // 8,8 を割り、1つ目は 8+10=18、2つ目は 8+3=11 のまま止める。ディーラーは 17。
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [10, 3])
        model.split()
        model.stand()   // ハンド1 = 18（勝ち）
        model.stand()   // ハンド2 = 11（負け）

        #expect(model.dealerValue == 17)
        #expect(model.hands[0].outcome == .win)
        #expect(model.hands[1].outcome == .lose)
        #expect(model.score == 1)
        #expect(model.outcome == .win, "まとめの表示は点で決める")
        #expect(model.reviewOutcome == .win)
    }

    @Test("両方勝てば 2 点")
    func winningBothScoresTwo() {
        // 10,10 を割り、それぞれ 10+9=19 / 10+9=19。ディーラーは 17。
        let model = makeSplitReadyModel(rank: 10, dealer: [10, 7], deck: [9, 9])
        model.split()
        model.stand()
        model.stand()

        #expect(model.hands.allSatisfy { $0.outcome == .win })
        #expect(model.score == 2)
        #expect(model.outcome == .win)
    }

    @Test("スプリットで作った21はナチュラルとして数えず、1 手 1 点")
    func splitTwentyOneIsNotNatural() {
        // A,A を割ると各手が A + 10 = 21 になるが、2 点にはしない。ディーラーは 20。
        let model = makeSplitReadyModel(rank: 1, dealer: [10, 10], deck: [13, 12])

        model.split()

        #expect(model.hands.allSatisfy { $0.value == 21 })
        #expect(model.hands.allSatisfy { $0.outcome == .win }, "ブラックジャックではなく通常の勝ち")
        #expect(model.score == 2, "1 点 × 2 手。ブラックジャックの 2 点 × 2 手（4 点）にはならない")
    }

    @Test("スプリットしたAは1枚ずつで強制スタンドする")
    func splitAcesDrawOnlyOneCard() {
        let model = makeSplitReadyModel(rank: 1, dealer: [10, 7], deck: [5, 5, 9, 9])

        model.split()

        #expect(model.hands.allSatisfy { $0.cards.count == 2 }, "Aに追加で引けない")
        #expect(model.hands.allSatisfy { $0.isDone })
        #expect(model.phase == .result, "操作を挟まずディーラーの番へ進む")
    }

    @Test("片方だけバストしても、もう片方は続く")
    func oneBustedHandDoesNotEndTheRound() {
        // 10,10 を割り、1つ目に 5 → 25 でバスト。2つ目は 10+9=19 で勝つ。
        let model = makeSplitReadyModel(rank: 10, dealer: [10, 7], deck: [10, 9, 5])
        model.split()

        model.hit()  // ハンド1 に 5 → 25
        #expect(model.hands[0].isBusted)
        #expect(model.phase == .playerTurn, "ラウンドはまだ終わらない")
        #expect(model.activeHandIndex == 1)

        model.stand()
        #expect(model.hands[0].outcome == .bust)
        #expect(model.hands[1].outcome == .win)
        #expect(model.score == 1)
    }

    @Test("両方バストならディーラーは引かない")
    func dealerStaysWhenAllHandsBust() {
        // 10,10 を割り、両方に 10 を足して 30 にする。ディーラーは 12（本来なら引く手）。
        let model = makeSplitReadyModel(rank: 10, dealer: [8, 4], deck: [10, 10, 10, 10, 5])
        model.split()
        model.hit()
        model.hit()

        #expect(model.hands.allSatisfy { $0.isBusted })
        #expect(model.dealerHand.count == 2, "全滅したのでディーラーは引かない")
        #expect(model.score == 0)
        #expect(model.outcome == .lose)
    }

    @Test("ダブルダウンは無い（操作の API を持たない）")
    func hasNoDoubleDown() throws {
        let view = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
        let model = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackModel.swift")
        #expect(!view.contains("doubleDown"))
        #expect(!model.contains("func doubleDown"))
    }
}

@Suite("ブラックジャックの中断データ")
@MainActor
struct BlackjackSnapshotTests {

    @Test("スプリット中に中断しても2つの手と進み具合が戻る")
    func restoresSplitHands() {
        let (model, store, _) = makeInjectedModel(
            player: [8, 8], dealer: [10, 7], deck: [3, 9, 5], roundsPlayed: 3, score: 2, streak: 1
        )
        model.split()
        model.stand()  // ハンド2 を操作中の状態で中断する

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: StubAdService()))
        #expect(reopened.hands.count == 2)
        #expect(reopened.activeHandIndex == 1)
        #expect(reopened.hands.map { $0.cards.map(\.rank) } == [[8, 3], [8, 9]])
        #expect(reopened.hands[0].isDone)
        #expect(reopened.roundsPlayed == 3)
        #expect(reopened.score == 2)
        #expect(reopened.streak == 1)
    }

    @Test("チップ制だった頃の中断データは読み飛ばし、点として読み違えない（#2552）")
    func ignoresChipEraSnapshot() {
        // 旧形式（チップと賭け金を持つ）。`roundsPlayed` などの鍵が無いのでデコードできない。
        let legacy = """
        {
          "playerHand": [{"id": 0, "suit": 0, "rank": 10}, {"id": 1, "suit": 1, "rank": 6}],
          "dealerHand": [{"id": 2, "suit": 2, "rank": 9}, {"id": 3, "suit": 3, "rank": 7}],
          "deck": [{"id": 4, "suit": 0, "rank": 5}],
          "chips": 900,
          "bet": 200,
          "phase": "playerTurn",
          "hands": [{"id": 0, "cards": [{"id": 0, "suit": 0, "rank": 10}, {"id": 1, "suit": 1, "rank": 6}],
                     "bet": 200, "isFromSplit": false, "isDoubled": false, "isDone": false}],
          "activeHandIndex": 0,
          "reviveCount": 2
        }
        """
        let store = MemorySnapshotStore()
        store.inject(Data(legacy.utf8), for: "blackjack")
        #expect(!BlackjackModule().hasResumableSnapshot(in: store), "続きから戻れる扱いにしない")

        let model = BlackjackModel(services: GameServices(snapshots: store, ads: StubAdService()))

        #expect(model.phase == .ready, "落ちずに配る前から始まる")
        #expect(model.hands.isEmpty)
        #expect(model.score == 0, "チップの 900 を点として読んでいない")
        #expect(model.roundsPlayed == 0)
    }

    @Test("チップ制だった頃の「賭け待ち」の中断データ（賭け金 0 の局）も読み飛ばす")
    func ignoresChipEraBetWaitingSnapshot() {
        let legacy = """
        {"playerHand": [], "dealerHand": [], "deck": [], "chips": 2000, "bet": 0, "phase": "betting",
         "hands": [], "activeHandIndex": 0, "hasRevivedThisSession": true, "reviveCount": 1}
        """
        let store = MemorySnapshotStore()
        store.inject(Data(legacy.utf8), for: "blackjack")

        let model = BlackjackModel(services: GameServices(snapshots: store, ads: StubAdService()))

        #expect(model.phase == .ready)
        #expect(model.score == 0)
    }
}

// MARK: - 既存の挙動が退行していないこと

@Suite("ブラックジャックの基本操作（#439 の退行防止）")
@MainActor
struct BlackjackBaselineTests {

    @Test("ヒットでバストすると即座に負けになり、ディーラーは引かない")
    func bustEndsRoundImmediately() {
        let model = makeInjectedModel(player: [10, 10], dealer: [8, 4], deck: [10]).0

        model.hit()

        #expect(model.outcome == .bust)
        #expect(model.score == 0)
        #expect(model.phase == .result)
        #expect(model.dealerHand.count == 2)
        #expect(model.reviewOutcome == .loss)
    }

    @Test("スタンドするとディーラーが17以上まで引く（S17）")
    func dealerHitsUntilSeventeen() {
        let model = makeInjectedModel(player: [10, 8], dealer: [5, 6], deck: [5, 4, 10]).0

        model.stand()

        #expect(model.dealerValue == 20, "11 → 16 → 20 で止まる")
        #expect(model.dealerHand.count == 4)
        #expect(model.outcome == .lose)
    }

    @Test("次のラウンドへ進むと手が空になり、配る前へ戻る")
    func nextRoundClearsTable() {
        let model = makeInjectedModel(player: [10, 8], dealer: [10, 7], deck: [5]).0
        model.stand()

        model.nextRound()

        #expect(model.hands.isEmpty)
        #expect(model.playerHand.isEmpty)
        #expect(model.phase == .ready)
        #expect(model.outcome == nil)
        #expect(model.score == 1, "18 対 17 で勝った 1 点は持ち越す")
        #expect(model.roundsPlayed == 1)
    }

    @Test("配ると、スプリットの可否が手札から決まる")
    func freshDealExposesOptions() {
        // 種によっては配った瞬間にナチュラルで決着して `.playerTurn` に入らないため、
        // 「たまたま検証されずに通る」ことが無いよう、手番になった種で必ず1回検証する。
        for seed in UInt64(1)...200 {
            let model = BlackjackModel(seed: seed)
            model.deal()
            guard model.phase == .playerTurn else { continue }

            let hand = model.playerHand
            #expect(hand.count == 2)
            #expect(model.isSplitApplicable == (hand[0].value == hand[1].value))
            return
        }
        Issue.record("配ってプレイヤーの手番になる種が 200 件の中に無かった")
    }

    @Test("同ランクが配られた種ではスプリットが提示される")
    func freshDealOffersSplitOnPair() {
        for seed in UInt64(1)...5000 {
            let model = BlackjackModel(seed: seed)
            model.deal()
            guard model.phase == .playerTurn,
                  model.playerHand[0].rank == model.playerHand[1].rank else { continue }

            #expect(model.isSplitApplicable)
            model.split()
            #expect(model.hands.count == 2)
            return
        }
        Issue.record("同ランク2枚が配られる種が 5000 件の中に無かった")
    }

    @Test("ランク違いの10値2枚が配られた種でもスプリットが提示される（#497）")
    func freshDealOffersSplitOnMixedTenValuePair() {
        for seed in UInt64(1)...5000 {
            let model = BlackjackModel(seed: seed)
            model.deal()
            let hand = model.playerHand
            guard model.phase == .playerTurn,
                  hand[0].rank != hand[1].rank,
                  hand[0].value == 10, hand[1].value == 10 else { continue }

            #expect(model.isSplitApplicable)
            model.split()
            #expect(model.hands.count == 2)
            return
        }
        Issue.record("ランク違いの10値2枚が配られる種が 5000 件の中に無かった")
    }
}
