import Core
import SwiftUI

/// 図入りの遊び方（#2044）のサイコロ役づくりの図。文言は `HowToPlayGuide.diceCombo.items`（Core）と同じ順。
/// サイコロと得点表の行は本番と同じ `DiceComboDieFace` / `DiceComboScoreRow`。
@MainActor
enum DiceComboHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(RollFigure()) },
        { AnyView(HoldFigure()) },
        { AnyView(ChooseFigure()) },
        { AnyView(CombosFigure()) },
        { AnyView(BonusFigure()) },
    ]

    private static let side: CGFloat = 30

    /// 出目を 1 列に並べる。`held` の添字に枠を付ける。
    private struct Dice: View {
        let values: [Int]
        var held: Set<Int> = []
        var side: CGFloat = DiceComboHowToFigures.side
        var body: some View {
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    DiceComboDieFace(value: value, isHeld: held.contains(index))
                        .frame(width: side, height: side)
                }
            }
        }
    }

    /// 「振る」で 5 個を振る。1 ターン 3 回まで。
    private struct RollFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                Dice(values: [3, 6, 2, 6, 5])
                HStack(spacing: 6) {
                    Label(tr("振る"), systemImage: "dice.fill")
                        .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Fill.coral))
                    RuleFigureLabel(tr("3回まで"), color: Theme.coral)
                }
            }
        }
    }

    /// 6 を 2 個キープ → 振り直すとキープした目は残る。
    private struct HoldFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Dice(values: index == 0 ? [3, 6, 2, 6, 5] : [6, 6, 1, 6, 4],
                         held: index == 0 ? [1, 3] : [], side: 22)
                }
                RuleFigureLabel(tr("キープした目は残る"), color: Theme.coral)
            }
        }
    }

    /// 得点表の役をタップして点を入れる（入れられる点が差し色で出る）。
    private struct ChooseFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Dice(values: [6, 6, 6, 3, 3], side: 24)
                VStack(spacing: 3) {
                    DiceComboScoreRow(name: tr("フルハウス"), rule: tr("3個と2個で5個の合計"), scored: nil, preview: 24)
                    DiceComboScoreRow(name: tr("Sストレート"), rule: tr("4つ続きで15点"), scored: nil, preview: 0)
                }
                .frame(width: 210)
            }
        }
    }

    /// 役の例: ストレートとファイブダイス。
    private struct CombosFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                example(values: [2, 3, 4, 5, 6], name: tr("Bストレート"), points: DiceComboLogic.bigStraightScore)
                example(values: [4, 4, 4, 4, 4], name: tr("ファイブダイス"), points: DiceComboLogic.fiveDiceScore)
            }
        }

        private func example(values: [Int], name: String, points: Int) -> some View {
            HStack(spacing: 8) {
                Dice(values: values, side: 22)
                Text(verbatim: "→")
                    .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSub)
                RuleFigureLabel(tr("%1$@ %2$lld点", name, points), color: Theme.coral)
            }
        }
    }

    /// 1〜6 の目の小計が 63 点以上でボーナス。
    private struct BonusFigure: View {
        var body: some View {
            HStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(verbatim: "63+")
                        .scaledFont(20, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.ink)
                    RuleFigureLabel(tr("1〜6の目の小計"))
                }
                Text(verbatim: "→")
                    .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSub)
                Text(verbatim: "+\(DiceComboLogic.upperBonus)")
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
            }
        }
    }
}
