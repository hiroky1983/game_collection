import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 同じ点数 2 枚の手を中断データから作る。
@MainActor
private func splitReady(rank: Int, dealer: [Int], deck: [Int]) -> BlackjackModel {
    makeBlackjackModel(blackjackSnapshot(player: [rank, rank], dealer: dealer, deck: deck))
}

@MainActor
private func dealt(player: [Int], dealer: [Int], deck: [Int]) -> BlackjackModel {
    makeBlackjackModel(blackjackSnapshot(player: player, dealer: dealer, deck: deck))
}

@Suite("ブラックジャックのスプリット（#439・#2552 で勝ち点制）")
@MainActor
struct BlackjackSplitTests {

    @Test("同じ点数2枚のときだけ選べる")
    func onlyOnSameValuePair() {
        #expect(splitReady(rank: 8, dealer: [10, 7], deck: [3, 9]).canSplit)
        #expect(!dealt(player: [9, 10], dealer: [10, 7], deck: [3, 9]).canSplit, "点数が違えば割れない")
    }

    @Test("10・J・Q・K は10値同士なので割れる（#497）", arguments: [
        [10, 13], [11, 12], [10, 11], [12, 13],
    ])
    func splitsAcrossTenValueRanks(pair: [Int]) {
        let model = dealt(player: pair, dealer: [10, 7], deck: [3, 9])
        #expect(model.canSplit)

        model.split()

        #expect(model.hands.count == 2)
        #expect(model.hands[0].cards.map(\.rank) == [pair[0], 3])
        #expect(model.hands[1].cards.map(\.rank) == [pair[1], 9])
    }

    @Test("10値と A は点数が違うので割れない（#497）")
    func doesNotSplitTenWithAce() {
        #expect(!dealt(player: [1, 10], dealer: [10, 7], deck: [3, 9]).canSplit)
    }

    @Test("2ハンドに分かれ、1枚ずつ配られて 1 つ目から操作する")
    func splitsIntoTwoHands() {
        let model = splitReady(rank: 8, dealer: [10, 7], deck: [3, 9])

        model.split()

        #expect(model.hands.count == 2)
        #expect(model.hands.allSatisfy { $0.cards.count == 2 && $0.isFromSplit })
        #expect(model.hands[0].cards[1].rank == 3, "山札の先頭から順に配られる")
        #expect(model.hands[1].cards[1].rank == 9)
        #expect(model.activeHandIndex == 0)
        #expect(model.phase == .playerTurn)
    }

    @Test("再スプリットはできない")
    func cannotResplit() {
        let model = splitReady(rank: 8, dealer: [10, 7], deck: [8, 9])
        model.split()

        #expect(model.hands[0].cards.map(\.rank) == [8, 8])
        #expect(!model.canSplit, "同ランク2枚でも2手目以降は割れない")
        model.split()
        #expect(model.hands.count == 2)
    }

    @Test("2ハンドが順に進行する")
    func playsHandsInOrder() {
        let model = splitReady(rank: 8, dealer: [10, 7], deck: [3, 9, 10, 2])
        model.split()
        #expect(model.playerHand.map(\.rank) == [8, 3], "playerHand は操作中の手を指す")

        model.hit()
        #expect(model.activeHandIndex == 0, "バストしない限り同じ手を続ける")
        #expect(model.playerValue == 21)

        model.stand()
        #expect(model.activeHandIndex == 1)
        #expect(model.phase == .playerTurn, "2つ目が残っているのでまだ決着しない")

        model.stand()
        #expect(model.phase == .result)
    }

    @Test("分けた手はそれぞれ勝てば 1 点。片方勝ち・片方負けなら 1 点で、まとめは勝ち")
    func eachSplitHandScoresIndependently() {
        // 8,8 を割り、1つ目は 8+10=18（勝ち）、2つ目は 8+3=11（負け）。ディーラーは 17。
        let model = splitReady(rank: 8, dealer: [10, 7], deck: [10, 3])
        model.split()
        model.stand()
        model.stand()

        #expect(model.hands[0].outcome == .win)
        #expect(model.hands[1].outcome == .lose)
        #expect(model.roundPoints == 1)
        #expect(model.points == 1)
        #expect(model.outcome == .win, "勝ち点が入った回は勝ちとして見せる")
        #expect(model.streak == 1)
        #expect(!model.canRetryRound, "勝ち点が入った回はやり直しの対象ではない")
    }

    @Test("両方勝てば 2 点")
    func winningBothScoresTwo() {
        let model = splitReady(rank: 10, dealer: [10, 7], deck: [9, 9])
        model.split()
        model.stand()
        model.stand()

        #expect(model.hands.allSatisfy { $0.outcome == .win })
        #expect(model.points == 2)
        #expect(model.outcome == .win)
    }

