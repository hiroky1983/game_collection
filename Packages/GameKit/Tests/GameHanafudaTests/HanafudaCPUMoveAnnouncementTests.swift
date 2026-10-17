import Testing
@testable import GameHanafuda

/// CPU の手番の読み上げ（#2280）。
@MainActor
@Suite("花札: CPU の手番の読み上げ")
struct HanafudaCPUMoveAnnouncementTests {
    private let played = HanafudaCard(id: 0)
    private let drawn = HanafudaCard(id: 5)

    @Test("場に出しただけの手番と、めくり札で取った手番を続けて読む")
    func text() {
        let noCapture = HanafudaCPUTurnSummary(played: played, playedCaptured: 0, drawn: drawn, drawnCaptured: 2)
        #expect(HanafudaSpeech.cpuTurnAnnouncement(noCapture)
                == "CPUは\(played.displayName)を場に出しました。めくり札「\(drawn.displayName)」で2枚取りました")
        let capture = HanafudaCPUTurnSummary(played: played, playedCaptured: 2, drawn: drawn, drawnCaptured: 0)
        #expect(HanafudaSpeech.cpuTurnAnnouncement(capture)
                == "CPUは\(played.displayName)で2枚取りました。めくり札は「\(drawn.displayName)」でした")
    }

    @Test("こいこいは最後に読む")
    func koiKoi() {
        var turn = HanafudaCPUTurnSummary(played: played, playedCaptured: 1, drawn: nil)
        turn.koiKoi = true
        #expect(HanafudaSpeech.cpuTurnAnnouncement(turn)
                == "CPUは\(played.displayName)で1枚取りました。CPUがこいこいしました")
    }

    @Test("CPU の手番が終わって人間へ渡った直後の鍵だけが控えられ、人間が出すと外れる")
    func keyTracksCPUTurnOnly() throws {
        let model = try #require((UInt64(1)...200).lazy.map { seed -> HanafudaModel in
            let m = HanafudaModel(services: nil, cpuDelay: .zero, seed: seed)
            m.startMatch(options: HanafudaOptions())
            return m
        }.first { $0.turn == .cpu })
        #expect(model.lastCPUMoveKey == nil)
        model.stepCPU()
        try #require(model.phase == .playing)
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        #expect(model.lastCPUTurn?.drawn != nil)
        let card = try #require(model.humanHand.first(where: { model.canPlay($0) }))
        model.play(card)
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
