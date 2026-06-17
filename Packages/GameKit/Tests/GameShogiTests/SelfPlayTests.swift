import Testing
@testable import GameShogi

@Suite("自己対戦で囲い・定跡が進むか")
struct SelfPlayTests {
    @Test func strongEngineBuildsKingSafetyOverOpening() async {
        let engine = SimpleMinimaxEngine(level: 2)
        var pos = Position.start()
        let safetyAtStartBlack = engine.kingSafety(pos, .black)
        let safetyAtStartWhite = engine.kingSafety(pos, .white)

        // 強レベル同士で 24 手進める。
        for _ in 0..<24 {
            guard let usi = await engine.bestMove(sfen: pos.toSFEN()),
                  let move = Move.fromUSI(usi),
                  pos.legalMoves().contains(move) else { break }
            pos.make(move)
        }

        let safetyEndBlack = engine.kingSafety(pos, .black)
        let safetyEndWhite = engine.kingSafety(pos, .white)

        // 序盤を通して玉の安全度（＝囲い・駒組み）が上がっているはず。
        #expect(safetyEndBlack > safetyAtStartBlack)
        #expect(safetyEndWhite > safetyAtStartWhite)
    }
}