    @Test("スプリットで作った21はブラックジャックにしない（1 点ずつ）")
    func splitTwentyOneIsNotNatural() {
        // A,A を割ると各手が A + 10 = 21。ディーラーは 20。
        let model = splitReady(rank: 1, dealer: [10, 10], deck: [13, 12])

        model.split()

        #expect(model.hands.allSatisfy { $0.value == 21 })
        #expect(model.hands.allSatisfy { $0.outcome == .win }, "ブラックジャックではなく通常の勝ち")
        #expect(model.points == 2, "ブラックジャック扱い（2 点ずつ＝4 点）にはならない")
    }

    @Test("スプリットしたAは1枚ずつで強制スタンドする")
    func splitAcesDrawOnlyOneCard() {
        let model = splitReady(rank: 1, dealer: [10, 7], deck: [5, 5, 9, 9])

        model.split()

        #expect(model.hands.allSatisfy { $0.cards.count == 2 }, "Aに追加で引けない")
        #expect(model.hands.allSatisfy { $0.isDone })
        #expect(model.phase == .result, "操作を挟まずディーラーの番へ進む")
    }

    @Test("片方だけバストしても、もう片方は続く")
    func oneBustedHandDoesNotEndTheRound() {
        let model = splitReady(rank: 10, dealer: [10, 7], deck: [10, 9, 5])
        model.split()

        model.hit()
        #expect(model.hands[0].isBusted)
        #expect(model.phase == .playerTurn)
        #expect(model.activeHandIndex == 1)

        model.stand()
        #expect(model.hands[0].outcome == .bust)
        #expect(model.hands[1].outcome == .win)
        #expect(model.points == 1)
    }

    @Test("両方バストならディーラーは引かず、0 点で負けた回になる")
    func dealerStaysWhenAllHandsBust() {
        let model = splitReady(rank: 10, dealer: [8, 4], deck: [10, 10, 10, 10, 5])
        model.split()
        model.hit()
        model.hit()

        #expect(model.hands.allSatisfy { $0.isBusted })
        #expect(model.dealerHand.count == 2, "全滅したのでディーラーは引かない")
        #expect(model.points == 0)
        #expect(model.outcome == .lose)
        #expect(model.canRetryRound)
    }

    @Test("片方引き分け・片方負けの回は 0 点の負け（やり直せる）")
    func pushAndLoseIsALostRound() {
        // 10,10 を割り、1つ目 10+7=17（引き分け）、2つ目 10+6=16（負け）。ディーラーは 17。
        let model = splitReady(rank: 10, dealer: [10, 7], deck: [7, 6])
        model.split()
        model.stand()
        model.stand()

        #expect(model.hands.map(\.outcome) == [.push, .lose])
        #expect(model.roundPoints == 0)
        #expect(model.outcome == .lose)
        #expect(model.canRetryRound)
    }

    @Test("スプリット中に中断しても2つの手が戻る")
    func restoresSplitHands() {
        let store = MemorySnapshotStore()
        let first = makeBlackjackModel(blackjackSnapshot(player: [8, 8], dealer: [10, 7], deck: [3, 9, 5]), store: store)
        first.split()
        first.stand()
        #expect(first.activeHandIndex == 1)

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()))
        #expect(reopened.hands.count == 2)
        #expect(reopened.activeHandIndex == 1)
        #expect(reopened.hands[0].isDone)
        #expect(reopened.phase == .playerTurn)
    }
}

@Suite("ブラックジャックの基本操作（#439 の退行防止）")
@MainActor
struct BlackjackBasicActionTests {

    @Test("ヒットでバストすると即座に負けになり、ディーラーは引かない")
    func hitBustEndsRound() {
        let model = dealt(player: [10, 6], dealer: [10, 2], deck: [10, 5])
        model.hit()
        #expect(model.phase == .result)
        #expect(model.outcome == .bust)
        #expect(model.dealerHand.count == 2)
    }

    @Test("スタンドするとディーラーが17以上まで引く（S17）")
    func dealerDrawsToSeventeen() {
        let model = dealt(player: [10, 8], dealer: [10, 2], deck: [2, 2, 3])
        model.stand()
        #expect(model.dealerValue >= 17)
        #expect(model.dealerHand.map(\.rank) == [10, 2, 2, 2, 3])
    }

    @Test("ダブルダウン・インシュアランスの口はモデルに無い（#2552）")
    func noDoubleDownOrInsurance() throws {
        let source = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackModel.swift")
        #expect(!source.contains("func doubleDown"))
        #expect(!source.contains("isDoubled"))
        #expect(!source.lowercased().contains("insurance"))
    }
}
