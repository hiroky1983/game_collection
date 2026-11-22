import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameDaifugo

/// CPU が動いたときの読み上げ（#3424）。
@MainActor
@Suite("大富豪: CPU の動きの読み上げ")
struct DaifugoCPUAnnouncementTests {
    @Test("文面は「誰が、何をしたか」")
    func text() {
        #expect(DaifugoAccessibility.cpuMoveAnnouncement(name: "CPU2", action: "8 8") == "CPU2、8 8")
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameDaifugo.tr("%1$@、%2$@", "CPU2", "Pass", language: .english) == "CPU2: Pass")
    }

    @Test("CPU が動くと控えが進む")
    func eventAfterCPUMove() async {
        var found = false
        for seed in UInt64(1)...20 where !found {
            let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
            let model = DaifugoModel(services: services, cpuDelay: .zero, seed: seed)
            model.startGame()
            #expect(model.cpuEvent == nil)
            await model.runCPUTurnsIfNeeded()
            if let event = model.cpuEvent {
                #expect(event.text.hasPrefix("CPU"))
                found = true
            }
        }
        #expect(found)
    }
}
