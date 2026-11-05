import Testing
import CoreEngine
@testable import GameMancala

/// CPU の着手の読み上げ（#3062）。
@MainActor
@Suite("マンカラ: CPU の着手の読み上げ")
struct MancalaCPUMoveAnnouncementTests {
    @Test("穴の番号は画面の左から数え、取った・ストア入りを添える")
    func text() {
        // 北の 6 番目の穴（添字 12）は画面の左端 = 穴 1。
        #expect(MancalaAccessibility.cpuMoveAnnouncement(pitSlot: 12, event: nil) == "CPUは穴1 をまきました")
        #expect(MancalaAccessibility.cpuMoveAnnouncement(pitSlot: 7, event: nil) == "CPUは穴6 をまきました")
        let plain = MancalaEvent(side: .north, extraTurn: false, captured: 0)
        #expect(MancalaAccessibility.cpuMoveAnnouncement(pitSlot: 9, event: plain) == "CPUは穴4 をまきました")
        let extra = MancalaEvent(side: .north, extraTurn: true, captured: 0)
        #expect(MancalaAccessibility.cpuMoveAnnouncement(pitSlot: 7, event: extra)
                == "CPUは穴6 をまきました。ストアに入って、もう一度まきます")
        let capture = MancalaEvent(side: .north, extraTurn: false, captured: 5)
        #expect(MancalaAccessibility.cpuMoveAnnouncement(pitSlot: 8, event: capture)
                == "CPUは穴5 をまきました。5個を取りました")
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameMancala.tr("CPUは穴%lld をまきました", 3, language: .english) == "The CPU sowed from pit 3")
    }

    @Test("CPU が打った直後の鍵だけが控えられ、人間が打つと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: false)
        try #require(model.isAITurn)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        let pit = try #require(model.legalPits.first)
        model.tap(pit: pit)
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
