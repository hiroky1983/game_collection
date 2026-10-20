import Foundation
import SwiftUI
import Core
@testable import GameBlackjack
import CoreTestSupport

/// 視聴完了・未完了を制御できる広告スタブ。
final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    private(set) var interstitialCount = 0
    /// 視聴のあいだに起きること（ハブへ戻る等）。広告のロード中も画面は操作できる（#653）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool = true) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async { interstitialCount += 1 }
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// カードを id 付きで作る。id は通し番号、スートは id から決める。
func blackjackCards(_ ranks: [Int], from start: Int = 0) -> [BlackjackCard] {
    ranks.enumerated().map { offset, rank in
        BlackjackCard(id: start + offset, suit: BlackjackSuit.allCases[(start + offset) % 4], rank: rank)
    }
}

/// 配りが乱数なので**狙った手札を作れない**。中断スナップショットを自作して注入し、
/// 山札の先頭も決め打ちする（#439）。
@MainActor
func makeInjectedModel(
    player: [Int],
    dealer: [Int],
    deck: [Int],
    hands: [BlackjackHand]? = nil,
    activeHandIndex: Int = 0,
    roundsPlayed: Int = 0,
    score: Int = 0,
    streak: Int = 0,
    retryUsed: Bool = false,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    ads: StubAdService = StubAdService(),
    playLog: PlayLog? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration(),
    seed: UInt64? = nil
) -> (BlackjackModel, MemorySnapshotStore, StubAdService) {
    let restored = hands ?? [BlackjackHand(id: 0, cards: blackjackCards(player))]
    let snapshot = BlackjackSnapshot(
        dealerHand: blackjackCards(dealer, from: 100),
        deck: blackjackCards(deck, from: 200),
        phase: .playerTurn,
        hands: restored,
        activeHandIndex: activeHandIndex,
        roundsPlayed: roundsPlayed, score: score, streak: streak, retryUsed: retryUsed
    )
    try? store.save(snapshot, for: "blackjack")
    let services = GameServices(snapshots: store, ads: ads, playLog: playLog, screenGeneration: screenGeneration)
    return (BlackjackModel(services: services, seed: seed), store, ads)
}
