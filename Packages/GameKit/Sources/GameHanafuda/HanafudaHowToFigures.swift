import Core
import SwiftUI

/// 図入りの遊び方（#2044）の花札こいこいの図。文言は `HowToPlayGuide.hanafuda.items`（Core）と同じ順。
/// 札は本番と同じ `HanafudaCardFace`（#2188 の札の画像＋月と種別の帯）。
@MainActor
enum HanafudaHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(MonthFigure()) },
        { AnyView(MatchFigure()) },
        { AnyView(DrawFigure()) },
        { AnyView(YakuFigure()) },
    ]

    private static let cardWidth: CGFloat = 40

    static func card(_ id: Int, width: CGFloat = cardWidth, highlighted: Bool = false, dimmed: Bool = false) -> some View {
        // 幅をここで決め打ちで渡す（`fixedWidth`）。盤面と違ってここは幅があらかじめ分かっているので、
        // `HanafudaCardFace` 内の `GeometryReader` を経由させない（#2905。「はじめての遊び方」の
        // `TabView` でページをめくるたびに GeometryReader を持つ札を何枚も再計測するのが重く、
        // 花札こいこいで画面が固まってクラッシュしていた）。
        HanafudaCardFace(card: HanafudaCard(id: id), isDimmed: dimmed, isHighlighted: highlighted, fixedWidth: width)
    }

    /// 札の裏（山札）。図のための簡素な裏面。
    struct CardBack: View {
        var body: some View {
            RoundedRectangle(cornerRadius: HanafudaHowToFigures.cardWidth * 0.12, style: .continuous)
                .fill(Color(hex: 0x3A2E27))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall / 3, style: .continuous)
                        .strokeBorder(Color(hex: 0xB33A3A), lineWidth: 2)
                        .padding(4)
                )
                .frame(width: HanafudaHowToFigures.cardWidth,
                       height: HanafudaHowToFigures.cardWidth * HanafudaCardArt.aspectRatio)
        }
    }

    /// 同じ月（1 月・松）の 4 枚。左上の数字が月。
    struct MonthFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { id in
                            HanafudaHowToFigures.card(id, width: 44)
                        }
                    }
                    RuleFigureLabel(tr("1 月（松）の 4 枚"))
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach([8, 10], id: \.self) { id in
                            HanafudaHowToFigures.card(id, width: 44)
                        }
                    }
                    RuleFigureLabel(tr("3 月（桜）"))
                }
            }
        }
    }

    /// 手札の松に鶴を選ぶと、場の松のカスと合わせて取れる。
    struct MatchFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                if index == 0 {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 4) {
                            HanafudaHowToFigures.card(0, highlighted: true)
                            RuleFigureLabel(tr("手札"), color: Theme.coralText)
                        }
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                HanafudaHowToFigures.card(2, highlighted: true)
                                HanafudaHowToFigures.card(9, dimmed: true)
                                HanafudaHowToFigures.card(21, dimmed: true)
                            }
                            RuleFigureLabel(tr("場"))
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: -12) {
                            HanafudaHowToFigures.card(0)
                            HanafudaHowToFigures.card(2)
                        }
                        RuleFigureLabel(tr("同じ月を取る"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 山札から 1 枚めくり、場の同じ月の札と合わせる。
    struct DrawFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                if index == 0 {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            ZStack {
                                CardBack().offset(x: 3, y: 3)
                                CardBack()
                            }
                            HanafudaHowToFigures.card(8, highlighted: true)
                        }
                        RuleFigureLabel(tr("山札から 1 枚めくる"))
                    }
                } else {
                    VStack(spacing: 4) {
                        HStack(spacing: -12) {
                            HanafudaHowToFigures.card(8)
                            HanafudaHowToFigures.card(10)
                        }
                        RuleFigureLabel(tr("場の同じ月と合わさる"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 役（猪鹿蝶）ができたら、あがり か こいこい。
    struct YakuFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach([24, 36, 20], id: \.self) { id in
                            HanafudaHowToFigures.card(id)
                        }
                    }
                    RuleFigureLabel(tr("役ができた！（猪鹿蝶）"), color: Theme.coralText)
                }
                HStack(spacing: 10) {
                    choice(tr("あがり"), detail: tr("得点する"), fill: Theme.Fill.coral)
                    choice(tr("こいこい"), detail: tr("続けて伸ばす"), fill: Theme.Fill.purple)
                }
            }
        }

        private func choice(_ title: String, detail: String, fill: Color) -> some View {
            VStack(spacing: 3) {
                Text(title)
                    .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(fill))
                RuleFigureLabel(detail)
            }
        }
    }
}
