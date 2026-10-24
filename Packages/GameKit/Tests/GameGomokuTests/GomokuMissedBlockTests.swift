import Testing
@testable import GameGomoku

/// 負けた局の「ここで止めていれば」（#2851）。人間は黒、CPU は白。
@Suite("五目並べ: ここで止めていれば")
struct GomokuMissedBlockTests {
    typealias Move = GomokuMissedBlockFinder.Move

    private func moves(_ points: [(Int, Int)]) -> [Move] {
        points.enumerated().map { (row: $1.0, col: $1.1, stone: $0 % 2 == 0 ? .black : .white) }
    }

    private func find(_ points: [(Int, Int)]) -> GomokuMissedBlock? {
        GomokuMissedBlockFinder.find(base: GomokuBoard(), moves: moves(points), humanSide: .black)
    }

    @Test("止められる四を見逃した局は、その四の先の交点を示す")
    func ignoredFour() throws {
        // 白が (7,3)〜(7,6) の四（左は黒が塞いでいる）を作り、黒が受けずに負ける。
        let block = try #require(find([
            (7, 2), (7, 3), (0, 0), (7, 4), (0, 2), (7, 5), (0, 4), (7, 6), (0, 6), (7, 7)
        ]))
        #expect(block.stopPoints == [GomokuPoint(row: 7, col: 7)])
        #expect(block.playedPoint == GomokuPoint(row: 0, col: 6))
        #expect(block.previousMove == GomokuPoint(row: 7, col: 6))
        #expect(block.position[7, 7] == nil)
        #expect(block.position.moveCount == 8)
    }

    @Test("達四では止められないので、活三の段階まで遡る")
    func walksBackBeforeOpenFour() throws {
        // 白が (7,3)(7,4)(7,5) の活三から (7,6) で達四にして勝つ。止められた最後の局面は活三のとき。
        let block = try #require(find([
            (0, 0), (7, 3), (0, 2), (7, 4), (0, 4), (7, 5), (0, 6), (7, 6), (0, 8), (7, 7)
        ]))
        #expect(block.position.moveCount == 6)
        #expect(block.playedPoint == GomokuPoint(row: 0, col: 6))
        #expect(Set(block.stopPoints) == [GomokuPoint(row: 7, col: 6), GomokuPoint(row: 7, col: 2)])
        #expect(!block.stopPoints.contains(block.playedPoint))
    }

    @Test("CPU が最後に着手していない局（人間の勝ち・手が少ない局）では何も出さない")
    func noResultWhenHumanWon() {
        #expect(find([(7, 7)]) == nil)
        #expect(find([(7, 7), (0, 0), (7, 8)]) == nil)
    }

    @Test("脅しの無い局面で負けた局（探索の範囲外）では何も出さない")
    func noThreatBeforeLoss() {
        // 白の最後の手が勝ちでも、直前に白の脅し（四・活三）が無ければ止める手は示さない。
        #expect(find([(0, 0), (7, 7), (0, 2), (9, 9)]) == nil)
    }
}
