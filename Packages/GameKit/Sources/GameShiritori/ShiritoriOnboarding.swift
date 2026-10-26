import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）のカードしりとり。
///
/// 遊び方（ノルマ／とことん）で先頭の目的と、取ったあとの説明が変わるので、「？」の遊び方と同じく `mode` を受けて組む。
/// ノルマの枚数・制限時間・「ん」の負け・勝ち負けは `ShiritoriQuota` / `ShiritoriTime` / `ShiritoriModel` の実装どおり
/// （`ShiritoriOnboardingTests` が確かめる）。裏読み・おてつき後の細かい扱いは書かない。図は遊び方の図
/// （`ShiritoriHowToFigures`）の部品を使い回し、札は本番の `ShiritoriCardTile`。
@MainActor
enum ShiritoriOnboarding {
    /// 「ん」で終わる読みの図の札の読み。
    static let nReading = "みかん"  // i18n-keep: しりとりの読み（言語を切り替えられない）

    static func guide(mode: ShiritoriMode) -> OnboardingGuide {
        let goal: OnboardingPage = switch mode {
        case .quota:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("取った札が、ノルマの枚数に届いたら勝ちです。"),
                    tr("ノルマは かんたん %1$lld 枚・ふつう %2$lld 枚・むずかしい %3$lld 枚です。",
                       ShiritoriQuota.easy.cardCount, ShiritoriQuota.normal.cardCount, ShiritoriQuota.hard.cardCount),
                ],
                figure: { AnyView(ShiritoriHowToFigures.QuotaFigure()) }
            )
        case .endless:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("ノルマは無く、札が尽きるまで続きます。"),
                    tr("全部の札を取りきると、パーフェクトで勝ちです。"),
                ],
                figure: { AnyView(ShiritoriHowToFigures.EndlessFigure()) }
            )
        }
        let turn = OnboardingPage(
            heading: tr("取ったあと"),
            lines: mode == .quota
                ? [
                    tr("取った札が、新しい場の札になります。"),
                    tr("そのあとは CPU の番です。CPU も同じように札を取ります。"),
                ]
                : [
                    tr("取った札が、新しい場の札になります。"),
                    tr("そのあとは CPU の番です。CPU も同じように札を取ります。"),
                    tr("札を取った場所には、山札から新しい札が出ます。"),
                ],
            figure: { AnyView(ShiritoriHowToFigures.TurnFigure()) }
        )
        return OnboardingGuide(
            gameID: "shiritori",
            title: tr("カードしりとりのはじめての遊び方"),
            pages: [
                goal,
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("場の札の読みの、最後の字から始まる札を選んで取ります。"),
                        tr("たとえば「りんご」の次は、「ご」で始まる「ごりら」です。"),
                    ],
                    figure: { AnyView(ShiritoriHowToFigures.ChainFigure()) }
                ),
                turn,
                OnboardingPage(
                    heading: tr("制限時間"),
                    lines: [
                        tr("制限時間は %lld 秒です。", Int(ShiritoriTime.initial)),
                        tr("しりとりが成立すると +%lld 秒。", Int(ShiritoriTime.successBonus)),
                        tr("合わない札を選ぶと -%lld 秒です。", Int(ShiritoriTime.missPenalty)),
                    ],
                    figure: { AnyView(ShiritoriHowToFigures.TimerFigure()) }
                ),
                OnboardingPage(
                    heading: tr("「ん」で終わる札"),
                    lines: [
                        tr("読みが「ん」で終わる札を取ると、その場で負けです。"),
                        tr("CPU が「ん」で終わる札を取ったときは、あなたの勝ちです。"),
                    ],
                    figure: { AnyView(NFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("CPU が続けられなくなったら、あなたの勝ちです。"),
                        tr("あなたが続けられなくなる・時間切れになると、負けです。"),
                    ],
                    figure: { AnyView(ShiritoriHowToFigures.WinLoseFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 「ん」で終わる読みの札は取ってはいけない。
    private struct NFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: ShiritoriOnboarding.nReading)
                        .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.coralText.opacity(0.12)))
                    RuleVerdictMark(false)
                }
                RuleFigureLabel(tr("「ん」で終わる読みは、その場で負け"), color: Theme.coralText)
            }
        }
    }
}
