import Testing
import Foundation
import SwiftUI
import Core
@testable import GameBlackjack

// MARK: - Mocks

/// 中断データを注入するためだけの器（残高を狙った値で始めさせるのに使う）。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

private final class SilentAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 「残高 `chips` から `bet` 枚を賭けて必ず負ける手」を中断データで作る。
///
/// 配りは乱数なので、端数（25 枚）で止まる残高は普通に遊んで狙えない。#439・#499 の
/// テストと同じ手口で、プレイヤー 15 対 ディーラー 20 の決着直前を注入する。
/// `stand()` すると必ず負け、残高はちょうど `chips - bet` になる。
@MainActor
private func makeModelAboutToLose(chips: Int, bet: Int) -> BlackjackModel {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make([10, 5])
    let store = MemorySnapshotStore()
    try? store.save(
        BlackjackSnapshot(
            playerHand: playerCards,
            dealerHand: make([10, 10]),
            deck: make([2, 2]),
            chips: chips,
            bet: bet,
            phase: .playerTurn,
            hands: [BlackjackHand(id: 0, cards: playerCards, bet: bet)],
            activeHandIndex: 0,
            hasRevivedThisSession: false
        ),
        for: "blackjack"
    )
    return BlackjackModel(
        services: GameServices(snapshots: store, ads: SilentAdService()),
        seed: 20260912
    )
}

// MARK: - Tests

/// 「いちばん安いベットに届かない残高」で詰まないことの検証（#656）。
///
/// 50 枚ベットでブラックジャックを引いたときだけ 1.5 倍払い（75 枚）で 25 の端数が生まれる。
/// 破産判定が `chips <= 0` だった頃は、この 25 枚でベットボタンが全部無効・破産カードも
/// 出ないという、ハブに戻る以外の出口が無い状態になっていた。
@Suite("最小ベットに届かない残高（#656）")
@MainActor
struct BlackjackMinimumBetTests {

    @Test("残高 25 枚で破産扱いになり、復活と「最初からやり直す」が選べる")
    func quarterChipBalanceEndsTheSession() {
        let model = makeModelAboutToLose(chips: 75, bet: 50)
        model.stand()

        #expect(model.chips == 25, "端数の 25 枚に着地する局面であること（前提の確認）")
        #expect(model.sessionOver, "最小ベットに届かないのでセッションは終わっている")
        #expect(model.canReviveAfterBust, "復活導線が出る（sessionOver かつ未使用）")
    }

    @Test("残高 50 枚ちょうどなら従来どおり遊べる（退行させない）")
    func exactlyMinimumBetKeepsPlaying() {
        let model = makeModelAboutToLose(chips: 100, bet: 50)
        model.stand()

        #expect(model.chips == 50)
        #expect(!model.sessionOver, "最小ベットちょうどはまだ賭けられる")

        model.nextRound()
        #expect(model.phase == .betting)
        model.placeBet(BlackjackModel.minimumBet)
        #expect(model.phase == .playerTurn, "50 枚を賭けて手が始まる")
    }

    @Test("残高 0 枚は従来どおり破産（境目を広げただけで、元の判定を落としていない）")
    func zeroChipsStillEndsTheSession() {
        let model = makeModelAboutToLose(chips: 50, bet: 50)
        model.stand()

        #expect(model.chips == 0)
        #expect(model.sessionOver)
    }

    @Test("残高は 0 に丸めず、端数のまま見せる")
    func remainingChipsAreNotZeroedOut() {
        let model = makeModelAboutToLose(chips: 75, bet: 50)
        model.stand()
        // チップバーは `model.chips` をそのまま出すので、丸めると表示が実態と食い違う。
        #expect(model.chips == 25)
    }

    @Test("破産の境目は、いちばん安いベット額と同じ値である")
    func bustThresholdMatchesTheCheapestBet() {
        // ここが食い違うと「全ボタンが無効なのに破産にならない」残高がまた生まれる。
        // `BlackjackView.betOptions` の先頭はこの定数から作っている。
        #expect(BlackjackModel.minimumBet == 50)

        // 境目のすぐ下（49 枚）は終わり、境目ちょうど（50 枚）は続く。
        let justBelow = makeModelAboutToLose(chips: 99, bet: 50)
        justBelow.stand()
        #expect(justBelow.chips == 49)
        #expect(justBelow.sessionOver)
    }
}
