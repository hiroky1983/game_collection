import Testing
import CoreGraphics
@testable import GameBlockPuzzle

/// ピースのカタログ。**`id` は中断データに書かれる**ので、並びの不変条件をここで固定する。
@Suite("ブロックならべ: ピースのカタログ")
struct BlockPuzzlePieceTests {

    @Test("id は添字と一致し、重複しない")
    func idsMatchIndices() {
        for (index, piece) in BlockPuzzlePiece.catalog.enumerated() {
            #expect(piece.id == index)
        }
        #expect(Set(BlockPuzzlePiece.catalog.map(\.id)).count == BlockPuzzlePiece.catalog.count)
    }

    @Test("形はすべて左上に正規化されていて、マスの重複が無い")
    func shapesAreNormalized() {
        for piece in BlockPuzzlePiece.catalog {
            #expect(piece.cells.map(\.row).min() == 0, "ピース\(piece.id): 最小行が 0 でない")
            #expect(piece.cells.map(\.col).min() == 0, "ピース\(piece.id): 最小列が 0 でない")
            #expect(piece.cells.allSatisfy { $0.row >= 0 && $0.col >= 0 })
            let unique = Set(piece.cells.map { "\($0.row),\($0.col)" })
            #expect(unique.count == piece.cells.count, "ピース\(piece.id): 同じマスを 2 回占めている")
        }
    }

    /// `BlockPuzzleBoard.revive` が中央 5×5 を空けるだけで「必ず置ける」と言えるための前提。
    /// カタログに 6 マス以上に伸びる形を足したら、この表明が先に落ちる。
    @Test("外接矩形は 5×5 に収まる（コンティニューの前提）")
    func boundingBoxFitsReviveRegion() {
        let limit = BlockPuzzleBoard.reviveRegionSize
        for piece in BlockPuzzlePiece.catalog {
            #expect(piece.width <= limit && piece.height <= limit, "ピース\(piece.id) が 5×5 に収まらない")
        }
    }

    @Test("色番号は 1...5（0 は空きマスの予約）")
    func colorIndexRange() {
        for piece in BlockPuzzlePiece.catalog {
            #expect((1...5).contains(piece.colorIndex))
        }
    }

    @Test("落ち物テトロミノの S / Z 形は入れていない（置き型に限定する設計）")
    func hasNoSOrZShapes() {
        // S / Z は「2×3 の外接矩形に 4 マス」で、L 字（3 マス）や大きい L 字（5 マス）と
        // マス数で区別できる。該当する形が 1 つも無いことを確かめる。
        let sOrZ = BlockPuzzlePiece.catalog.filter {
            $0.size == 4 && !($0.width == 1 || $0.height == 1) && !($0.width == 2 && $0.height == 2)
        }
        #expect(sOrZ.isEmpty)
    }
}

@Suite("ブロックならべ: 盤の判定")
struct BlockPuzzleBoardTests {

    /// 指定した形のピースをその場で作る（カタログの並びに依存せずに境界を突くため）。
    private func piece(_ cells: [(Int, Int)], id: Int = 0) -> BlockPuzzlePiece {
        BlockPuzzlePiece(id: id, cells: cells.map { BlockPuzzleCell(row: $0.0, col: $0.1) })
    }

    @Test("空盤は 10×10 ですべて 0")
    func emptyBoard() {
        let board = BlockPuzzleBoard.emptyBoard()
        #expect(board.count == 10)
        #expect(board.allSatisfy { $0.count == 10 && $0.allSatisfy { $0 == 0 } })
        #expect(BlockPuzzleBoard.isValid(board))
    }

    @Test("盤の妥当性は大きさと色番号の両方で見る")
    func validation() {
        var board = BlockPuzzleBoard.emptyBoard()
        board[0][0] = 5
        #expect(BlockPuzzleBoard.isValid(board))
        board[0][0] = 6
        #expect(!BlockPuzzleBoard.isValid(board), "色番号 6 は存在しない")
        board[0][0] = -1
        #expect(!BlockPuzzleBoard.isValid(board))
        #expect(!BlockPuzzleBoard.isValid([[0, 0], [0, 0]]), "9×9 以下の盤は復元しない")
    }

    @Test("盤からはみ出す位置には置けない")
    func rejectsOutOfBounds() {
        let board = BlockPuzzleBoard.emptyBoard()
        let bar = piece([(0, 0), (0, 1), (0, 2)])
        #expect(BlockPuzzleBoard.canPlace(board, bar, row: 0, col: 7))
        #expect(!BlockPuzzleBoard.canPlace(board, bar, row: 0, col: 8), "右へ 1 マスはみ出す")
        #expect(!BlockPuzzleBoard.canPlace(board, bar, row: -1, col: 0))
        #expect(!BlockPuzzleBoard.canPlace(board, bar, row: 10, col: 0))
    }

