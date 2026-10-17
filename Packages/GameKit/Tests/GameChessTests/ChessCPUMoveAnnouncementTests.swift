import Testing
@testable import GameChess

/// CPU の着手（とチェック）の読み上げ（#2280）。
@MainActor
@Suite("チェス: CPU の着手の読み上げ")
struct ChessCPUMoveAnnouncementTests {
    private let knight = ChessPiece(type: .knight, color: .white)

    @Test("駒の名前と移動元・移動先を読む")
    func text() {
        let move = ChessMove(from: ChessSquare.fromName("g1")!, to: ChessSquare.fromName("f3")!)
        #expect(ChessAccessibility.cpuMoveAnnouncement(piece: knight, move: move, isCheck: false)
                == "CPUは白のナイトをg1からf3へ動かしました")
    }

    @Test("チェックを掛けたときは続けて読む")
    func check() {
        let move = ChessMove(from: ChessSquare.fromName("g1")!, to: ChessSquare.fromName("f3")!)
        #expect(ChessAccessibility.cpuMoveAnnouncement(piece: knight, move: move, isCheck: true)
                == "CPUは白のナイトをg1からf3へ動かしました。チェックです")
    }

    @Test("CPU が指した直後の鍵だけが控えられ、人間が指すと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = ChessGameModel(services: nil)
        model.newGame(humanSide: .black, aiLevel: 1) // CPU=白(先手)
        try #require(model.isAITurn)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        model.apply(try #require(model.position.legalMoves().first))
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}
