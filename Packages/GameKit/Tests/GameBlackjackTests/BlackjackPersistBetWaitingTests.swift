import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 復活していない通常のセッションでも、決着後の賭け待ちで残高を持ち越す（#1623）。
@MainActor
@Suite("ブラックジャック: 決着後の残高の保存（#1623）")
struct BlackjackPersistBetWaitingTests {
    /// 1 ラウンドを最後まで進め、残高が初期額から動いた決着になる種を探して返す。
    private func settledModel(store: MemorySnapshotStore) -> BlackjackModel? {
        for seed in UInt64(1)...200 {
            store.clear(for: "blackjack")
            let model = BlackjackModel(
                services: GameServices(snapshots: store, ads: NoopAdService()), seed: seed
            )
            model.placeBet(100)
            while model.phase == .playerTurn { model.stand() }
            if model.phase == .result && model.chips != BlackjackModel.initialChips { return model }
        }
        return nil
    }

    @Test("決着で離れても、残高が復元される（賭ける前から始まる）")
    func keepsChipsWhenLeavingAtResult() throws {
        let store = MemorySnapshotStore()
        let model = try #require(settledModel(store: store))
        let settled = model.chips

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(reopened.chips == settled, "精算後の残高が初期額へ戻っている")
        #expect(reopened.phase == .betting, "決着の画は持ち越さず賭け待ちへ戻す")
        #expect(reopened.bet == 0)
        #expect(!reopened.sessionOver)
    }

    @Test("次のゲームを押して賭け待ちで離れても、残高が復元される")
    func keepsChipsAfterNextRound() throws {
        let store = MemorySnapshotStore()
        let model = try #require(settledModel(store: store))
        let settled = model.chips
        model.nextRound()
        model.placeBet(BlackjackModel.minimumBet)
        while model.phase == .playerTurn { model.stand() }
        model.nextRound()
        let after = model.chips

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(reopened.chips == after)
    }

    @Test("最初からやり直すと、中断データは消えて初期額に戻る")
    func restartClearsSnapshot() throws {
        let store = MemorySnapshotStore()
        let model = try #require(settledModel(store: store))
        model.restartSession()
        #expect(!store.exists(for: "blackjack"))
    }
}
