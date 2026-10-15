import Testing
@testable import GameGo

/// CPU の着手・パスの読み上げ（#2280）。
@MainActor
@Suite("囲碁: CPU の着手の読み上げ")
struct GoCPUMoveAnnouncementTests {
    @Test("着手は行列を、パスはパスと読む")
    func text() {
        #expect(GoAccessibility.cpuMoveAnnouncement(point: GoPoint(row: 3, col: 4)) == "CPUは4行5列に打ちました")
        #expect(GoAccessibility.cpuMoveAnnouncement(point: nil) == "CPUはパスしました")
    }

    @Test("CPU が打った直後の鍵だけが控えられ、人間が打つと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = GoModel(services: nil)
        model.newGame(humanSide: .white, level: .normal) // CPU=黒(先手)
        try #require(model.isAITurn)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        model.apply(.pass)
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
