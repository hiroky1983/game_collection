import Testing
import Core
import CoreTestSupport
@testable import Game2048

/// #2253: タイルが元の位置から行き先へ滑るための「移動元 → 移動先」の対応。
@Suite("2048 タイルの移動元と移動先（#2253）")
struct Game2048TileMoveLogicTests {
    private typealias Cell = Game2048Cell

    private func move(_ from: (Int, Int), _ to: (Int, Int), merges: Bool = false) -> Game2048TileMove {
        Game2048TileMove(from: Cell(row: from.0, col: from.1), to: Cell(row: to.0, col: to.1), merges: merges)
    }

    /// 1 行だけタイルのある盤（他の行は空）。
    private func rowBoard(_ row: [Int], at r: Int = 0) -> [[Int]] {
        var b = Game2048Logic.emptyBoard()
        b[r] = row
        return b
    }

    @Test("合体する 2 枚は同じ行き先へ寄り、どちらも merges が立つ")
    func mergePairSharesDestination() {
        let moves = Game2048Logic.moves(rowBoard([2, 2, 0, 0]), .left)
        #expect(moves == [move((0, 0), (0, 0), merges: true), move((0, 1), (0, 0), merges: true)])
    }

    @Test("壁際へ滑る（離れた 1 枚は壁まで、壁に着いている列は動かない）")
    func slidesToWall() {
        #expect(Game2048Logic.moves(rowBoard([0, 0, 0, 2]), .left) == [move((0, 3), (0, 0))])
        #expect(Game2048Logic.moves(rowBoard([2, 0, 0, 0]), .right) == [move((0, 0), (0, 3))])
        // 合体できない 4 枚は誰も動かない（行き先 = 移動元）。
        #expect(Game2048Logic.moves(rowBoard([2, 4, 8, 16]), .left) == [
            move((0, 0), (0, 0)), move((0, 1), (0, 1)), move((0, 2), (0, 2)), move((0, 3), (0, 3)),
        ])
    }

    @Test("3 枚並びは進む向きの先頭側から 1 組だけ合体し、残る 1 枚はその隣へ")
    func threeInARowMergesFromLeadingSide() {
        // 右へ: 右端側の (0,2)(0,1) が (0,3) で合体、(0,0) は (0,2) へ。
        #expect(Game2048Logic.moves(rowBoard([2, 2, 2, 0]), .right) == [
            move((0, 2), (0, 3), merges: true), move((0, 1), (0, 3), merges: true), move((0, 0), (0, 2)),
        ])
        // 4 枚同値は 2 組とも合体（各タイルは 1 手で 1 度だけ）。
        #expect(Game2048Logic.moves(rowBoard([4, 4, 4, 4]), .left) == [
            move((0, 0), (0, 0), merges: true), move((0, 1), (0, 0), merges: true),
            move((0, 2), (0, 1), merges: true), move((0, 3), (0, 1), merges: true),
        ])
    }

    @Test("縦の向き（上・下）は列ごとに行き先を返す")
    func verticalDirections() {
        var b = Game2048Logic.emptyBoard()
        b[1][2] = 8
        b[3][2] = 8
        b[0][0] = 2
        #expect(Game2048Logic.moves(b, .up) == [move((0, 0), (0, 0)), move((1, 2), (0, 2), merges: true), move((3, 2), (0, 2), merges: true)])
        #expect(Game2048Logic.moves(b, .down) == [move((0, 0), (3, 0)), move((3, 2), (3, 2), merges: true), move((1, 2), (3, 2), merges: true)])
    }

    @Test("移動の対応から組み立てた盤は slide の結果と一致する（乱数の盤 × 4 方向 × 連続）")
    func movesAgreeWithSlide() {
        var rng = SplitMix64(seed: 2253)
        for _ in 0..<300 {
            var board = (0..<4).map { _ in (0..<4).map { _ in [0, 0, 2, 2, 4, 8][Int(rng.next() % 6)] } }
            // 同じ盤から 6 手続けて指し、毎手で対応を確かめる（連続スワイプ）。
            for _ in 0..<6 {
                let direction = Direction.allCases[Int(rng.next() % 4)]
                let slid = Game2048Logic.slide(board, direction)
                let moves = Game2048Logic.moves(board, direction)
                var rebuilt = Game2048Logic.emptyBoard()
                for m in moves { rebuilt[m.to.row][m.to.col] += board[m.from.row][m.from.col] }
                #expect(rebuilt == slid.board)
                // 盤上のタイルはすべて 1 度ずつ動く（取り残しが無い）。
                #expect(moves.count == board.joined().filter { $0 != 0 }.count)
                #expect(Set(moves.map(\.from)).count == moves.count)
                // 合体は行き先ごとにちょうど 2 枚、合体しない行き先は 1 枚。
                let byDestination = Dictionary(grouping: moves, by: \.to)
                for (_, group) in byDestination {
                    #expect(group.count == (group[0].merges ? 2 : 1))
                    #expect(group.allSatisfy { $0.merges == group[0].merges })
                }
                board = slid.board
            }
        }
    }
}

