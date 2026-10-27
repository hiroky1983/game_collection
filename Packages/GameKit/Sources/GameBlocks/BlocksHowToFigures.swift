import Core
import SwiftUI

/// 図入りの遊び方（#2044）のブロック崩しの図。文言は `HowToPlayGuide.blocks.items`（Core）と同じ順。
/// パドル・球・ブロックは図形で描く。
@MainActor
enum BlocksHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PaddleFigure()) },
        { AnyView(BounceFigure()) },
        { AnyView(ItemFigure()) },
        { AnyView(StageFigure()) },
        { AnyView(MissFigure()) },
    ]

    private static let brickColors: [Color] = [Theme.Fill.coral, Theme.Fill.yellow, Theme.Fill.teal, Theme.Fill.purple]

    private struct Paddle: View {
        var width: CGFloat = 54
        var body: some View {
            Capsule().fill(Theme.ink).frame(width: width, height: 9)
        }
    }

    private struct Ball: View {
        var body: some View {
            Circle().fill(Theme.coral).frame(width: 10, height: 10)
        }
    }

    struct Brick: View {
        let color: Color
        var body: some View {
            RoundedRectangle(cornerRadius: Theme.cornerSmall / 4, style: .continuous)
                .fill(color)
                .frame(width: 30, height: 12)
        }
    }

    /// 枠（盤）。
    private struct Field<Content: View>: View {
        let width: CGFloat
        let height: CGFloat
        @ViewBuilder let content: () -> Content
        var body: some View {
            ZStack { content() }
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                    .fill(Theme.inkSub.opacity(0.1)))
        }
    }

    /// 指を横に動かすとパドルが動き、タップで球が出る。
    struct PaddleFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                VStack(spacing: 6) {
                    Paddle()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Image(systemName: "hand.point.up.left.fill")
                            .scaledFont(20, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(Theme.coralText)
                        Image(systemName: "arrow.right")
                    }
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                    RuleFigureLabel(tr("指を横に動かす"))
                }
                VStack(spacing: 6) {
                    Ball()
                    Paddle()
                    Image(systemName: "hand.tap.fill")
                        .scaledFont(20, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("タップで発射"))
                }
            }
        }
    }

    /// 球をはね返してブロックに当てる。灰色は壊れない。
    struct BounceFigure: View {
        var body: some View {
            Field(width: 200, height: 110) {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            Brick(color: i == 1 ? Color(hex: 0x9E9E9E) : BlocksHowToFigures.brickColors[i])
                        }
                    }
                    Spacer()
                }
                .padding(.top, 10)
                Path { p in
                    p.move(to: CGPoint(x: 100, y: 92))
                    p.addLine(to: CGPoint(x: 140, y: 30))
                }
                .stroke(Theme.coral, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                VStack {
                    Spacer()
                    Paddle()
                }
                .padding(.bottom, 6)
                Ball().position(x: 120, y: 60)
                Text(tr("壊れない"))
                    .scaledFont(10, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                    .position(x: 84, y: 36)
            }
        }
    }

    /// 落ちてくるアイテムを受けると、パドルが伸びたり球が増えたり。
    struct ItemFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 6) {
                    if index == 0 {
                        Image(systemName: "capsule.fill")
                            .scaledFont(14, maxScale: 1.15)
                            .foregroundStyle(Theme.Fill.teal)
                        Image(systemName: "arrow.down")
                            .scaledFont(11, weight: .black, maxScale: 1.2)
                            .foregroundStyle(Theme.inkSubText)
                        Paddle()
                    } else {
                        HStack(spacing: 6) { Ball(); Ball(); Ball() }
                        Paddle(width: 84)
                    }
                    RuleFigureLabel(index == 0 ? tr("アイテムを受ける") : tr("伸びる・球が増える"),
                                    color: index == 1 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 壊せるブロックを全部消すと次のステージ。
    private struct StageFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    Field(width: 100, height: 46) {
                        HStack(spacing: 3) {
                            Brick(color: Color(hex: 0x9E9E9E))
                            if index == 0 { Brick(color: Theme.Fill.coral) } else { Color.clear.frame(width: 30, height: 12) }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("あと 1 つ") : tr("次のステージへ"),
                                    color: index == 1 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 球を全部落とすと 1 ミス、3 回で終わり。
    struct MissFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    Field(width: 80, height: 60) {
                        VStack(spacing: 4) {
                            Spacer()
                            Paddle(width: 40)
                            Ball().offset(x: 24)
                        }
                        .padding(.bottom, 2)
                    }
                    RuleFigureLabel(tr("球を落とすと 1 ミス"))
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "xmark.circle.fill")
                                .scaledFont(18, weight: .bold, maxScale: 1.15)
                                .foregroundStyle(Theme.coralText)
                        }
                    }
                    RuleFigureLabel(tr("3 回で終わり"), color: Theme.coralText)
                }
            }
        }
    }
}
