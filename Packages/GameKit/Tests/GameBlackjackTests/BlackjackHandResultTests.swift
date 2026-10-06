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
                       chips: Int = 1000, hands: [BlackjackHand]? = nil) -> BlackjackModel {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make(player)
    let restored = hands ?? [BlackjackHand(id: 0, cards: playerCards, bet: 100)]
    let store = MemorySnapshotStore()
    let snapshot = BlackjackSnapshot(
        playerHand: playerCards, dealerHand: make(dealer), deck: make(deck),
        chips: chips, bet: restored.reduce(0) { $0 + $1.bet },
        phase: .playerTurn, hands: restored, activeHandIndex: 0
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

    @Test("勝つと +ベット額。点数の対比が理由に出る")
    func win() throws {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "あなた19 対 ディーラー17")
        #expect(result.chipDelta == 100)
    }

    @Test("バストすると負け。理由に点数が出る")
    func bust() throws {
        let model = makeModel(player: [10, 6], dealer: [10, 7], deck: [10])
        model.hit()
        let result = try #require(model.handResult)

        #expect(result.kind == .lose)
        #expect(result.reason == "バスト（26）")
        #expect(result.chipDelta == -100)
    }

    @Test("ディーラーがバストして勝つ")
    func dealerBust() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 6], deck: [10])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.reason == "ディーラーがバスト（26）")
    }

    @Test("同点は引き分けで ±0")
    func push() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 8], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .draw)
        #expect(result.chipDelta == 0)
        #expect(result.chipText == "±0枚")
    }

    @Test("スプリットで手ごとに勝敗が割れても、見出し・増減・実際の収支が一致する")
    func splitMixed() throws {
        // ハンド1: 20（勝ち）/ ハンド2: 12（負け）。ディーラーは 17 で止まる。
        let hands = [
            BlackjackHand(id: 0, cards: cards([10, 10], from: 0), bet: 100, isFromSplit: true),
            BlackjackHand(id: 1, cards: cards([10, 2], from: 10), bet: 200, isFromSplit: true),
        ]
        let model = makeModel(player: [10, 10], dealer: [10, 7], deck: [], chips: 1000, hands: hands)
        model.stand()   // ハンド1
        model.stand()   // ハンド2 → ディーラー → 精算
        let result = try #require(model.handResult)

        #expect(model.chips == 1000 - 100, "+100 と −200 で実際の持ち点は 100 減る")
        #expect(result.chipDelta == -100)
        #expect(result.kind == .lose, "見出しは収支（−100）に合わせる")
        #expect(result.chipDelta == model.chips - 1000, "表示の増減は実際の持ち点の差と一致する")
        #expect(result.reason == "ハンド1 勝ち / ハンド2 負け")
    }

    @Test("次のラウンドへ進むと結果は消える")
    func clearedOnNextRound() {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        #expect(model.handResult != nil)

        model.nextRound()
        #expect(model.handResult == nil)
        #expect(model.roundDelta == nil)
    }

    private func cards(_ ranks: [Int], from id: Int) -> [BlackjackCard] {
        ranks.enumerated().map { i, rank in
            BlackjackCard(id: id + i, suit: BlackjackSuit.allCases[(id + i) % 4], rank: rank)
        }
    }
}
