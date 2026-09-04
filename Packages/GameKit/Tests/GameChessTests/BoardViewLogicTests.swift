import Testing
import Foundation
@testable import GameChess

private func sq(_ name: String) -> Int { ChessSquare.fromName(Substring(name))! }

@Suite("チェス 盤の向き（白視点／黒反転）")
struct ChessBoardOrientationTests {

    @Test("反転なしは白視点（左上 a8・右下 h1）")
    func whiteView() {
        #expect(ChessSquare.boardIndex(row: 0, col: 0, flipped: false) == sq("a8"))
        #expect(ChessSquare.boardIndex(row: 7, col: 7, flipped: false) == sq("h1"))
        // 白の初期配置が手前（下の 2 段）に来る。
        #expect(ChessSquare.boardIndex(row: 7, col: 4, flipped: false) == sq("e1"))
    }

    @Test("反転すると黒が手前（左上 h1・右下 a8）")
    func blackView() {
        #expect(ChessSquare.boardIndex(row: 0, col: 0, flipped: true) == sq("h1"))
        #expect(ChessSquare.boardIndex(row: 7, col: 7, flipped: true) == sq("a8"))
        #expect(ChessSquare.boardIndex(row: 7, col: 3, flipped: true) == sq("e8"))
    }

    @Test("画面座標とマスの対応が 1 対 1（どちらの向きでも 64 マス全部に届く）")
    func everyCellMapsToUniqueSquare() {
        for flipped in [false, true] {
            var seen = Set<Int>()
            for row in 0..<8 { for col in 0..<8 {
                seen.insert(ChessSquare.boardIndex(row: row, col: col, flipped: flipped))
            }}
            #expect(seen.count == 64)
        }
    }

    @Test("displayPosition は boardIndex の逆変換になっている")
    func displayPositionIsInverse() {
        for flipped in [false, true] {
            for square in 0..<64 {
                let spot = ChessSquare.displayPosition(of: square, flipped: flipped)
                #expect(ChessSquare.boardIndex(row: spot.row, col: spot.col, flipped: flipped) == square)
            }
        }
    }

    @Test("マスの明暗は市松で、白から見て右下（h1）が明るい")
    func squareColorsAlternate() {
        #expect(ChessSquare.isLightSquare(sq("h1")))
        #expect(ChessSquare.isLightSquare(sq("a1")) == false)
        #expect(ChessSquare.isLightSquare(sq("a8")))
        for square in 0..<64 {
            let right = square + 1
            guard ChessSquare.file(right) != 0, right < 64 else { continue }
            #expect(ChessSquare.isLightSquare(square) != ChessSquare.isLightSquare(right),
                    "\(ChessSquare.name(square)) と隣は必ず色が違う")
        }
    }
}

@MainActor
@Suite("チェス 直前手のハイライト・表記")
struct ChessLastMoveTests {

    @Test("直前手の移動元・移動先がハイライトされ、表記が出る")
    func highlightsLastMove() {
        let model = ChessGameModel(services: nil)
        model.tapSquare(sq("g1"))
        model.tapSquare(sq("f3"))
        #expect(model.highlightedSquares == [sq("g1"), sq("f3")])
        #expect(model.highlightedMoveText == "Nf3")
    }

    @Test("開始直後はハイライトも表記も無い")
    func noHighlightAtStart() {
        let model = ChessGameModel(services: nil)
        #expect(model.highlightedMove == nil)
        #expect(model.highlightedSquares.isEmpty)
        #expect(model.highlightedMoveText == nil)
    }

    @Test("取られた駒は価値の高い順に並ぶ（プロモーションで増えても負にならない）")
    func capturedPieces() {
        let model = ChessGameModel(services: nil)
        #expect(model.capturedPieces(of: .white).isEmpty)
        #expect(model.capturedPieces(of: .black).isEmpty)

        // 黒がクイーンとポーンを失った局面を作る。
        let store = MockChessSnapshotStore()
        try? store.save(ChessSnapshot(
            initialFen: "rnb1kbnr/1ppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            moves: [], phase: .playing, reviewPly: nil,
            white: .human, black: .human, aiLevel: nil, startedAt: Date(), undoUsed: false
        ), for: "chess")
        let lost = ChessGameModel(services: makeChessServices(store))
        #expect(lost.capturedPieces(of: .black) == [.queen, .pawn], "価値の高い順")
        #expect(lost.capturedPieces(of: .white).isEmpty)
    }
}
