import Foundation
import Testing
@testable import Core
import GameKitTestSupport

/// タイトルの下の「今の条件」チップ（#1690・会長決裁 2026-10-25）。
///
/// 言葉の組み立て（全文 / 難易度だけ）を値で固定し、9 ゲームが共通枠へ条件を渡していること、
/// チップのタップが「新規」ボタンと同じ入口を呼ぶことをソース走査で見る。
@Suite("条件のチップ")
struct GameChromeConditionTests {
    @Test("全文は「・」でつなぎ、縮めた形は先頭（難易度）だけ")
    func fullAndShortText() {
        let condition = GameChromeCondition(["ふつう", "先手", "禁じ手あり"]) {}
        #expect(condition.fullText == "ふつう・先手・禁じ手あり")
        #expect(condition.shortText == "ふつう")
        #expect(condition.hasShortForm)
    }

    @Test("空の言葉は捨てる。1 語だけなら縮めた形は無い")
    func emptyPartsAreDropped() {
        let condition = GameChromeCondition(["初級", ""]) {}
        #expect(condition.fullText == "初級")
        #expect(condition.shortText == "初級")
        #expect(!condition.hasShortForm)
    }

    /// 条件を選べる 9 ゲーム。それぞれの View が `condition:` を渡し、タップは「新規」と同じ `requestNewGame()` を呼ぶ。
    private static let games: [(module: String, view: String, fullScreen: Bool)] = [
        ("GameShogi", "ShogiView", false), ("GameChess", "ChessView", false), ("GameGo", "GoView", false),
        ("GameGomoku", "GomokuView", false), ("GameOthello", "OthelloView", false),
        ("GameConcentration", "ConcentrationView", true), ("GameShiritori", "ShiritoriView", false),
        ("GameMinesweeper", "MinesweeperView", false), ("GameSudoku", "SudokuView", false),
    ]

    @Test("9 ゲームが条件を共通枠へ渡し、タップは「新規」と同じ入口を呼ぶ", arguments: games.map(\.view))
    func gamesPassCondition(view: String) throws {
        let entry = try #require(Self.games.first { $0.view == view })
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/\(entry.module)/\(entry.view).swift"))
        #expect(SourceScan.matchCount(of: #"condition: GameChromeCondition\("#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"GameChromeCondition\([^{]*\)\s*\{\s*requestNewGame\(\)\s*\}"#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"GameChromeNewGame\([^{]*\)\s*\{\s*requestNewGame\(\)\s*\}"#, in: source) == 1)
    }
}
