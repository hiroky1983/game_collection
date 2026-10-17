import Testing
@testable import GameBackgammon

/// CPU の手番の読み上げ（#2280）。
@MainActor
@Suite("バックギャモン: CPU の手番の読み上げ")
struct BackgammonCPUMoveAnnouncementTests {
    private func move(hits: Bool) -> BackgammonMove { BackgammonMove(from: 12, to: 8, die: 4, hits: hits) }

    @Test("動かした駒の数を読み、叩かれた駒があれば続けて読む")
    func text() {
        #expect(BackgammonAccessibility.cpuTurnAnnouncement(moves: [move(hits: false), move(hits: false)])
                == "CPUは駒を2個動かしました")
        #expect(BackgammonAccessibility.cpuTurnAnnouncement(moves: [move(hits: true), move(hits: false)])
                == "CPUは駒を2個動かしました。あなたの駒が1個バーに送られました")
    }

    @Test("動かせなかった手番はパスと読む")
    func pass() {
        #expect(BackgammonAccessibility.cpuTurnAnnouncement(moves: []) == "CPUはパスしました")
    }

    @Test("駒を 1 つ動かすたびではなく、手番が人間へ渡ったときだけ鍵を控える")
    func keyIsRecordedOnlyWhenTurnEnds() async throws {
        let model = try #require((UInt64(1)...60).lazy.map { seed -> BackgammonModel in
            let m = BackgammonModel(services: nil, cpuDelay: .zero, seed: seed)
            return m
        }.first { $0.isAITurn && !$0.mustPass })
        #expect(model.lastCPUMoveKey == nil)
        var keysSeenMidTurn = 0
        while model.isAITurn, !model.gameOver {
            await model.performAIMoveIfNeeded()
            if model.isAITurn, !model.gameOver, model.lastCPUMoveKey != nil { keysSeenMidTurn += 1 }
        }
        #expect(keysSeenMidTurn == 0)
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        #expect(!model.lastCPUTurnMoves.isEmpty)
    }
}
