import Foundation
import SwiftUI
import Core
@testable import GameBlackjack
import CoreTestSupport

/// 配りが乱数のブラックジャックでは狙った手札を作れないので、中断データを自作して注入し、
/// 山札の先頭も決め打ちする（#439 からの手口）。10 回勝負（#2552）の途中の回もここで組み立てる。
///
/// カードの id は通し番号で振る（同じ id が卓に 2 枚あると `ForEach` が壊れるため）。
struct BlackjackTable {
    private var nextID = 0

    mutating func cards(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
}

/// プレイヤーの手番の中断データ。
///
/// - Parameters:
///   - completedRounds: それまでに決着した回数（0 なら 1 回目の途中）。
///   - hands: スプリット後の手など、手を直に渡すとき。nil なら `player` の 1 手。
func blackjackSnapshot(
    player: [Int],
    dealer: [Int],
    deck: [Int],
    hands: ((inout BlackjackTable) -> [BlackjackHand])? = nil,
    completedRounds: Int = 0,
    points: Int = 0,
    streak: Int = 0,
    bestStreak: Int = 0,
    hasUsedRetry: Bool = false,
    handsWon: Int = 0,
    handsLost: Int = 0,
    activeHandIndex: Int = 0
) -> BlackjackSnapshot {
    var table = BlackjackTable()
    let playerHands = hands.map { $0(&table) } ?? [BlackjackHand(id: 0, cards: table.cards(player))]
    return BlackjackSnapshot(
        completedRounds: completedRounds,
        points: points,
        streak: streak,
        bestStreak: max(bestStreak, streak),
        hasUsedRetry: hasUsedRetry,
        streakBeforeRound: 0,
        handsWon: handsWon,
        handsLost: handsLost,
        naturalWins: 0,
        hands: playerHands,
        activeHandIndex: activeHandIndex,
        dealerHand: table.cards(dealer),
        deck: table.cards(deck),
        phase: .playerTurn
    )
}

/// 視聴完了・未完了を制御できる広告スタブ。
final class BlackjackStubAds: AdService, @unchecked Sendable {
    var rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 視聴のあいだに起きること（ハブへ戻る・次の回へ進む等）。広告のロード中も画面は操作できる（#653）。
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

/// 中断データを入れたストアから画面を開き直した形でモデルを作る。
@MainActor
func makeBlackjackModel(
    _ snapshot: BlackjackSnapshot,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    ads: AdService = BlackjackStubAds(),
    playLog: PlayLog? = nil,
    gameCenter: GameCenterReporter? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration(),
    seed: UInt64? = 20261020,
    dealerDrawInterval: Duration = .zero
) -> BlackjackModel {
    try? store.save(snapshot, for: "blackjack")
    return BlackjackModel(
        services: GameServices(
            snapshots: store, ads: ads, playLog: playLog, gameCenter: gameCenter,
            screenGeneration: screenGeneration
        ),
        seed: seed,
        dealerDrawInterval: dealerDrawInterval
    )
}

/// 使い捨ての `PlayLog`（UserDefaults のスイートをテストごとに分ける）。
@MainActor
func makeBlackjackPlayLog() -> (PlayLog, UserDefaults, String) {
    let name = "bj-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 決着まで進める。プレイヤーの手番ならスタンドし続ける（スプリット後は手ごとに 1 回）。
@MainActor
func standUntilResolved(_ model: BlackjackModel) {
    while model.phase == .playerTurn { model.stand() }
}

/// 10 回勝負を最後まで遊ぶ（毎回スタンド・やり直しは使わない）。
@MainActor
func playWholeMatch(_ model: BlackjackModel) {
    if model.phase == .ready { model.deal() }
    for _ in 0..<(BlackjackModel.roundsPerMatch * 2) {
        standUntilResolved(model)
        if model.matchOver { return }
        model.nextRound()
    }
}
