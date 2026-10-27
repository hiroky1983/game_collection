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

    // 図の出目（「はじめての遊び方」#2826 と共用。`DiceComboOnboardingTests` が `DiceComboLogic` に通して確かめる）。
    /// 振った目。
    static let rolled = [3, 6, 2, 6, 5]
    /// キープする目の位置（6 を 2 個）。
    static let keptIndices: Set<Int> = [1, 3]
    /// キープして振り直したあとの目（キープした位置は同じ目のまま）。
    static let rerolled = [6, 6, 1, 6, 4]
    /// 得点表の図の出目（フルハウス）。
    static let fullHouseDice = [6, 6, 6, 3, 3]
    /// 役の例の出目。
    static let bigStraightDice = [2, 3, 4, 5, 6]
    static let fiveDiceDice = [4, 4, 4, 4, 4]

    /// 出目を 1 列に並べる。`held` の添字に枠を付ける。
    struct Dice: View {
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
    struct RollFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                Dice(values: DiceComboHowToFigures.rolled)
                HStack(spacing: 6) {
                    Label(tr("振る"), systemImage: "dice.fill")
                        .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Fill.coral))
                    RuleFigureLabel(tr("3回まで"), color: Theme.coralText)
                }
            }
        }
    }

    /// 6 を 2 個キープ → 振り直すとキープした目は残る。
    struct HoldFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Dice(values: index == 0 ? DiceComboHowToFigures.rolled : DiceComboHowToFigures.rerolled,
                         held: index == 0 ? DiceComboHowToFigures.keptIndices : [], side: 22)
                }
                RuleFigureLabel(tr("キープした目は残る"), color: Theme.coralText)
            }
        }
    }

    /// 得点表の役をタップして点を入れる（入れられる点が差し色で出る）。
    struct ChooseFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                let dice = DiceComboHowToFigures.fullHouseDice
                Dice(values: dice, side: 24)
                VStack(spacing: 3) {
                    DiceComboScoreRow(name: tr("フルハウス"), rule: tr("3個と2個で5個の合計"), scored: nil,
                                      preview: DiceComboLogic.score(.fullHouse, dice: dice))
                    DiceComboScoreRow(name: tr("Sストレート"), rule: tr("4つ続きで15点"), scored: nil,
                                      preview: DiceComboLogic.score(.smallStraight, dice: dice))
                }
                .frame(width: 210)
            }
        }
    }

    /// 役の例: ストレートとファイブダイス。
    struct CombosFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                example(values: DiceComboHowToFigures.bigStraightDice, name: tr("Bストレート"), points: DiceComboLogic.bigStraightScore)
                example(values: DiceComboHowToFigures.fiveDiceDice, name: tr("ファイブダイス"), points: DiceComboLogic.fiveDiceScore)
            }
        }

        private func example(values: [Int], name: String, points: Int) -> some View {
            HStack(spacing: 8) {
                Dice(values: values, side: 22)
                Text(verbatim: "→")
                    .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                RuleFigureLabel(tr("%1$@ %2$lld点", name, points), color: Theme.coralText)
            }
        }
    }

    /// 1〜6 の目の小計が 63 点以上でボーナス。
    struct BonusFigure: View {
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
                    .foregroundStyle(Theme.inkSubText)
                Text(verbatim: "+\(DiceComboLogic.upperBonus)")
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
            }
        }
    }
}