@Suite("2048 タイルの ID と表示の一貫性（#2253）")
@MainActor
struct Game2048TileModelTests {
    private func model(_ board: [[Int]]) -> Game2048Model {
        Game2048Model(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), board: board)
    }

    /// 表示のタイル（消えていくタイルを除く）が盤と 1 対 1 で一致しているか。
    private func tilesMatchBoard(_ m: Game2048Model) -> Bool {
        var b = Game2048Logic.emptyBoard()
        for t in m.tiles {
            guard b[t.row][t.col] == 0 else { return false } // 同じマスに 2 枚は重ならない
            b[t.row][t.col] = t.value
        }
        return b == m.board && Set(m.tiles.map(\.id)).count == m.tiles.count
    }

    @Test("滑ったタイルは ID を保ち、合体は新しい ID で、元の 2 枚は行き先で消えていく")
    func idsSurviveSlideAndMergeMakesNewTile() throws {
        let m = model([
            [2, 2, 0, 4],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])
        #expect(tilesMatchBoard(m))
        let before = Dictionary(uniqueKeysWithValues: m.tiles.map { (Game2048Cell(row: $0.row, col: $0.col), $0) })
        m.move(.left)
        #expect(tilesMatchBoard(m))

        let four = try #require(before[Game2048Cell(row: 0, col: 3)])
        let slid = try #require(m.tiles.first { $0.id == four.id })
        #expect((slid.row, slid.col, slid.value, slid.arrival) == (0, 1, 4, .slid))

        let merged = try #require(m.tiles.first { $0.arrival == .merged })
        #expect((merged.row, merged.col, merged.value) == (0, 0, 4))
        #expect(!before.values.contains { $0.id == merged.id })

        // 合体した 2 枚は行き先 (0,0) へ滑ってから消える。
        let sources = [before[Game2048Cell(row: 0, col: 0)]!.id, before[Game2048Cell(row: 0, col: 1)]!.id]
        #expect(Set(m.vanishing.map(\.id)) == Set(sources))
        #expect(m.vanishing.allSatisfy { ($0.row, $0.col, $0.value) == (0, 0, 2) })

        // 新タイルは 1 枚だけ、空いていたマスに出る。
        #expect(m.tiles.filter { $0.arrival == .spawned }.count == 1)

        // 前の手の ID で片付けようとしても（キャンセルが間に合わなかった古い片付け）、今の合体元は消さない。
        m.settleVanishing(ids: [-1])
        #expect(!m.vanishing.isEmpty)
        m.settleVanishing(ids: m.vanishing.map(\.id))
        #expect(m.vanishing.isEmpty)
    }

    @Test("連続スワイプでも盤と表示がずれず、前の手の消えていくタイルは次の手で残らない")
    func consecutiveMovesStayConsistent() {
        let m = model([
            [2, 2, 2, 2],
            [4, 0, 4, 0],
            [0, 8, 0, 8],
            [16, 0, 0, 16],
        ])
        var everyID = Set(m.tiles.map(\.id))
        for direction in [Direction.left, .right, .up, .down, .left, .up, .right, .down, .left, .left] {
            let previousVanishing = Set(m.vanishing.map(\.id))
            let moved = m.history.count
            m.move(direction)
            #expect(tilesMatchBoard(m))
            if m.history.count > moved {
                // 前の手の消えていくタイルは片付いていて、今の手の合体元だけが残る。
                #expect(Set(m.vanishing.map(\.id)).isDisjoint(with: previousVanishing))
                #expect(Set(m.vanishing.map(\.id)).isDisjoint(with: m.tiles.map(\.id)))
            }
            // 合体・出現で増える ID は使い回さない。
            let new = Set(m.tiles.map(\.id)).subtracting(everyID)
            #expect(new.isDisjoint(with: everyID))
            everyID.formUnion(new)
            if m.gameOver { break }
        }
    }

    @Test("戻す・新しいゲームは盤から表示を作り直し、消えていくタイルを残さない")
    func undoAndNewGameRebuildTiles() {
        let m = model([
            [2, 2, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])
        m.move(.left)
        #expect(!m.vanishing.isEmpty)
        #expect(m.undo())
        #expect(tilesMatchBoard(m))
        #expect(m.vanishing.isEmpty)
        #expect(m.tiles.allSatisfy { $0.arrival == .placed })

        m.move(.right)
        m.newGame()
        #expect(tilesMatchBoard(m))
        #expect(m.vanishing.isEmpty)
        #expect(m.tiles.count == 2)
        #expect(m.tiles.allSatisfy { $0.arrival == .spawned })
    }

    @Test("動かない向きへのスワイプでは表示も変わらない")
    func noOpMoveKeepsTiles() {
        let m = model([
            [2, 4, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])
        let tiles = m.tiles
        m.move(.left)
        #expect(m.tiles == tiles)
        #expect(m.vanishing.isEmpty)
    }
}

/// テスト用の決定的な乱数（盤の生成だけに使う）。
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
