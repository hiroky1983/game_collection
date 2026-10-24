import Testing
import Core
@testable import GameGo

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("囲碁: はじめての遊び方")
struct GoOnboardingTests {
    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(GoOnboarding.guide.isWellFormed)
        #expect(GoOnboarding.guide.gameID == GoModule().id)
    }

    @Test("取る図: 最後の呼吸点を埋めると白 1 子が取り上げられる")
    func capture() {
        var state = GoDiagram.state([
            ".....",
            "..X..",
            ".XOX.",
            ".....",
            ".....",
        ], to: .black)
        #expect(state.play(.play(GoPoint(row: 3, col: 2))) == nil)
        #expect(state.board[GoPoint(row: 2, col: 2)] == nil)
        #expect(state.captures[GoStone.black.rawValue] == 1)
    }

    @Test("打てない図: 呼吸点の無くなる交点は自殺手")
    func suicide() {
        var state = GoDiagram.state(GoOnboarding.suicideDiagram, to: .black)
        #expect(state.play(.play(GoPoint(row: 2, col: 2))) == .suicide)
    }

    @Test("打てない図: 相手を取れるなら、呼吸点が無く見える交点にも打てる")
    func suicideExceptionWhenCapturing() {
        var state = GoDiagram.state([
            ".....",
            "..OX.",
            ".O.OX",
            "..OX.",
            ".....",
        ], to: .black)
        // (2, 2) へ打つと白の (2, 3) が呼吸点を失って取られる。
        #expect(state.play(.play(GoPoint(row: 2, col: 2))) != .suicide)
    }

    @Test("コウ: 1 子を取り返した直後は、取り返し返せない")
    func ko() {
        var state = GoDiagram.state([
            ".XO..",
            "X.XO.",
            ".XO..",
            ".....",
            ".....",
        ], to: .white)
        #expect(state.play(.play(GoPoint(row: 1, col: 1))) == nil)   // 白が黒 1 子を取る
        #expect(state.play(.play(GoPoint(row: 1, col: 2))) == .ko)   // 黒はすぐには取り返せない
    }

    @Test("数え方: 両者が続けてパスすると終局。白はコミ 6.5 目が足される")
    func scoring() {
        var state = GoState()
        #expect(!state.isTwoPassEnd)
        state.play(.pass)
        state.play(.pass)
        #expect(state.isTwoPassEnd)

        let rules = GoRuleset()
        #expect(rules.size == 9)
        #expect(rules.komi == 6.5)
        #expect(GoOnboarding.exampleBlackArea + GoOnboarding.exampleWhiteArea == rules.size * rules.size)
        let score = GoScore(blackArea: GoOnboarding.exampleBlackArea, whiteArea: GoOnboarding.exampleWhiteArea,
                            neutral: 0, komi: rules.komi, handicapCompensation: 0)
        #expect(score.whiteTotal == 46.5)
        #expect(score.winner == .white)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in GoOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
