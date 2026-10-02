import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker
import CoreTestSupport

private final class NoopAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 2 巡目のベッティングを中断データとして注入する。プレイヤーはワンペア、CPU は役なし。
/// アンティ 10 を払った後の局面（持ち点 100・ポット 40）で、局の開始前は 110 だったことにする。
@MainActor
private func makeModel(handStartChips: Int?) -> PokerModel {
    var nextCardID = 0
    func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        defer { nextCardID += 1 }
        return PokerCard(id: nextCardID, suit: suit, rank: rank)
    }
    let store = MemorySnapshotStore()
    let snap = PokerSnapshot(
        playerHand: [c(11, .spades), c(11, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)],
        cpuHand: [c(14, .hearts), c(10, .clubs), c(7, .diamonds), c(5, .clubs), c(3, .spades)],
        deck: [],
        playerChips: 100, cpuChips: 100, pot: 40,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "", rules: .standard,
        handStartChips: handStartChips
    )
    try? store.save(snap, for: "poker")
    return PokerModel(services: GameServices(snapshots: store, ads: NoopAdService()))
}

@Suite("ポーカーの 1 局の決着表示（#1754）")
@MainActor
struct PokerHandResultTests {

    @Test("決着するまでは出さない")
    func nilBeforeResult() {
        #expect(makeModel(handStartChips: 110).handResult == nil)
    }

    @Test("ショーダウンで勝つと、見出し・役の対比・手持ちの増減が出る")
    func showdownWin() throws {
        let model = makeModel(handStartChips: 110)
        model.bet2Action(.check)
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "\(model.playerHandRank.description) 対 \(model.cpuHandRank.description)")
        // 110 → 100（アンティ後）→ 140（ポット 40 を獲得）。増減は +30。
        #expect(result.chipDelta == 30)
        #expect(result.chipDelta == model.playerChips - 110, "表示の増減は実際の持ち点の差と一致する")
    }

    @Test("自分がフォールドすると、負けとして理由に「あなたがフォールド」が出る")
    func playerFold() throws {
        let model = makeModel(handStartChips: 110)
        model.bet2Action(.fold)
        let result = try #require(model.handResult)

        #expect(result.kind == .lose)
        #expect(result.headline == "負け")
        #expect(result.reason == "あなたがフォールド")
        #expect(result.chipDelta == -10)
    }

    @Test("局の開始前の持ち点が無い旧い中断データでは、増減だけ出さない")
    func legacySnapshotHasNoDelta() throws {
        let model = makeModel(handStartChips: nil)
        model.bet2Action(.check)
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.chipDelta == nil)
    }

    @Test("次の局を始めると結果は消える")
    func clearedOnNextRound() {
        let model = makeModel(handStartChips: 110)
        model.bet2Action(.fold)
        #expect(model.handResult != nil)

        model.startGame()
        #expect(model.handResult == nil)
        #expect(model.handNetChips == nil)
    }
}
