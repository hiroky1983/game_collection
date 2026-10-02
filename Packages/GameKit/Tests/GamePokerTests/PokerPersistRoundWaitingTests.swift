import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker
import CoreTestSupport

/// 復活していない通常のセッションでも、決着後の次の局待ちで残高を持ち越す（#1714）。
@MainActor
@Suite("ポーカー: 決着後の残高の保存（#1714）")
struct PokerPersistRoundWaitingTests {
    private final class StubAd: AdService, @unchecked Sendable {
        @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
        @MainActor func showInterstitial() async {}
        @MainActor func showRewardedAd() async -> Bool { true }
    }

    private func foldedModel(store: MemorySnapshotStore) -> PokerModel {
        let model = PokerModel(services: GameServices(snapshots: store, ads: StubAd()))
        model.startGame()
        model.bet1Action(.check)
        model.confirmExchange()
        model.bet2Action(.fold)
        return model
    }

    @Test("決着で離れても、両者の残高が復元され、開始シート（.idle）から始まる")
    func keepsChipsWhenLeavingAtResult() {
        let store = MemorySnapshotStore()
        let model = foldedModel(store: store)
        #expect(model.phase == .result)
        #expect(!model.sessionOver)
        #expect(model.playerChips != PokerModel.initialChips, "前提: 残高が動いている")

        let reopened = PokerModel(services: GameServices(snapshots: store, ads: StubAd()))
        #expect(reopened.playerChips == model.playerChips)
        #expect(reopened.cpuChips == model.cpuChips)
        #expect(reopened.phase == .idle)
        #expect(!reopened.sessionOver)
    }

    @Test("最初からやり直すと、中断データは消えて初期額に戻る")
    func restartClearsSnapshot() {
        let store = MemorySnapshotStore()
        let model = foldedModel(store: store)
        model.restartSession()
        #expect(!store.exists(for: "poker"))
    }
}
