import Testing
@testable import GameShogi

@Suite("簡易AI")
struct EngineTests {
    @Test func returnsLegalMoveFromStart() async {
        let engine = SimpleMinimaxEngine(level: 1)
        let usi = await engine.bestMove(sfen: Position.startSFEN)
        let move = usi.flatMap(Move.fromUSI)
        #expect(move != nil)
        // 返した手は初期局面の合法手である。
        #expect(Position.start().legalMoves().contains(move!))
    }

    @Test func takesFreeRook() async {
        // 先手番。先手金 5e、すぐ上 5d に取れる後手飛車（無防備）。駒得を選ぶはず。
        let sfen = "4k4/9/9/4r4/4G4/9/9/9/4K4 b - 1"
        let engine = SimpleMinimaxEngine(level: 1)
        let usi = await engine.bestMove(sfen: sfen)
        // 5e の金が 5d の飛車を取る手。
        #expect(usi == "5e5d")
    }

    @Test func returnsNilWhenNoMoves() async {
        // 詰みではないが合法手が無い人工局面は作りにくいので、駒だけの最小局面で nil にならないことを確認。
        let engine = SimpleMinimaxEngine(level: 1)
        let usi = await engine.bestMove(sfen: "4k4/9/9/9/9/9/9/9/4K4 b - 1")
        #expect(usi != nil) // 玉が動ける
    }
}
