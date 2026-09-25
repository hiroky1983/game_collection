import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GamePoker
import CoreTestSupport

// MARK: - 局面の組み立て

/// ベッティング中の局面を中断データとして注入する（`PokerShowdownPacingTests` と同じ手口）。
/// プレイヤーはワンペア（J）、CPU は `cpuPair` で決まる役。役を変えて勝敗を振る。
@MainActor
private func makeModel(
    phase: PokerPhase, playerChips: Int, cpuChips: Int, pot: Int, currentBet: Int,
    cpuWins: Bool
) -> PokerModel {
    var nextCardID = 0
    func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        defer { nextCardID += 1 }
        return PokerCard(id: nextCardID, suit: suit, rank: rank)
    }
    let player = [c(11, .spades), c(11, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)]
    let cpuStrong = [c(14, .spades), c(14, .diamonds), c(14, .clubs), c(5, .clubs), c(3, .spades)]
    let cpuWeak = [c(13, .hearts), c(10, .clubs), c(7, .diamonds), c(5, .clubs), c(3, .spades)]
    let store = MemorySnapshotStore()
    try? store.save(
        PokerSnapshot(
            playerHand: player, cpuHand: cpuWins ? cpuStrong : cpuWeak, deck: [],
            playerChips: playerChips, cpuChips: cpuChips, pot: pot,
            phase: phase, currentBet: currentBet,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "", rules: .standard
        ),
        for: "poker"
    )
    return PokerModel(services: GameServices(
        snapshots: store, ads: NoopAdService(), feedback: SpyFeedbackService(),
        playLog: PlayLog(defaults: UserDefaults(suiteName: "poker-shortcall-\(UUID().uuidString)")!)
    ))
}

// MARK: - Tests

@Suite("ポーカー: ショートコールの超過分の返却（#1376）")
@MainActor
struct PokerShortCallRefundTests {

    @Test("CPU が残高 15 で 20 ベットをコールして勝っても、プレイヤーの超過 5 枚は戻る")
    func cpuShortCallRefundsPlayer() {
        let model = makeModel(phase: .betting2, playerChips: 100, cpuChips: 15, pot: 20, currentBet: 0, cpuWins: true)

        model.bet2Action(.bet(20))

        #expect(model.phase == .result)
        #expect(model.winner == .cpu)
        #expect(model.playerChips == 85)  // 100 - 20 + 戻り 5
        #expect(model.cpuChips == 50)     // 0 + ポット（20 + 15 + 15）
        #expect(model.playerChips + model.cpuChips == 135)
    }

    @Test("1 巡目でも CPU のショートコールは超過分を戻す")
    func cpuShortCallInFirstRoundRefundsPlayer() {
        let model = makeModel(phase: .betting1, playerChips: 100, cpuChips: 15, pot: 20, currentBet: 0, cpuWins: true)

        model.bet1Action(.bet(20))

        #expect(model.phase == .exchange)
        #expect(model.playerChips == 85)
        #expect(model.cpuChips == 0)
        #expect(model.pot == 50)          // 20 + 15 + 15
    }

    @Test("プレイヤーが残高 15 で 20 のベットをコールして勝っても、CPU の超過 5 枚は CPU に戻る")
    func playerShortCallRefundsCPU() {
        let model = makeModel(phase: .betting2, playerChips: 15, cpuChips: 80, pot: 40, currentBet: 20, cpuWins: false)

        model.callCPUBet()

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(model.playerChips == 50)  // 0 + ポット（20 + 15 + 15）
        #expect(model.cpuChips == 85)     // 80 + 戻り 5
        #expect(model.playerChips + model.cpuChips == 135)
    }

    @Test("チップが足りていれば返却は起きない（全額コール）")
    func fullCallRefundsNothing() {
        let model = makeModel(phase: .betting2, playerChips: 100, cpuChips: 100, pot: 20, currentBet: 0, cpuWins: true)

        model.bet2Action(.bet(20))

        #expect(model.playerChips == 80)
        #expect(model.cpuChips == 140)    // 100 - 20（コール）+ ポット 60
    }
}
