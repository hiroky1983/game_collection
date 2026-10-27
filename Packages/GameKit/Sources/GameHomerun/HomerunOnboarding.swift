import Core
import HomerunCore
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）の柵越えおじさん。
///
/// 図は遊び方の図（`HomerunHowToFigures`）の 2D の部品を使い回す（打席の 3D は図に使わない）。ねらう・振るの図は
/// 打席の「操作の説明」と同じ `HomerunTutorialFigure`。記録の図の 3 球は `HomerunSwing` の定数（`homerSwing` など）で持ち、
/// 画面は `HomerunJudge.judge` に通した結果（種別の語・飛距離）を描く。`HomerunOnboardingTests` が同じ定数を
/// `HomerunJudge` / `HomerunChallenge` に通し、回数の文言は `HomerunLedger` の定数・振る舞いと合っていることを確かめる。
/// 月まで飛ぶ・ポール直撃などの隠し演出は書かない。
@MainActor
enum HomerunOnboarding {
    /// 記録の図の「柵越え」の 1 球（ジャストに近いタイミングで、ボールの少し下を打つ）。
    static let homerSwing = HomerunSwing(timingOffset: 10, cursorDX: 0, cursorDY: 6)
    /// 記録の図の「ファウル」の 1 球（右へ寄せすぎ・振るのも遅い）。
    static let foulSwing = HomerunSwing(timingOffset: 100, cursorDX: 11, cursorDY: 4)
    /// 記録の図の「空振り」の 1 球（振るのが早すぎる）。
    static let missSwing = HomerunSwing(timingOffset: -200, cursorDX: 0, cursorDY: 6)

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "homerun",
            title: tr("柵越えおじさんのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("飛んでくる球を、10 球打つゲームです。"),
                        tr("10 球の合計飛距離を伸ばしましょう。"),
                    ],
                    figure: { AnyView(HomerunHowToFigures.TenBallsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 球でやること"),
                    lines: [
                        tr("画面の下のほうを押したままずらすと、水色のミートカーソルが動きます。"),
                        tr("カーソルをボールに合わせます。"),
                    ],
                    figure: { AnyView(HomerunHowToFigures.TutorialFigure(kind: .aim)) }
                ),
                OnboardingPage(
                    heading: tr("指を離して打つ"),
                    lines: [
                        tr("縮む輪が白い的に重なった瞬間に指を離すと、スイングします。"),
                        tr("ぴったりなほど遠くへ飛びます。早すぎ・遅すぎは空振りです。"),
                    ],
                    figure: { AnyView(HomerunHowToFigures.TutorialFigure(kind: .swing)) }
                ),
                OnboardingPage(
                    heading: tr("打球の角度と方向"),
                    lines: [
                        tr("カーソルをボールの少し下に置くと、打球が上がります。"),
                        tr("カーソルの左右と離す早さで、打球の方向が決まります。"),
                        tr("左右に寄せすぎるとファウルです。"),
                    ],
                    figure: { AnyView(HomerunHowToFigures.LaunchFigure()) }
                ),
                OnboardingPage(
                    heading: tr("挑戦は 1 日 3 回"),
                    lines: [
                        tr("打席に立った時点で 1 回減り、0:00 に戻ります。"),
                        tr("回数が 0 のときは、広告を見て 1 回遊べます（1 日の本数に上限があります）。"),
                    ],
                    figure: { AnyView(HomerunHowToFigures.DailyFigure()) }
                ),
                OnboardingPage(
                    heading: tr("記録の決まり"),
                    lines: [
                        tr("10 球の合計飛距離が、その挑戦の記録です。"),
                        tr("空振り・見送り・ファウルは 0 m。柵越えを重ねて自己ベストを目指そう。"),
                    ],
                    figure: { AnyView(ResultFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 柵越え・ファウル・空振りの 1 球ずつの飛距離（判定に通した値）。
    private struct ResultFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    ForEach(Array([HomerunOnboarding.homerSwing, HomerunOnboarding.foulSwing, HomerunOnboarding.missSwing]
                        .enumerated()), id: \.offset) { _, swing in
                        row(HomerunJudge.judge(swing))
                    }
                }
                .frame(width: 190)
                RuleFigureLabel(tr("空振り・ファウルは 0 m"), color: Theme.coralText)
            }
        }

        private func row(_ ball: HomerunBattedBall) -> some View {
            let isHomer = ball.kind == .homer
            return HStack(spacing: 8) {
                Image(systemName: isHomer ? "star.fill" : "baseball.fill")
                    .scaledFont(14, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(isHomer ? Theme.coralText : Theme.inkSubText)
                Text(HomerunText.kind(ball.kind))
                    .scaledFont(15, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(isHomer ? Theme.coralText : Theme.ink)
                Spacer(minLength: 8)
                Text(verbatim: HomerunText.meters(ball.distance))
                    .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                    .foregroundStyle(isHomer ? Theme.coralText : Theme.inkSubText)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .fill(isHomer ? Theme.coral.opacity(0.12) : Theme.inkSub.opacity(0.06)))
        }
    }
}
