import Testing
import Foundation
import Core
import CoreEngine
@testable import GameHearts
import CoreTestSupport

/// CPU が札を出したときの読み上げ（#3424）。
@MainActor
@Suite("ハーツ: CPU の動きの読み上げ")
struct HeartsCPUAnnouncementTests {
    @Test("文面は「誰が何を出したか」")
    func text() {
        let text = HeartsAccessibility.cpuPlayAnnouncement(player: 1, card: HeartsCard(.spade, 12))
        #expect(text == "CPU1が\(HeartsCard(.spade, 12).figure.spokenLabel)を出しました")
    }

    @Test("英語の訳がある")
    func english() {
        let text = GameHearts.tr("%1$@が%2$@を出しました", "CPU1", "Q", language: .english)
        #expect(text == "CPU1 played Q")
    }

    @Test("CPU が出すと控えが進み、あなたが出しても進まない")
    func eventTracksCPUOnly() async throws {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: 42)
        model.startMatch()
        for card in model.playerHand.prefix(3) { model.togglePass(card) }
        model.confirmPass()
        await model.runCPUTurnsIfNeeded()
        var guardCount = 0
        while model.phase == .playing, !model.isPlayerTurn, guardCount < 100 {
            await model.runCPUTurnsIfNeeded()
            guardCount += 1
        }
        let id = try #require(model.playableCardIDs.min())
        let card = try #require(model.playerHand.first(where: { $0.id == id }))
        let before = model.cpuEvent
        model.toggleSelection(card)
        model.playSelected()
        #expect(model.cpuEvent == before)   // あなたの操作では鳴らさない
        await model.runCPUTurnsIfNeeded()
        let after = try #require(model.cpuEvent)
        #expect(after.serial > (before?.serial ?? 0))
        #expect(after.text.contains("CPU"))
    }
}
