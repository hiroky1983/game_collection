import Testing
import Core
@testable import Game2048

/// 図で見る「はじめての遊び方」（#2826）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("2048: はじめての遊び方")
struct Game2048OnboardingTests {
    /// 1 行だけタイルのある 4×4 の盤。
    private func board(firstRow: [Int]) -> [[Int]] {
        var b = Game2048Logic.emptyBoard()
        b[0] = firstRow
        return b
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(Game2048Onboarding.guide.isWellFormed)
        #expect(Game2048Onboarding.guide.gameID == Game2048Model(services: nil).gameID)
    }

    @Test("スライドの図: 左へスワイプすると、全部が左へ寄る")
    func slide() {
        let row = Game2048HowToFigures.slideRow
        let result = Game2048Logic.slideRowLeft(row.before)
        #expect(result.row == row.after)
        #expect(result.gained == 0)
    }

    @Test("合体の図: 同じ数字は 2 倍になり、できた数字がスコアに入る")
    func merge() {
        let row = Game2048HowToFigures.mergeRow
        let result = Game2048Logic.slideRowLeft(row.before)
        #expect(result.row == row.after)
        #expect(result.gained == row.after.reduce(0, +))
    }

    @Test("新しいタイルの図: 寄ったあとの空きに 2 か 4 が 1 枚だけ出る")
    func spawnFigure() {
        let slid = Game2048HowToFigures.slideRow.after
        let spawn = Game2048Onboarding.spawnRow
        let changed = slid.indices.filter { slid[$0] != spawn[$0] }
        #expect(changed.count == 1)
        #expect(changed.allSatisfy { slid[$0] == 0 && [2, 4].contains(spawn[$0]) })
    }

    @Test("動かすたびに、空いたマスに 2 か 4 のタイルが 1 枚出る")
    func spawnOnMove() {
        for _ in 0..<30 {
            let model = Game2048Model(services: nil, board: board(firstRow: Game2048HowToFigures.slideRow.before))
            let before = Game2048Logic.slide(model.board, .left).board
            model.move(.left)
            let added = (0..<4).flatMap { r in (0..<4).map { (r, $0) } }
                .filter { before[$0.0][$0.1] != model.board[$0.0][$0.1] }
            #expect(added.count == 1)
            #expect(added.allSatisfy { before[$0.0][$0.1] == 0 && [2, 4].contains(model.board[$0.0][$0.1]) })
        }
    }

    @Test("2048 を作るとクリアで、そのまま続けられる")
    func winAndContinue() {
        let model = Game2048Model(services: nil, board: board(firstRow: [1024, 1024, 0, 0]))
        model.move(.left)
        #expect(model.hasWon)
        #expect(model.showWinPrompt)
        model.continueAfterWin()
        #expect(!model.showWinPrompt)
        #expect(!model.gameOver)
    }

    @Test("ゲームオーバーの図: どこにも動かせない。コンティニューは 1 回だけ")
    func stuck() {
        let stuck = Game2048Onboarding.stuckBoard
        #expect(Game2048Logic.isGameOver(stuck))
        #expect(Direction.allCases.allSatisfy { !Game2048Logic.slide(stuck, $0).moved })
        let model = Game2048Model(services: nil, board: stuck)
        #expect(model.gameOver)
        #expect(model.continueAfterAd())
        #expect(!model.gameOver)
        #expect(model.continueUsed)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in Game2048Onboarding.guide.texts + ["新しいタイルが 1 枚出る", "どこにも動かせない → ゲームオーバー"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
