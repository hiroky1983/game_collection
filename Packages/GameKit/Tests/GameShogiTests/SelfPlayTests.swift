import Testing
@testable import GameShogi

@Suite("自己対戦で囲い・定跡が進むか")
struct SelfPlayTests {
    /// `level: 2` は実時間 1.5 秒で反復深化を打ち切る設計（`SimpleMinimaxEngine.init(level:)`）
    /// のため、CI ランナーの負荷次第で到達する深さ・指し手が変わり、このテストが確率的に
    /// 落ちていた（PR #633 の CI 失敗・issue #634・2026-09-11）。**直接指定の入口**
    /// （`init(depth:usePositional:useQuiescence:useBook:timeLimit:)`）で `level: 2` と
    /// 同じ強さ（深さ5・位置評価/静止探索/定跡あり）を指定しつつ、`timeLimit` を打ち切りが
    /// 実質発生しない大きさにする——同じ局面なら常に同じ深さまで読み切り、同じ手を指す。
    private static func deterministicStrongEngine() -> SimpleMinimaxEngine {
        SimpleMinimaxEngine(
            depth: 5, usePositional: true, useQuiescence: true, useBook: true,
            timeLimit: 60
        )
    }

    @Test func strongEngineBuildsKingSafetyOverOpening() async {
        let engine = Self.deterministicStrongEngine()
        var pos = Position.start()
        let safetyAtStartBlack = engine.kingSafety(pos, .black)
        let safetyAtStartWhite = engine.kingSafety(pos, .white)

        // 強レベル同士で 16 手進める（元は24手。実測でスイープした: 8手だと囲いが未完成のまま
        // 玉が動いた分だけ安全度が一時的に下がり空振りする（誤検知の実例として確認済み）、
        // 16手で安定して上がる。24手は打ち切り無しの探索だと1手あたりのコストが跳ね上がり
        // 5分超のテストになる。16手・約145秒は元の実測値「約2分」から大きく伸びていない）。
        for _ in 0..<16 {
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
