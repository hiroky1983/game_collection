import Core
import SwiftUI

/// 図入りの遊び方（#2386）のいろリレーの図。文言は `HowToPlayGuide.colorRelay.items`（Core）と同じ順。
/// 札は本番と同じ `ColorRelayCardView` を小さく使う。
@MainActor
enum ColorRelayHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(MatchFigure()) },
        { AnyView(DrawFigure()) },
        { AnyView(SkipReverseFigure()) },
        { AnyView(DrawTwoFigure()) },
        { AnyView(WildFigure()) },
        { AnyView(WinFigure()) },
    ]

    private static let cardWidth: CGFloat = 40

    private static func card(_ id: Int, _ color: RelayColor?, _ kind: RelayKind,
                             hint: RelayCardHint = .none) -> some View {
        ColorRelayCardView(card: RelayCard(id: id, color: color, kind: kind), width: cardWidth, hint: hint)
    }

    /// 場の赤の 5 に、同じ色（赤の 8）と同じ数字（緑の 5）は出せる。色も数字も違う札は出せない。
    private struct MatchFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ColorRelayHowToFigures.card(1, .red, .number(5))
                    RuleFigureLabel(tr("場の札"))
                }
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        ColorRelayHowToFigures.card(2, .red, .number(8))
                        ColorRelayHowToFigures.card(3, .green, .number(5))
                        ColorRelayHowToFigures.card(4, .purple, .number(8), hint: .unplayable)
                    }
                    HStack(spacing: 6) {
                        RuleVerdictMark(true).frame(width: cardWidth)
                        RuleVerdictMark(true).frame(width: cardWidth)
                        RuleVerdictMark(false).frame(width: cardWidth)
                    }
                    RuleFigureLabel(tr("同じ色か同じ数字"))
                }
            }
        }
    }

    /// 山から 1 枚引く。
    private struct DrawFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        FourColorMark(size: 30)
                            .frame(width: cardWidth, height: ColorRelayCardSize(width: cardWidth).height)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Color.white))
                        RuleFigureLabel(tr("山から1枚"))
                    } else {
                        ColorRelayHowToFigures.card(5, .yellow, .number(3), hint: .playable)
                        RuleFigureLabel(tr("出せるならそのまま"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// とばし（次の人の番を飛ばす）とぎゃく（向きが逆）。
    private struct SkipReverseFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 4) {
                    ColorRelayHowToFigures.card(6, .green, .skip)
                    RuleFigureLabel(tr("次の人の番を飛ばす"))
                }
                VStack(spacing: 4) {
                    ColorRelayHowToFigures.card(7, .purple, .reverse)
                    RuleFigureLabel(tr("向きが逆になる"))
                }
            }
        }
    }

    /// +2 を出されると、次の人は 2 枚引く。
    private struct DrawTwoFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        ColorRelayHowToFigures.card(8, .yellow, .drawTwo)
                        RuleFigureLabel(tr("+2を出す"))
                    } else {
                        HStack(spacing: -cardWidth * 0.55) {
                            FourColorMark(size: 28)
                                .frame(width: cardWidth, height: ColorRelayCardSize(width: cardWidth).height)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Color.white))
                            FourColorMark(size: 28)
                                .frame(width: cardWidth, height: ColorRelayCardSize(width: cardWidth).height)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Color.white))
                        }
                        RuleFigureLabel(tr("次の人が2枚引く"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// いろがえ・いろがえ+4。どの札の上にも出せて、次の色を選べる。
    private struct WildFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 4) {
                    ColorRelayHowToFigures.card(9, nil, .wild)
                    RuleFigureLabel(tr("いろがえ"))
                }
                VStack(spacing: 4) {
                    ColorRelayHowToFigures.card(10, nil, .wildDrawFour)
                    RuleFigureLabel(tr("いろがえ+4"))
                }
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(RelayColor.allCases, id: \.self) { color in
                            Circle().fill(color.color).frame(width: 16, height: 16)
                        }
                    }
                    .frame(height: ColorRelayCardSize(width: cardWidth).height - 14)
                    RuleFigureLabel(tr("次の色を選ぶ"), color: Theme.coralText)
                }
            }
        }
    }

    /// 手札がなくなったら勝ち。
    private struct WinFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniSlot()
                RuleFigureLabel(tr("手札0枚でゴール"), color: Theme.coralText)
            }
        }
    }
}
