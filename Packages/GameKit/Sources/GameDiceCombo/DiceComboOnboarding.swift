import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のサイコロ役づくり。
///
/// サイコロと得点表の行は本番と同じ `DiceComboDieFace` / `DiceComboScoreRow`。振る・キープ・記入・役・ボーナスの図は
/// 遊び方の図（`DiceComboHowToFigures`）の部品を使い回す。図の出目は `DiceComboHowToFigures` の定数、終わりの図の
/// 得点表は `finishedScores` で持ち、`DiceComboOnboardingTests` が `DiceComboLogic` と `DiceComboModel` に通して
/// 図のとおりになることを確かめる。
@MainActor
enum DiceComboOnboarding {
    /// 終わりの図の得点表（12 役ぜんぶ埋まった局。1〜6 の目の小計がちょうど 63 点でボーナスが付く）。
    static let finishedScores: [DiceComboCategory: Int] = [
        .ones: 3, .twos: 6, .threes: 9, .fours: 12, .fives: 15, .sixes: 18,
        .choice: 24, .fourDice: 0, .fullHouse: 23, .smallStraight: 15, .bigStraight: 30, .fiveDice: 50,
    ]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "dicecombo",
            title: tr("サイコロ役づくりのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("サイコロ 5 個を振って、役をつくるゲームです。"),
                        tr("得点表の 12 の役に点を入れて、合計点を伸ばします。"),
                    ],
                    figure: { AnyView(DiceComboHowToFigures.CombosFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("「振る」でサイコロ 5 個を振ります。"),
                        tr("1 ターンに 3 回まで振れます。"),
                    ],
                    figure: { AnyView(DiceComboHowToFigures.RollFigure()) }
                ),
                OnboardingPage(
                    heading: tr("残したい目をキープ"),
                    lines: [
                        tr("残したい目をタップするとキープ。"),
                        tr("キープした目は、振り直しても変わりません。"),
                    ],
                    figure: { AnyView(DiceComboHowToFigures.HoldFigure()) }
                ),
                OnboardingPage(
                    heading: tr("役を選んで点を入れる"),
                    lines: [
                        tr("得点表の役を 1 つタップして点を入れると、ターン終了です。"),
                        tr("条件に合わない役に入れると 0 点です。"),
                    ],
                    figure: { AnyView(DiceComboHowToFigures.ChooseFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1〜6 の目のボーナス"),
                    lines: [
                        tr("1〜6 の目の役は、その目の合計が点になります。"),
                        tr("1〜6 の目の小計が 63 点以上なら、ボーナス +35 点。"),
                    ],
                    figure: { AnyView(DiceComboHowToFigures.BonusFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("12 の役をぜんぶ埋めたら終わりです。"),
                        tr("負けはありません。合計点で自己ベストを目指そう。"),
                    ],
                    figure: { AnyView(FinishFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 12 ターン目まで埋めたら、ボーナス込みの合計点で終わる。
    private struct FinishFigure: View {
        var body: some View {
            let count = DiceComboCategory.allCases.count
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    stat(tr("ターン"), "\(count) / \(count)", color: Theme.ink)
                    Text(verbatim: "→")
                        .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.inkSubText)
                    stat(tr("合計"), "\(DiceComboLogic.total(DiceComboOnboarding.finishedScores))", color: Theme.coralText)
                }
                RuleFigureLabel(tr("12 役を埋めたら終わり"), color: Theme.coralText)
            }
        }

        private func stat(_ title: String, _ value: String, color: Color) -> some View {
            VStack(spacing: 2) {
                Text(title)
                    .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                Text(verbatim: value)
                    .scaledFont(24, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                    .foregroundStyle(color)
            }
        }
    }
}
