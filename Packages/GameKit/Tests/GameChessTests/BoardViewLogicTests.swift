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

/// 盤の組み方（#530）。演出の**値**（持ち上げが駒の移動より速い、等）は共通の
/// `BoardGameMotion` が持つようになったため、検証も Core 側の `BoardGameMotionTests` に 1 つだけ置く
/// （`ChessMotion` は `BoardGameMotion` の別名なので、ここで同じことを書いても二重管理になる）。
/// ここに残すのは**チェスのソースの組み方**、つまり共通実装に乗っているかどうかだけ。
@Suite("チェス 盤の組み方")
struct ChessBoardViewSourceTests {

    /// 角丸 → 駒 → 王手 → 着手先 の重なり順そのものは、共通の `boardLayers`（Core・#530）が持つ。
    /// **順番の検証はそちらに移した**（`BoardGameChromeSourceTests`）。ここではチェスが自前で
    /// 積み直していないこと = 共通の順番に乗っていることだけを見る。
    /// 修飾子の**置き場所**で決まるため、値では検証できない（将棋 `ShogiPieceLayerSourceTests` と同じ流儀）。
    @Test("盤は共通の boardLayers に乗る（自前で層を積み直さない）")
    func boardUsesSharedLayerOrder() throws {
        let lines = try Self.lines(ofFunction: "private var board: some View {")
        #expect(lines.contains(".boardLayers("), "board が boardLayers を使っていない:\n\(lines.joined(separator: "\n"))")
        #expect(lines.contains("pieces: { pieceLayer(cell: cell) },"))
        #expect(lines.contains("check: { checkLayer(cell: cell) },"))
        #expect(lines.contains("targets: { targetLayer(cell: cell) }"))
        #expect(lines.contains { $0.hasPrefix(".clipShape(") } == false,
                "board に自前の clipShape がある（共通の角丸と二重に掛かる）:\n\(lines.joined(separator: "\n"))")
        // 座標の層（チェスにしかない）は共通の重ね順の**後ろ**に来る。共通の 3 層より前に
        // 割り込ませると、駒や着手先の印が座標の文字に隠れる。
        guard let shared = lines.firstIndex(of: ".boardLayers("),
              let coordinate = lines.firstIndex(of: ".overlay { coordinateLayer(cell: cell) }") else {
            Issue.record("boardLayers / 座標の層が見つからない（走査の前提が壊れている）")
            return
        }
        #expect(shared < coordinate)
        // 共通の 3 層を自前の overlay で足し直していないこと（座標の 1 枚だけが許される）。
        #expect(lines.filter { $0.hasPrefix(".overlay {") } == [".overlay { coordinateLayer(cell: cell) }"])
    }

    /// 選択した駒の持ち上げの見た目は共通の `pieceLift`（Core・#530）に置く。
    /// 自前に書き戻すと、将棋と片方だけずれた状態に戻る。
    @Test("駒の持ち上げは共通の pieceLift を使い、アニメーションはその後ろに置く")
    func pieceLiftUsesSharedModifier() throws {
        let lines = try Self.lines(ofFunction: "private func pieceLayer(cell: CGFloat) -> some View {")
        #expect(lines.contains(".pieceLift(isLifted: isLifted, cell: cell)"),
                "共通の pieceLift を使っていない:\n\(lines.joined(separator: "\n"))")
        // 持ち上げは**駒単位**（`isLifted`）、移動は**層に1つ**（`pieceLayout`）。並び順が構造を表す。
        let animations = lines.filter { $0.hasPrefix(".gameAnimation(") }
        #expect(animations == [
            ".gameAnimation(ChessMotion.pieceLift, value: isLifted)",
            ".gameAnimation(ChessMotion.pieceMove, value: pieceLayout)",
        ])
        guard let modifier = lines.firstIndex(of: ".pieceLift(isLifted: isLifted, cell: cell)"),
              let lift = lines.firstIndex(of: ".gameAnimation(ChessMotion.pieceLift, value: isLifted)"),
              let transition = lines.firstIndex(where: { $0.hasPrefix(".transition(") }) else {
            Issue.record("駒の層の指定が見つからない（走査の前提が壊れている）")
            return
        }
        // 見た目 → アニメーション → `.transition` の順。アニメーションを前に置くと
        // 拡大・影・浮かせに掛からず、持ち上げが一瞬で切り替わる。
        #expect(modifier < lift)
        #expect(lift < transition)
        // `.animation` の直呼びは Reduce Motion を無視する（#210）。
        #expect(lines.contains { $0.hasPrefix(".animation(") } == false)
    }

    /// 宣言行から、インデントが戻るまでを 1 つのまとまりとして切り出す（前後の空白は落とす）。
    private static func lines(ofFunction declaration: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameChessTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameChess/ChessView.swift")
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = all.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == declaration }) else {
            Issue.record("走査の前提が壊れている: \(declaration) が見つからない")
            return []
        }
        let indent = all[start].prefix { $0 == " " }
        guard let end = all[start...].dropFirst().firstIndex(where: { $0 == indent + "}" }) else {
            Issue.record("走査の前提が壊れている: \(declaration) の終わりが見つからない")
            return []
        }
        return all[start...end].map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
