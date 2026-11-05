import Core
import CoreMiniBoard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）の囲碁。
///
/// 中国ルール（面積計算）・9 路盤・コミ 6.5 目・自殺手とコウの禁止は `GoRules` / `GoScoring` / `GoRuleset` の実装どおり。
/// 取る図・打てない図・数え方の図は `GoOnboardingTests` が同じ局面を `GoState` で動かして確かめる。
/// 置き石・死に石の判定・コウの細かい扱いは「くわしいルール」へ任せ、ここでは触れない。
@MainActor
enum GoOnboarding {
    /// 打てない場所の図（5 路・`.` 空点 / `X` 黒 / `O` 白）。中央（2, 2）に黒は打てない（自殺手）。
    static let suicideDiagram = [
        ".....",
        "..O..",
        ".O.O.",
        "..O..",
        ".....",
    ]

    /// 数え方の図の数字。9 路盤 81 点を黒 41・白 40 で分けた終局（コミ 6.5 目）。
    static let exampleBlackArea = 41
    static let exampleWhiteArea = 40

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "go",
            title: tr("囲碁のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("黒と白が交互に石を置いて、陣地を取り合うゲームです。"),
                        tr("盤上の自分の石と、自分だけが囲んだ地の合計が多い方が勝ちです。"),
                    ],
                    figure: { AnyView(GoHowToFigures.TerritoryFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("線が交わる交点をタップして、石を置きます。"),
                        tr("置いた石は動かせません。黒と白が交互に置きます。"),
                    ],
                    figure: { AnyView(GoHowToFigures.PlaceFigure()) }
                ),
                OnboardingPage(
                    heading: tr("石を取る"),
                    lines: [
                        tr("石のまわりのたて・よこの空点を「呼吸点」といいます。"),
                        tr("相手の石の呼吸点をすべて埋めると、その石を取り上げられます。"),
                    ],
                    figure: { AnyView(GoHowToFigures.CaptureFigure()) }
                ),
                OnboardingPage(
                    heading: tr("打てない場所"),
                    lines: [
                        tr("自分の石の呼吸点が無くなる場所には打てません。"),
                        tr("ただし、その手で相手の石を取れるなら打てます。"),
                        tr("コウ: 取り返すと同じ形がくり返す場所は、すぐには打ち返せません。"),
                    ],
                    figure: { AnyView(SuicideFigure()) }
                ),
                OnboardingPage(
                    heading: tr("パスと勝ち負け"),
                    lines: [
                        tr("打つところが無くなったら「パス」。両者が続けてパスすると終局です。"),
                        tr("白にはコミ 6.5 目が加算されます（置き石の対局は別の数え方です）。"),
                    ],
                    figure: { AnyView(ScoreFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 黒は ✕ に打てない（呼吸点が無くなる）。
    private struct SuicideFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 5, cols: 5, cell: 22, style: .lines) { row, col in
                    ZStack {
                        if Array(GoOnboarding.suicideDiagram[row])[col] == "O" { RuleStone(.white, size: 22) }
                        if row == 2, col == 2 { RuleBoardMark.cross() }
                    }
                }
                RuleFigureLabel(tr("黒は ✕ に打てない"), color: Theme.coralText)
            }
        }
    }

    /// 終局の数え方: 石 ＋ 地。白はコミが足される。
    private struct ScoreFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    tally(.black, tr("黒 %lld", GoOnboarding.exampleBlackArea))
                    tally(.white, tr("白 %lld ＋ コミ 6.5", GoOnboarding.exampleWhiteArea))
                }
                RuleFigureLabel(tr("白はコミを足して 46.5。白の勝ち"), color: Theme.coralText)
            }
        }

        private func tally(_ tone: RuleStone.Tone, _ label: String) -> some View {
            VStack(spacing: 4) {
                RuleStone(tone, size: 34)
                RuleFigureLabel(label)
            }
        }
    }
}
