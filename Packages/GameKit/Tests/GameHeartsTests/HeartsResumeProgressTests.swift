import Testing
import Core
import CoreTestSupport
@testable import GameHearts

/// ハブのタイルに出す進み具合（#3153）。
@Suite("ハーツの中断データの進み具合（#3153）")
@MainActor
struct HeartsResumeProgressTests {
    private func snapshot(handNumber: Int) -> HeartsSnapshot {
        let deck = HeartsCard.makeDeck()
        let hands = (0..<4).map { Array(deck[($0 * 13)..<(($0 + 1) * 13)]) }
        return HeartsSnapshot(
            phase: .passing, hands: hands, currentTrick: [], currentPlayer: 0, heartsBroken: false, trickNumber: 0,
            takenPoints: [0, 0, 0, 0], totals: [10, 10, 3, 3], handNumber: handNumber, playedIDs: [], lastTrick: [],
            lastTrickWinner: nil, receivedIDs: [], aiLevel: 1, turnSerial: 5, hintsUsed: nil, passHintIDs: nil
        )
    }

    @Test("「n手目」。中断データなしは出さない")
    func handNumber() throws {
        let module = HeartsModule()
        let store = MemorySnapshotStore()
        #expect(module.resumeProgress(in: store) == nil)
        try store.save(snapshot(handNumber: 3), for: module.id)
        #expect(module.resumeProgress(in: store) == "3手目")
    }
}
