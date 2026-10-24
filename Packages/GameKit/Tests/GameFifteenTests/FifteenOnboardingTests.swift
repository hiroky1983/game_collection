import Testing
import Core
@testable import GameFifteen

/// 図で見る「はじめての遊び方」（#2826）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("15パズル: はじめての遊び方")
struct FifteenOnboardingTests {
    /// 図の小さな盤（行の並び）を 4×4 の盤の左上に置き、残りのマスは使っていない数で埋める。
    private func embed(_ rows: [[Int]]) -> [Int] {
        let n = FifteenLogic.size
        let used = Set(rows.flatMap { $0 })
        var rest = (1..<FifteenLogic.cellCount).filter { !used.contains($0) }.makeIterator()
        var tiles = [Int](repeating: -1, count: FifteenLogic.cellCount)
        for (r, row) in rows.enumerated() {
            for (c, v) in row.enumerated() { tiles[r * n + c] = v }
        }
        for i in tiles.indices where tiles[i] == -1 { tiles[i] = rest.next()! }
        return tiles
    }

    /// 4×4 の盤から左上の `rows` 行 × `cols` 列を切り出す。
    private func crop(_ tiles: [Int], rows: Int, cols: Int) -> [[Int]] {
        (0..<rows).map { r in (0..<cols).map { c in tiles[r * FifteenLogic.size + c] } }
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(FifteenOnboarding.guide.isWellFormed)
        #expect(FifteenOnboarding.guide.gameID == FifteenModel(tiles: FifteenLogic.solved).gameID)
        #expect(FifteenOnboarding.guide.gameID == FifteenModule().id)
    }

    @Test("目的の図: はじめの盤は揃っていないが解ける。おわりの盤は揃った盤")
    func goalFigure() {
        let start = FifteenOnboarding.startBoard
        #expect(FifteenLogic.isPermutation(start))
        #expect(!FifteenLogic.isSolved(start))
        #expect(FifteenLogic.isSolvable(start))
        #expect(start.filter { $0 == 0 }.count == 1, "空白は 1 マスだけ")
    }

    @Test("1 枚スライドの図: 空白の隣をタップすると、そのタイルが空白へ動く（手数 1）")
    func slideFigure() throws {
        let slide = FifteenHowToFigures.slide
        let tiles = embed(slide.before)
        let index = try #require(tiles.firstIndex(of: slide.tapped))
        let result = try #require(FifteenLogic.slide(tiles, at: index))
        #expect(crop(result.tiles, rows: 2, cols: 2) == slide.after)
        #expect(result.distance == 1)
    }

    @Test("まとめて動く図: 同じ行の離れたタイルをタップすると、間ごと動き、動いた枚数が手数に入る")
    func rowSlideFigure() throws {
        let row = FifteenHowToFigures.rowSlide
        let tiles = embed([row.before])
        let index = try #require(tiles.firstIndex(of: row.tapped))
        let result = try #require(FifteenLogic.slide(tiles, at: index))
        #expect(crop(result.tiles, rows: 1, cols: 4) == [row.after])
        let model = FifteenModel(tiles: tiles)
        model.tap(at: index)
        #expect(model.tiles == result.tiles)
        #expect(model.moves == row.before.filter { $0 != 0 }.count)
    }

    @Test("動かせないタイルの図: 空白と同じ行・列にない（ななめの）タイルはタップしても動かない")
    func blockedFigure() {
        let before = FifteenHowToFigures.slide.before
        let tiles = embed(before)
        // 印を付けるのは左下（1 行 0 列）のタイル。空白は右上（0 行 1 列）。
        #expect(before[0][1] == 0)
        #expect(before[1][0] != 0)
        let index = 1 * FifteenLogic.size + 0
        #expect(FifteenLogic.slide(tiles, at: index) == nil)
        let model = FifteenModel(tiles: tiles)
        model.tap(at: index)
        #expect(model.tiles == tiles)
        #expect(model.moves == 0)
    }

    @Test("勝ち負け: 1〜15 を左上から順に並べたらクリア。ヒントは次に動かすタイルを示す")
    func clearAndHint() throws {
        // 揃った盤から空白を 1 手左へずらした盤（あと 1 手で揃う）。
        let almost = try #require(FifteenLogic.slide(FifteenLogic.solved, at: FifteenLogic.cellCount - 2)).tiles
        let hinted = FifteenModel(tiles: almost)
        hinted.requestHint()
        let hint = try #require(hinted.hintIndex)
        #expect(FifteenLogic.slide(almost, at: hint)?.distance == 1, "ヒントは空白の隣のタイル")
        let model = FifteenModel(tiles: almost)
        #expect(!model.isSolved)
        model.tap(at: FifteenLogic.cellCount - 1)
        #expect(model.isSolved)
        #expect(model.tiles == FifteenLogic.solved)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in FifteenOnboarding.guide.texts + ["はじめ", "おわり", "同じ行・列にないと動かない"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
