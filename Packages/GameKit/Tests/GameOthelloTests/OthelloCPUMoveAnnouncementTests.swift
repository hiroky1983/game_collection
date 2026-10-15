import Testing
@testable import GameOthello

/// CPU の着手・パスの読み上げと、手番バーの石数ラベル（#2280）。
@MainActor
@Suite("オセロ: CPU の着手の読み上げ")
struct OthelloCPUMoveAnnouncementTests {
    @Test("着手は行列と石数を、パスはパスと石数を読む")
    func text() {
        #expect(OthelloAccessibility.cpuMoveAnnouncement(move: (3, 4), black: 12, white: 9)
                == "CPUは4行5列に置きました。黒 12 対 白 9")
        #expect(OthelloAccessibility.cpuMoveAnnouncement(move: nil, black: 12, white: 9)
                == "CPUはパスしました。黒 12 対 白 9")
    }

    @Test("手番バーの石数は終局カードと同じ「黒 N 対 白 M」")
    func scoreLabel() {
        #expect(OthelloAccessibility.scoreLabel(black: 13, white: 12) == "黒 13 対 白 12")
    }

    @Test("CPU が打った直後の鍵だけが控えられ、人間が打つと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = OthelloModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 1) // CPU=黒(先手)
        try #require(model.isAITurn)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        #expect(model.lastCPUPassed == false)
        let (r, c) = try #require(model.board.validMoves(for: .white).first)
        model.tap(row: r, col: c)
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
