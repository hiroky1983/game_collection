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

/// 選択した駒の持ち上げ演出（将棋と同じ値・同じ理由）。
@Suite("チェス 駒の持ち上げ演出")
struct ChessPieceLiftMotionTests {

    @Test("持ち上げは駒の移動より速い（掴んだ手応えが遅れて見えない）")
    func liftIsFasterThanPieceMove() {
        #expect(ChessMotion.pieceLiftResponse < ChessMotion.pieceMoveResponse)
        // 秒の定数から `Animation` を組んでいること（定数だけ直しても演出が変わらない、を防ぐ）。
        #expect(ChessMotion.pieceLift == .spring(response: ChessMotion.pieceLiftResponse, dampingFraction: 0.7))
        // 持ち上げ量と拡大は「浮いたと分かる最小限」。隣のマスに被るほど大きくしない。
        #expect(ChessMotion.pieceLiftRatio > 0 && ChessMotion.pieceLiftRatio <= 0.2)
        #expect(ChessMotion.pieceLiftScale > 1 && ChessMotion.pieceLiftScale <= 1.15)
    }

    /// 修飾子の**置き場所**で決まるため、値では検証できない（将棋 `ShogiPieceLayerSourceTests` と同じ流儀）。
    @Test("盤の角丸は駒の層より前に掛ける（持ち上げた駒が上端で切れる）")
    func clipShapeComesBeforePieceLayer() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameChessTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameChess/ChessView.swift")
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // 走査は `board` の中だけに限る（ファイル全体だと別の面の clipShape を拾う）。
        guard let start = all.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "private var board: some View {" }) else {
            Issue.record("走査の前提が壊れている: private var board が見つからない")
            return
        }
        let indent = all[start].prefix { $0 == " " }
        guard let end = all[start...].dropFirst().firstIndex(where: { $0 == indent + "}" }) else {
            Issue.record("走査の前提が壊れている: private var board の終わりが見つからない")
            return
        }
        let lines = all[start...end].map { $0.trimmingCharacters(in: .whitespaces) }
        let clips = lines.enumerated().filter { $0.element.hasPrefix(".clipShape(") }
        // 2つ目を後ろに足されると、そちらが駒の層まで丸めてしまう（数も固定する）。
        #expect(clips.count == 1, "盤の clipShape が1つではない:\n\(lines.joined(separator: "\n"))")
        guard let clip = clips.first?.offset,
              let piece = lines.firstIndex(of: ".overlay { pieceLayer(cell: cell) }") else {
            Issue.record("盤の clipShape / 駒の層が見つからない（走査の前提が壊れている）")
            return
        }
        #expect(clip < piece)
    }
}
