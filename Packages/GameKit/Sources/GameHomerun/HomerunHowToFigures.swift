import Core
import SwiftUI

/// 図入りの遊び方（#2044）の柵越えおじさんの図。文言は `HowToPlayGuide.homerun.items`（Core）と同じ順。
/// ねらう・振るの図は打席の「操作の説明」（#1763）と同じ部品（`HomerunTutorialFigure`）を使い、
/// 残りは図形と SF Symbols で描く。
@MainActor
enum HomerunHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(TenBallsFigure()) },
        { AnyView(TutorialFigure(kind: .aim)) },
        { AnyView(TutorialFigure(kind: .swing)) },
        { AnyView(LaunchFigure()) },
        { AnyView(DailyFigure()) },
    ]

    /// 1 回の挑戦は 10 球、合計飛距離で記録。
    struct TenBallsFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { _ in
                        Image(systemName: "baseball.fill")
                            .scaledFont(18, maxScale: 1.15)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "sum")
                        .scaledFont(13, weight: .black, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("10 球の合計飛距離が記録"), color: Theme.coralText)
                }
            }
        }
    }

    /// 打席の「操作の説明」と同じ図解（指の動きのループ。Reduce Motion では止め絵）。
    struct TutorialFigure: View {
        let kind: HomerunTutorialFigure.Kind

        var body: some View {
            let width: CGFloat = 200
            HomerunTutorialFigure(kind: kind)
                .frame(width: width, height: width / HomerunTutorialFigure.aspect)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .stroke(Theme.inkSub.opacity(0.25), lineWidth: 1))
        }
    }

    /// カーソルをボールの少し下に置くと打球が上がる。
    struct LaunchFigure: View {
        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color(hex: 0xC0392B).opacity(0.7), lineWidth: 1.5).padding(4))
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    Circle()
                        .stroke(Theme.teal, lineWidth: 3)
                        .frame(width: 36, height: 36)
                        .offset(y: 12)
                }
                .frame(width: 60, height: 64)
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .scaledFont(28, weight: .black, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("少し下で打つと上がる"), color: Theme.coralText)
                }
            }
        }
    }

    /// 1 日 3 回。打席に立つと 1 回減り、0:00 に戻る。
    struct DailyFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 6) {
                    HomerunHeroCountDots(allowance: 3, remaining: index == 0 ? 2 : 3, size: 18)
                    RuleFigureLabel(index == 0 ? tr("打席に立つと 1 回減る") : tr("0:00 に 3 回に戻る"),
                                    color: index == 1 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }
}
