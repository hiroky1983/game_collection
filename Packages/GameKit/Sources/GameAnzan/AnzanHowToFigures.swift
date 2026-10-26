import Core
import SwiftUI

/// 図入りの遊び方（#2044）のぱっと暗算の図。文言は `HowToPlayGuide.anzan.items`（Core）と同じ順。
@MainActor
enum AnzanHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(FlashFigure()) },
        { AnyView(SumFigure()) },
        { AnyView(AnswerFigure()) },
        { AnyView(LevelFigure()) },
    ]

    /// 図に出す数（3 → 7 → 5、合計 15）。図で見る「はじめての遊び方」（#2826）も使う。
    static let numbers = [3, 7, 5]

    /// 数を出す画面（四角の中に 1 つの数）。
    private struct Flash: View {
        let text: String
        var dimmed = false
        var body: some View {
            Text(verbatim: text)
                .scaledFont(26, weight: .black, design: .rounded, maxScale: 1.15)
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .stroke(Theme.inkSub.opacity(0.3), lineWidth: 1))
                .opacity(dimmed ? 0.4 : 1)
        }
    }

    /// 3 → 7 → 5 と 1 つずつ出ては消える。
    struct FlashFigure: View {
        var body: some View {
            RuleFrames(count: 3, spacing: 8) { index in
                Flash(text: "\(AnzanHowToFigures.numbers[index])")
            }
        }
    }

    /// 頭の中で足す: 3 + 7 + 5 = 15。
    struct SumFigure: View {
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .scaledFont(26, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
                Text(verbatim: AnzanLogic.expression(AnzanHowToFigures.numbers))
                    .scaledFont(20, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    /// テンキーで 15 と入れて「決定」。
    struct AnswerFigure: View {
        var body: some View {
            HStack(spacing: 12) {
                Text(verbatim: "15")
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 70, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                        .strokeBorder(Theme.coral, lineWidth: 2))
                VStack(spacing: 3) {
                    ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]], id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(row, id: \.self) { n in
                                Text(verbatim: "\(n)")
                                    .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.15)
                                    .foregroundStyle(n == 1 || n == 5 ? Theme.onAccent : Theme.ink)
                                    .frame(width: 22, height: 18)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 3, style: .continuous)
                                        .fill(n == 1 || n == 5 ? Theme.Fill.coral : Theme.inkSub.opacity(0.15)))
                            }
                        }
                    }
                }
                Text(tr("決定"))
                    .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
    }

    /// 桁数・個数・速さを選べる。
    struct LevelFigure: View {
        var body: some View {
            HStack(spacing: 8) {
                chip(tr("桁数"), "1")
                chip(tr("個数"), "5")
                chip(tr("速さ"), "hare.fill")
            }
        }

        private func chip(_ name: String, _ value: String) -> some View {
            VStack(spacing: 3) {
                Group {
                    if value.count > 2 {
                        Image(systemName: value)
                    } else {
                        Text(verbatim: value)
                    }
                }
                .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                .foregroundStyle(Theme.coralText)
                .frame(width: 60, height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                    .fill(Theme.coral.opacity(0.12)))
                RuleFigureLabel(name)
            }
        }
    }
}
