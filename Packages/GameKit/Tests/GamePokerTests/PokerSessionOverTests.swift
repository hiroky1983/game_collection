import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker

// MARK: - Mocks

private final class MockSnapshotStore: SnapshotStore, @unchecked Sendable {
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

private final class NoopAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 2巡目のベッティング局面を中断データとして注入して復元する。
/// アンティを払った直後の手持ちを直接指定できるので、チップ切れ寸前の局面を1手で作れる。
@MainActor
private func makeModelInBetting2(
    playerChips: Int,
    cpuChips: Int,
    pot: Int,
    currentBet: Int
) -> PokerModel {
    let store = MockSnapshotStore()
    // 役の強さは判定に影響しない（フォールドは無条件に CPU の勝ち）ため、重複しない札を機械的に配る。
    let playerHand = (0..<5).map { PokerCard(id: $0, suit: .spades, rank: $0 + 2) }
    let cpuHand = (0..<5).map { PokerCard(id: $0 + 13, suit: .hearts, rank: $0 + 7) }
    let deck = (0..<10).map { PokerCard(id: $0 + 26, suit: .clubs, rank: $0 % 13 + 2) }
    let snap = PokerSnapshot(
        playerHand: playerHand, cpuHand: cpuHand, deck: deck,
        playerChips: playerChips, cpuChips: cpuChips, pot: pot,
        phase: .betting2, currentBet: currentBet,
        playerBetInRound: 0, cpuBetInRound: currentBet,
        cpuFolded: false, cpuAction: currentBet > 0 ? "ベット \(currentBet)" : ""
    )
    try? store.save(snap, for: "poker")
    return PokerModel(services: GameServices(snapshots: store, ads: NoopAdService()))
}

// MARK: - Tests

@Suite("フォールドでのセッション終了判定（#412）")
@MainActor
struct PokerSessionOverTests {

    @Test("自分の番でフォールドしてチップがアンティ未満なら、セッション敗北になる")
    func foldOnOwnTurnEndsSessionWhenOutOfChips() {
        // アンティ 10 を払って手持ち 0。CPU のベットはまだ無い（currentBet == 0）。
        let model = makeModelInBetting2(playerChips: 0, cpuChips: 90, pot: 20, currentBet: 0)

        model.bet2Action(.fold)

        #expect(model.phase == .result)
        #expect(model.sessionOver, "手持ち 0 < アンティ 10 なのでセッションは終了する")
        #expect(model.sessionWinner == .cpu)
        #expect(!model.canStartRound, "次のラウンドは始められない")
    }

    @Test("CPU のベットにフォールドしてチップがアンティ未満なら、セッション敗北になる")
    func foldToCPUBetEndsSessionWhenOutOfChips() {
        // アンティ 10 を払って手持ち 0。CPU が 20 をベットしていてコールできない。
        let model = makeModelInBetting2(playerChips: 0, cpuChips: 70, pot: 40, currentBet: 20)

        model.foldToCPUBet()

        #expect(model.phase == .result)
        #expect(model.sessionOver, "手持ち 0 < アンティ 10 なのでセッションは終了する")
        #expect(model.sessionWinner == .cpu)
        #expect(!model.canStartRound)
    }

    @Test("チップが残っていればフォールドしてもセッションは続く")
    func foldKeepsSessionAliveWhenChipsRemain() {
        let model = makeModelInBetting2(playerChips: 50, cpuChips: 40, pot: 20, currentBet: 20)

        model.foldToCPUBet()

        #expect(model.phase == .result)
        #expect(!model.sessionOver, "手持ち 50 >= アンティ 10 なので継続できる")
        #expect(model.sessionWinner == nil)
        #expect(model.canStartRound, "「次のゲーム」で次のラウンドに進める")
    }

    @Test("セッション終了はポットを分配したあとのチップで判定する")
    func foldJudgesSessionAfterPotIsAwarded() {
        // プレイヤーのフォールドでポットは CPU に渡るが、その後も CPU の手持ちがアンティ未満のまま。
        let model = makeModelInBetting2(playerChips: 80, cpuChips: 0, pot: 20, currentBet: 0)

        model.bet2Action(.fold)

        #expect(model.cpuChips == 20, "ポットはフォールド勝ちした CPU へ渡る")
        #expect(!model.sessionOver, "回収後の CPU は 20 >= アンティ 10 なので継続する")
        #expect(model.canStartRound)
    }
}
