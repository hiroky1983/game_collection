import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のおじさんの荷物運びパズル。
///
/// 「？」の遊び方（`OjisanPuzzleMode.howToPlayGuide`）と同じく、遊んでいるモードで出し分ける。パズルモードには
/// 腰痛ゲージ・入院・クリアライン・せり上がりを出さない（会長指示 2026-10-12）。図は遊び方の図
/// （`OjisanPuzzleHowToFigures.swift`）の部品をそのまま使い、荷物とおじさんは本番の絵。操作の案内（#2810）はここでは扱わない。
/// れんさの図の盤・消え方・点数（`ChainFigure.steps`）、操作・ゲージ・クリア・終わり方・続け方は
/// `OjisanPuzzleOnboardingTests` が `OjisanPuzzleBoard` / `OjisanPuzzleModel` に通して確かめる。
@MainActor
enum OjisanPuzzleOnboarding {
    static func guide(mode: OjisanPuzzleMode) -> OnboardingGuide {
        let goal: OnboardingPage = switch mode {
        case .backpain:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("荷物を 4 つそろえて消して、ラインより下まで片付けるゲームです。"),
                    tr("荷物は時間がたつと、下から 1 段ずつせり上がってきます。"),
                ],
                figure: { AnyView(GoalFigure(mode: .backpain)) }
            )
        case .puzzle:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("荷物を 4 つそろえて消して、得点をのばすゲームです。"),
                    tr("空の盤から始まり、ゲージはありません。"),
                ],
                figure: { AnyView(GoalFigure(mode: .puzzle)) }
            )
        }
        let controls = OnboardingPage(
            heading: tr("1 組でやること"),
            lines: [
                tr("2 つひと組の荷物が落ちてきます。"),
                tr("よこにスワイプで動かし、タップで回し、下にスワイプで落とします。"),
                tr("はさまれて回せないときは、もう 1 回タップで上下が入れかわります。"),
            ],
            figure: { AnyView(ControlsFigure()) }
        )
        let chain = OnboardingPage(
            heading: tr("4 つつながると消える"),
            lines: [
                tr("同じ荷物がたて・よこに 4 つ以上つながると消えます。"),
                tr("消えたあとに落ちてきた荷物がまたつながれば「れんさ」。れんさするほど点が増えます。"),
            ],
            figure: { AnyView(ChainFigure()) }
        )
        let pages: [OnboardingPage] = switch mode {
        case .backpain:
            [
                goal, controls, chain,
                OnboardingPage(
                    heading: tr("腰痛ゲージ"),
                    lines: [
                        tr("荷物は 5 種類。重い荷物をかかえるほど腰にきて、消すと楽になります。"),
                        tr("腰にくるほど落ちるのが速くなり、操作が遅れます。"),
                    ],
                    figure: { AnyView(GaugeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("ラインより下まで片付けたらクリア。早いほど良い記録です。"),
                        tr("ゲージが満タンで入院か、▼の列のいちばん上が埋まったら負けです。"),
                        tr("負けたときは、広告を見て 1 回だけ続けられます。"),
                    ],
                    figure: { AnyView(EndFigure(mode: .backpain)) }
                ),
            ]
        case .puzzle:
            [
                goal, controls, chain,
                OnboardingPage(
                    heading: tr("だんだん速くなる"),
                    lines: [
                        tr("荷物は 5 種類。同じ種類どうしだけがつながります。"),
                        tr("荷物を置くほど、少しずつ落ちるのが速くなります。"),
                    ],
                    figure: { AnyView(WeightFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("▼の列のいちばん上が埋まったら終わり。それまでの得点が記録です。"),
                        tr("埋まったときは、広告を見て 1 回だけ続けられます。"),
                    ],
                    figure: { AnyView(EndFigure(mode: .puzzle)) }
                ),
            ]
        }
        return OnboardingGuide(gameID: "ojisanpuzzle", title: tr("荷物運びパズルのはじめての遊び方"), pages: pages)
    }
}