    @Test("埋まっているマスには置けない（重ね置きの拒否）")
    func rejectsOccupied() {
        var board = BlockPuzzleBoard.emptyBoard()
        board[3][4] = 2
        let square = piece([(0, 0), (0, 1), (1, 0), (1, 1)])
        #expect(!BlockPuzzleBoard.canPlace(board, square, row: 3, col: 3))
        #expect(BlockPuzzleBoard.canPlace(board, square, row: 5, col: 3))
        #expect(BlockPuzzleBoard.place(board, square, row: 3, col: 3) == nil)
    }

    @Test("置くとピースの色でマスが埋まる")
    func placeFillsCells() {
        let board = BlockPuzzleBoard.emptyBoard()
        let l = piece([(0, 0), (1, 0), (1, 1)])   // 3 マス → 色番号 3
        let placed = BlockPuzzleBoard.place(board, l, row: 2, col: 5)
        #expect(placed?[2][5] == 3)
        #expect(placed?[3][5] == 3)
        #expect(placed?[3][6] == 3)
        #expect(placed?[2][6] == 0, "占めていないマスは触らない")
    }

    @Test("行が揃うと消える")
    func clearsFullRow() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 0..<10 { board[4][c] = 1 }
        board[5][0] = 2
        let result = BlockPuzzleBoard.clearLines(board)
        #expect(result.lines == 1)
        #expect(result.board[4].allSatisfy { $0 == 0 })
        #expect(result.board[5][0] == 2, "揃っていない行は残る")
    }

    @Test("列が揃うと消える")
    func clearsFullColumn() {
        var board = BlockPuzzleBoard.emptyBoard()
        for r in 0..<10 { board[r][7] = 4 }
        let result = BlockPuzzleBoard.clearLines(board)
        #expect(result.lines == 1)
        #expect(result.board.allSatisfy { $0[7] == 0 })
    }

    /// 行を先に消してから列を数えると、交差していた列が未完成に変わって 1 本ぶん取りこぼす。
    /// 同時判定になっていることをこのテストで固定する。
    @Test("交差した行と列は同時に 2 本として消える")
    func clearsCrossingRowAndColumnTogether() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 0..<10 { board[2][c] = 1 }
        for r in 0..<10 { board[r][3] = 2 }
        let result = BlockPuzzleBoard.clearLines(board)
        #expect(result.lines == 2)
        #expect(result.board.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    @Test("揃っていなければ何も消えず盤も変わらない")
    func noClear() {
        var board = BlockPuzzleBoard.emptyBoard()
        for c in 0..<9 { board[0][c] = 1 }
        let result = BlockPuzzleBoard.clearLines(board)
        #expect(result.lines == 0)
        #expect(result.board == board)
    }

    @Test("手元のどれか 1 つでも置ければゲームオーバーではない")
    func gameOverNeedsEveryPieceStuck() {
        // 1 マスだけ空いた盤。
        var board = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        board[9][9] = 0
        let single = piece([(0, 0)], id: 0)
        let pair = piece([(0, 0), (0, 1)], id: 1)

        #expect(!BlockPuzzleBoard.isGameOver(board, hand: [pair, single, nil]))
        #expect(BlockPuzzleBoard.isGameOver(board, hand: [pair, nil, nil]))
        #expect(BlockPuzzleBoard.isGameOver(board, hand: [nil, nil, nil]), "手元が空なら置きようがない")
    }

    @Test("コンティニューは中央 5×5 を空け、どの形も置けるようになる")
    func reviveOpensCenter() {
        let full = Array(repeating: Array(repeating: 3, count: 10), count: 10)
        let revived = BlockPuzzleBoard.revive(full)

        let empty: Int = revived.reduce(0) { $0 + $1.filter { $0 == 0 }.count }
        #expect(empty == 25)
        for r in 2..<7 {
            for c in 2..<7 { #expect(revived[r][c] == 0) }
        }
        #expect(revived[1][1] == 3, "領域の外は残す")
        for candidate in BlockPuzzlePiece.catalog {
            #expect(BlockPuzzleBoard.canPlaceAnywhere(revived, candidate),
                    "ピース\(candidate.id) が復活後に置けない")
        }
    }

    @Test("コンティニューは乱数を使わないので、同じ盤からは必ず同じ結果になる")
    func reviveIsDeterministic() {
        let full = Array(repeating: Array(repeating: 2, count: 10), count: 10)
        #expect(BlockPuzzleBoard.revive(full) == BlockPuzzleBoard.revive(full))
    }

    /// 「配られた瞬間に詰んでいる」局面を作らない、という設計上の性質。
    @Test("置ける形がカタログにある限り、配られる 3 つのうち必ず 1 つは置ける")
    func dealtHandIsAlwaysPlayable() {
        // 空きが縦 1 マス × 3 か所しか無い盤（置けるのは 1×1 だけ）。
        var tight = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        tight[0][0] = 0
        tight[5][5] = 0
        tight[9][9] = 0

        for seed in UInt64(1)...200 {
            var rng = BlockPuzzleRandom(seed: seed)
            let hand = BlockPuzzleBoard.makeHand(board: tight, using: &rng)
            #expect(hand.count == 3)
            #expect(hand.contains { BlockPuzzleBoard.canPlaceAnywhere(tight, $0) },
                    "種 \(seed): 置ける形が 1 つも配られなかった")
        }
    }

    @Test("どの形も置けない盤では救済せずそのまま配る（本当の詰み）")
    func dealtHandOnFullBoard() {
        let full = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        var rng = BlockPuzzleRandom(seed: 7)
        let hand = BlockPuzzleBoard.makeHand(board: full, using: &rng)
        #expect(hand.count == 3)
        #expect(BlockPuzzleBoard.isGameOver(full, hand: hand.map { Optional($0) }))
    }

    @Test("同じ種からは同じ手札が出る")
    func handIsReproducible() {
        var a = BlockPuzzleRandom(seed: 42)
        var b = BlockPuzzleRandom(seed: 42)
        let board = BlockPuzzleBoard.emptyBoard()
        #expect(BlockPuzzleBoard.makeHand(board: board, using: &a)
                == BlockPuzzleBoard.makeHand(board: board, using: &b))
    }
}

