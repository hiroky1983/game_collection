import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GamePoker

/// ポーカーのテストで使う部品（#2551）。手札を固定した局面を中断データとして注入し、
/// `showdown()` で決着させると勝ち負けと点数が決まる。

/// 視聴完了・未完了を制御できる広告スタブ。
final class PokerStubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 視聴のあいだに起きること（次の回へ進む・ハブへ戻る等）。広告のロード中も画面は操作できる（#653）。
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

/// 札を作る。id は役の判定に関わらないので、呼ぶ側で重ならないように渡す。
func pc(_ id: Int, _ rank: Int, _ suit: PokerSuit) -> PokerCard {
    PokerCard(id: id, suit: suit, rank: rank)
}

/// 決まった手札の組（CPU の手はどれも 5 枚とも残す役なので、交換で変わらない）。
enum PokerHands {
    /// フルハウス（K×3 + 9×2）。18 点。
    static let fullHouse = [pc(0, 13, .spades), pc(1, 13, .hearts), pc(2, 13, .diamonds), pc(3, 9, .clubs), pc(4, 9, .spades)]
    /// ハイカード（A 10 7 4 2・スートばらばら）。1 点。
    static let highCard = [pc(5, 14, .spades), pc(6, 10, .hearts), pc(7, 7, .diamonds), pc(8, 4, .clubs), pc(9, 2, .spades)]
    /// ストレート（9〜5）。10 点。
    static let straight = [pc(10, 9, .hearts), pc(11, 8, .clubs), pc(12, 7, .spades), pc(13, 6, .diamonds), pc(14, 5, .hearts)]
    /// 上と同じ並びのストレート（スート違い）。引き分けになる。
    static let sameStraight = [pc(15, 9, .clubs), pc(16, 8, .diamonds), pc(17, 7, .hearts), pc(18, 6, .spades), pc(19, 5, .clubs)]
    /// フラッシュ（ハート A J 8 5 3）。12 点。
    static let flush = [pc(20, 14, .hearts), pc(21, 11, .hearts), pc(22, 8, .hearts), pc(23, 5, .hearts), pc(24, 3, .hearts)]
    /// 山札（交換・もう 1 回の交換に足りる枚数）。役の判定に関わらない札。
    static let deck = (0..<20).map { pc(100 + $0, [2, 3, 4, 6, 8][$0 % 5], [PokerSuit.clubs, .diamonds][$0 % 2]) }
}

func pokerSnapshot(
    phase: PokerPhase = .drawn,
    round: Int = 1,
    player: [PokerCard],
    cpu: [PokerCard],
    deck: [PokerCard] = PokerHands.deck,
    playerPoints: Int = 0,
    cpuPoints: Int = 0,
    playerWins: Int = 0,
    cpuWins: Int = 0,
    bestRank: PokerHandRank? = nil,
    extraExchangeUsed: Bool = false,
    streak: Int? = nil,
    bestStreak: Int? = nil
) -> PokerSnapshot {
    PokerSnapshot(
        playerHand: player, cpuHand: cpu, deck: deck, phase: phase, round: round,
        playerPoints: playerPoints, cpuPoints: cpuPoints, playerWins: playerWins, cpuWins: cpuWins,
        bestRank: bestRank, extraExchangeUsed: extraExchangeUsed, cpuAction: "",
        winner: nil, playerHandRank: .highCard, cpuHandRank: .highCard, roundPoints: 0,
        streak: streak, bestStreak: bestStreak
    )
}

/// 中断データから局面を作る。`services` を省略すると記録・解析なしの最小構成。
@MainActor
func makePokerModel(
    _ snapshot: PokerSnapshot,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    ads: AdService = PokerStubAdService(),
    feedback: FeedbackService = NoopFeedbackService(),
    playLog: PlayLog? = nil,
    analytics: GameAnalytics? = nil,
    gameCenter: GameCenterReporter? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration(),
    showdownRevealDelay: Duration = .zero
) -> PokerModel {
    try? store.save(snapshot, for: "poker")
    return PokerModel(
        services: GameServices(
            snapshots: store, ads: ads, feedback: feedback, playLog: playLog, analytics: analytics,
            gameCenter: gameCenter, screenGeneration: screenGeneration
        ),
        showdownRevealDelay: showdownRevealDelay
    )
}

/// 交換せずに 10 回目の決着まで進める（実際の操作の経路を通る）。
@MainActor
func playPokerToEnd(_ model: PokerModel) {
    if model.phase == .idle || model.sessionOver { model.startGame() }
    var guardCount = 0
    while !model.sessionOver && guardCount < 100 {
        guardCount += 1
        switch model.phase {
        case .exchange: model.confirmExchange()
        case .drawn:    model.showdown()
        case .result:   model.nextRound()
        case .idle:     return
        }
    }
}

/// 一時的な `PlayLog`。
@MainActor
func makePokerPlayLog() -> PlayLog {
    PlayLog(defaults: UserDefaults(suiteName: "poker-\(UUID().uuidString)")!)
}
