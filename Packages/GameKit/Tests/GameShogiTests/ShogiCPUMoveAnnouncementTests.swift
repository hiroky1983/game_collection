import Core
import Testing
@testable import GameShogi

/// CPU の着手（と王手）の読み上げ（#2280）。
@MainActor
@Suite("将棋: CPU の着手の読み上げ")
struct ShogiCPUMoveAnnouncementTests {
    private func sq(_ file: Int, _ rank: Int) -> Int { Sq.index(file: file - 1, rank: rank - 1) }

    @Test("盤上の駒の移動は駒名と移動元・移動先を読む")
    func boardMove() {
        let move = Move.board(from: sq(7, 7), to: sq(7, 6), promote: false)
        #expect(ShogiAccessibility.cpuMoveAnnouncement(
            move: move, piece: Piece(type: .pawn, color: .black), isCheck: false, language: .japanese)
                == "CPUは歩を7七から7六へ動かしました")
    }

    @Test("成りと王手は続けて読む")
    func promotionAndCheck() {
        let move = Move.board(from: sq(2, 4), to: sq(2, 3), promote: true)
        #expect(ShogiAccessibility.cpuMoveAnnouncement(
            move: move, piece: Piece(type: .pawn, color: .black, promoted: true), isCheck: true, language: .japanese)
                == "CPUはと金を2四から2三へ動かしました。成りました。王手です")
    }

    @Test("持ち駒を打ったときは打った駒と升を読む")
    func drop() {
        let move = Move.drop(type: .bishop, to: sq(5, 5))
        #expect(ShogiAccessibility.cpuMoveAnnouncement(
            move: move, piece: Piece(type: .bishop, color: .white), isCheck: false, language: .japanese)
                == "CPUは角を5五に打ちました")
    }

    @Test("CPU が指した直後の鍵だけが控えられ、人間が指すと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 1) // CPU=先手
        try #require(model.isAITurn)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        model.apply(try #require(model.position.legalMoves().first))
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
