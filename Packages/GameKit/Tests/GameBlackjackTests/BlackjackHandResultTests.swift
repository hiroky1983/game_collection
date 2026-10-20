import Testing
import Foundation
import SwiftUI
import Core
@testable import GameBlackjack
import CoreTestSupport

private final class SilentAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// プレイヤーのターンの中断データを注入して復元する（配りが乱数なので手札を決め打ちするため）。
@MainActor
private func makeModel(player: [Int], dealer: [Int], deck: [Int],
                       hands: [BlackjackHand]? = nil) -> BlackjackModel {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make(player)
    let restored = hands ?? [BlackjackHand(id: 0, cards: playerCards)]
    let store = MemorySnapshotStore()
    let snapshot = BlackjackSnapshot(
        dealerHand: make(dealer), deck: make(deck),
        phase: .playerTurn, hands: restored, activeHandIndex: 0,
        roundsPlayed: 0, score: 0, streak: 0, retryUsed: false,
        winsInMatch: 0, lossesInMatch: 0, bestStreak: 0
    )
    try? store.save(snapshot, for: "blackjack")
    return BlackjackModel(services: GameServices(snapshots: store, ads: SilentAdService()))
}

@Suite("ブラックジャックの 1 ラウンドの決着表示（#1754）")
@MainActor
struct BlackjackHandResultTests {

    @Test("決着するまでは出さない")
    func nilBeforeResult() {
        let model = makeModel(player: [10, 8], dealer: [10, 7], deck: [])
        #expect(model.handResult == nil)
    }

    @Test("勝つと +1 点。点数の対比が理由に出る")
    func win() throws {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "あなた19 対 ディーラー17（+1点）")
        #expect(result.chipDelta == nil, "賭けをなくしたのでチップの増減は出さない")
        #expect(model.roundPoints == 1)
    }

    @Test("バストすると負け。理由に点数が出る")
    func bust() throws {
        let model = makeModel(player: [10, 6], dealer: [10, 7], deck: [10])
        model.hit()
        let result = try #require(model.handResult)

        #expect(result.kind == .lose)
        #expect(result.reason == "バスト（26）")
        #expect(model.roundPoints == 0)
    }

    @Test("ディーラーがバストして勝つ")
    func dealerBust() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 6], deck: [10])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.reason == "ディーラーがバスト（26）（+1点）")
    }

    @Test("同点は引き分けで 0 点")
    func push() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 8], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .draw)
        #expect(model.roundPoints == 0)
        #expect(result.chipText == nil)
    }

    @Test("スプリットで手ごとに勝敗が割れても、見出し・点・内訳が一致する")
    func splitMixed() throws {
        // ハンド1: 20（勝ち）/ ハンド2: 12（負け）。ディーラーは 17 で止まる。
        let hands = [
            BlackjackHand(id: 0, cards: cards([10, 10], from: 0), isFromSplit: true),
            BlackjackHand(id: 1, cards: cards([10, 2], from: 10), isFromSplit: true),
        ]
        let model = makeModel(player: [10, 10], dealer: [10, 7], deck: [], hands: hands)
        model.stand()   // ハンド1
        model.stand()   // ハンド2 → ディーラー → 決着
        let result = try #require(model.handResult)

        #expect(model.score == 1, "勝った手の 1 点だけが入る")
        #expect(model.roundPoints == 1)
        #expect(result.kind == .win, "見出しは点（1 点）に合わせる")
        #expect(result.reason == "ハンド1 勝ち / ハンド2 負け（+1点）")
    }

    @Test("スプリットで 2 手とも勝てば 2 点")
    func splitBothWin() throws {
        let hands = [
            BlackjackHand(id: 0, cards: cards([10, 10], from: 0), isFromSplit: true),
            BlackjackHand(id: 1, cards: cards([10, 9], from: 10), isFromSplit: true),
        ]
        let model = makeModel(player: [10, 10], dealer: [10, 7], deck: [], hands: hands)
        model.stand()
        model.stand()
        #expect(model.score == 2)
        #expect(model.outcome == .win)
    }

    @Test("スプリットで 2 手とも負ければ負け、勝ちと引き分けなら勝ち")
    func splitAggregate() {
        let bothLose = [
            BlackjackHand(id: 0, cards: cards([10, 2], from: 0), isFromSplit: true),
            BlackjackHand(id: 1, cards: cards([10, 3], from: 10), isFromSplit: true),
        ]
        let lose = makeModel(player: [10, 2], dealer: [10, 7], deck: [], hands: bothLose)
        lose.stand(); lose.stand()
        #expect(lose.outcome == .lose)
        #expect(lose.score == 0)

        let pushAndWin = [
            BlackjackHand(id: 0, cards: cards([10, 7], from: 0), isFromSplit: true),
            BlackjackHand(id: 1, cards: cards([10, 9], from: 10), isFromSplit: true),
        ]
        let mixed = makeModel(player: [10, 7], dealer: [10, 7], deck: [], hands: pushAndWin)
        mixed.stand(); mixed.stand()
        #expect(mixed.outcome == .win)
        #expect(mixed.score == 1)
    }

    @Test("次のラウンドへ進むと結果は消える")
    func clearedOnNextRound() {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        #expect(model.handResult != nil)

        model.nextRound()
        #expect(model.handResult == nil)
        #expect(model.roundPoints == nil)
    }

    private func cards(_ ranks: [Int], from id: Int) -> [BlackjackCard] {
        ranks.enumerated().map { i, rank in
            BlackjackCard(id: id + i, suit: BlackjackSuit.allCases[(id + i) % 4], rank: rank)
        }
    }
}
