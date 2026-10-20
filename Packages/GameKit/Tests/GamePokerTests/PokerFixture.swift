import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GamePoker

/// 広告は常に視聴完了で返す（`showRewardedAd` の回数も数える）。
final class PokerStubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 視聴のあいだに起きること（次の回へ進む等）。広告のロード中も画面は操作できる（#653）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool = true) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// 手札と中断データを決め打ちで組む（配りは乱数なので、役の勝ち負けを固定するため中断データで注入する）。
enum PokerFixture {
    static func hand(_ ranks: [Int], _ suits: [PokerSuit], base: Int) -> [PokerCard] {
        zip(ranks, suits).enumerated().map { PokerCard(id: base + $0.offset, suit: $0.element.1, rank: $0.element.0) }
    }

    /// フラッシュ（12 点）。CPU のストレートに勝つ。
    static var flush: [PokerCard] { hand([2, 5, 9, 11, 13], Array(repeating: .hearts, count: 5), base: 0) }
    /// 役なし（ハイカード・1 点）。CPU のストレートに負ける。
    static var junk: [PokerCard] { hand([2, 4, 7, 9, 12], [.spades, .hearts, .diamonds, .clubs, .spades], base: 0) }
    /// ストレート（10 点）。CPU は全部残す形なので交換しない。
    static var cpuStraight: [PokerCard] { hand([5, 6, 7, 8, 9], [.spades, .hearts, .diamonds, .clubs, .spades], base: 20) }
    /// `cpuStraight` と同じ強さ（スーツ違い）。引き分けになる。
    static var tieStraight: [PokerCard] { hand([5, 6, 7, 8, 9], [.hearts, .diamonds, .clubs, .spades, .hearts], base: 0) }
    static var filler: [PokerCard] { hand([2, 3, 4, 6, 8, 10, 12, 3, 5, 7], Array(repeating: .clubs, count: 10), base: 40) }

    static func snapshot(
        player: [PokerCard], cpu: [PokerCard] = cpuStraight, phase: PokerPhase = .exchange,
        round: Int = 1, totalPoints: Int = 0, playerWins: Int = 0, cpuWins: Int = 0, draws: Int = 0,
        bestRank: PokerHandRank? = nil, extraExchangeUsed: Bool = false, exchangesDone: Int = 0,
        lastRoundPoints: Int = 0
    ) -> PokerSnapshot {
        PokerSnapshot(
            playerHand: player, cpuHand: cpu, deck: filler, phase: phase, round: round,
            totalPoints: totalPoints, playerWins: playerWins, cpuWins: cpuWins, draws: draws,
            bestRank: bestRank?.rawValue, extraExchangeUsed: extraExchangeUsed,
            exchangesDone: exchangesDone, cpuAction: "", lastRoundPoints: lastRoundPoints
        )
    }

    @MainActor
    static func model(
        _ snapshot: PokerSnapshot? = nil,
        ads: PokerStubAdService = PokerStubAdService(),
        playLog: PlayLog? = nil,
        feedback: FeedbackService = NoopFeedbackService(),
        gameCenter: GameCenterReporter? = nil,
        analytics: GameAnalytics? = nil,
        screenGeneration: GameScreenGeneration = GameScreenGeneration(),
        showdownRevealDelay: Duration = .zero
    ) -> (PokerModel, MemorySnapshotStore) {
        let store = MemorySnapshotStore()
        if let snapshot { try? store.save(snapshot, for: "poker") }
        let services = GameServices(
            snapshots: store, ads: ads, feedback: feedback, playLog: playLog, analytics: analytics,
            gameCenter: gameCenter, screenGeneration: screenGeneration
        )
        return (PokerModel(services: services, showdownRevealDelay: showdownRevealDelay), store)
    }

    @MainActor
    static func freshPlayLog() -> PlayLog {
        PlayLog(defaults: UserDefaults(suiteName: "poker-\(UUID().uuidString)")!)
    }
}