@Suite("ブロックならべ: 得点")
struct BlockPuzzleScoringTests {

    @Test("配置点は埋めたマス数")
    func placement() {
        for piece in BlockPuzzlePiece.catalog {
            #expect(BlockPuzzleScoring.placementPoints(piece) == piece.cells.count)
        }
    }

    @Test("まとめて消すほど 1 本あたりが伸びる")
    func clearGrowsWithLines() {
        #expect(BlockPuzzleScoring.clearPoints(lines: 1, combo: 1) == 10)
        #expect(BlockPuzzleScoring.clearPoints(lines: 2, combo: 1) == 30)
        #expect(BlockPuzzleScoring.clearPoints(lines: 3, combo: 1) == 60)
        #expect(BlockPuzzleScoring.clearPoints(lines: 4, combo: 1) == 100)
    }

    @Test("連鎖は倍率として掛かる")
    func comboMultiplies() {
        #expect(BlockPuzzleScoring.clearPoints(lines: 2, combo: 3) == 90)
    }

    @Test("消していない手には点が付かない")
    func noClearNoPoints() {
        #expect(BlockPuzzleScoring.clearPoints(lines: 0, combo: 5) == 0)
        #expect(BlockPuzzleScoring.clearPoints(lines: 2, combo: 0) == 0)
    }
}

@Suite("ブロックならべ: ドラッグ位置の翻訳")
struct BlockPuzzleDropTests {

    private let square = BlockPuzzlePiece(
        id: 0,
        cells: [(0, 0), (0, 1), (1, 0), (1, 1)].map { BlockPuzzleCell(row: $0.0, col: $0.1) }
    )

    @Test("ピースは指より上に描かれる（置き先を指で隠さない）")
    func liftsAboveFinger() {
        let center = BlockPuzzleDrop.pieceCenter(touch: CGPoint(x: 100, y: 200), cellSize: 30)
        let expectedY: CGFloat = 200 - 1.5 * 30
        #expect(center.x == CGFloat(100))
        #expect(center.y == expectedY)
    }

    @Test("中心が 2×2 のマスにぴたり重なる位置では、その左上マスが選ばれる")
    func centerMapsToTopLeftCell() {
        // セル 30pt・2×2 のピース。行 3 列 4 に置くとき、中心は (4+1)*30 = 150, (3+1)*30 = 120。
        let target = BlockPuzzleDrop.targetCell(
            center: CGPoint(x: 150, y: 120), piece: square, cellSize: 30
        )
        #expect(target.row == 3)
        #expect(target.col == 4)
    }

    @Test("半マス未満のずれは最も近いマスへ丸める")
    func roundsToNearestCell() {
        let near = BlockPuzzleDrop.targetCell(
            center: CGPoint(x: 150 + 14, y: 120 - 14), piece: square, cellSize: 30
        )
        #expect(near.row == 3 && near.col == 4)

        let far = BlockPuzzleDrop.targetCell(
            center: CGPoint(x: 150 + 16, y: 120), piece: square, cellSize: 30
        )
        #expect(far.col == 5, "半マスを超えたら隣のマスへ移る")
    }

    /// 盤の外へ落としたときに端へ吸い付くと、外へ捨てたつもりの手が成立してしまう。
    @Test("盤の外の位置は盤の中へ丸めない")
    func keepsOutOfBoardTargets() {
        let target = BlockPuzzleDrop.targetCell(
            center: CGPoint(x: -100, y: -100), piece: square, cellSize: 30
        )
        #expect(target.row < 0 && target.col < 0)
    }

    @Test("セルの寸法が未測定でも落ちない")
    func toleratesZeroCellSize() {
        let target = BlockPuzzleDrop.targetCell(center: .zero, piece: square, cellSize: 0)
        #expect(target == (0, 0))
    }
}
