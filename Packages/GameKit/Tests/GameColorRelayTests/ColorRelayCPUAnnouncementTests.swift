import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameColorRelay

/// CPU が動いたときの読み上げ（#3424）。
@MainActor
@Suite("いろリレー: CPU の動きの読み上げ")
struct ColorRelayCPUAnnouncementTests {
    @Test("文面は「誰が、何をしたか」")
    func text() {
        #expect(ColorRelayAccessibility.cpuMoveAnnouncement(name: "CPU2", action: "1枚引いた") == "CPU2、1枚引いた")
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameColorRelay.tr("%1$@、%2$@", "CPU2", "Skip", language: .english) == "CPU2: Skip")
    }

    @Test("あなたが動いても控えは進まず、CPU が動くと進む")
    func eventAfterCPUMove() async throws {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ColorRelayModel(services: services, cpuDelay: .zero, seed: 42)
        model.startGame()
        // あなたが先手なら、山から引いて（出せる札を引いたら見送って）番を渡す。
        if model.isPlayerTurn { model.drawCard() }
        if model.isPlayerTurn { model.endTurn() }
        #expect(model.cpuEvent == nil)
        await model.runCPUTurnsIfNeeded()
        let event = try #require(model.cpuEvent)
        #expect(event.serial >= 1)
        #expect(event.text.hasPrefix("CPU"))
    }
}
