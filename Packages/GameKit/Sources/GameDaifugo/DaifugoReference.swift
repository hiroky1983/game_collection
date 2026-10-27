import Core
import CoreMiniCard
import SwiftUI

/// 対局中に開ける早見表（#2788）の中身のうち、**ルールの値から作るもの**。
///
/// 強さの順・革命の枚数は `DaifugoRules` から引く。ルールを変えたら表も変わり、食い違いは
/// `DaifugoReferenceTests` が検出する。
enum DaifugoReference {
    /// 札の数字（`DaifugoCard.rank`。ジョーカーは `jokerRank`）を図用の札の表記にする。
    static func rankLabel(_ rank: Int) -> String {
        switch rank {
        case DaifugoRules.jokerRank: return "JK"
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// 弱い順に並べた数字（ジョーカー込み）。革命中は 3 が最強・2 が最弱に逆転し、ジョーカーだけ最強のまま。
    static func strengthOrder(isRevolution: Bool) -> [Int] {
        let ranks = [DaifugoRules.jokerRank] + Array(1...13)
        return ranks.sorted {
            DaifugoRules.strength(rank: $0, isRevolution: isRevolution)
                < DaifugoRules.strength(rank: $1, isRevolution: isRevolution)
        }
    }

    /// 早見表に「しばり」の段を出すか。ローカルルールの選択（#2605・#2721）で表が変わる入口。
    static func showsBind(_ ruleSet: DaifugoRuleSet) -> Bool { ruleSet.isBindEnabled }
}

// MARK: - 早見表のシート

/// 大富豪の早見表（#2788）。ヘッダーの丸ボタンから開く（ポーカーの点数表と同じ置き場・同じ枠）。
/// `ruleSet` は今の局のローカルルール。選んだルールに合わせて段が変わる。
struct DaifugoReferenceSheet: View {
    let ruleSet: DaifugoRuleSet

    var body: some View {
        YakuTableSheet(title: tr("大富豪の早見表")) {
            YakuTableSection(header: tr("カードの強さ")) {
                strengthRow(title: tr("ふだん"), isRevolution: false)
                strengthRow(title: tr("革命中（逆になる）"), isRevolution: true)
                Text(tr("ジョーカーは、革命中も最強です。"))
                    .themeCaption(12, weight: .medium)
                    .foregroundStyle(Theme.inkSubText)
            }
            YakuTableSection(header: tr("革命・8切り")) {
                ruleRow(tr("同じ数字を %lld 枚以上まとめて出すと革命。強さが逆になります（もう一度出すと元に戻ります）。",
                           DaifugoRules.revolutionCount))
                ruleRow(tr("8 を含む組を出すと場が流れ、そのまま続けて出せます。"))
            }
            if DaifugoReference.showsBind(ruleSet) {
                YakuTableSection(header: tr("しばり")) {
                    ruleRow(tr("同じスートが 2 回続くと、場が流れるまでそのスートの札（とジョーカー）しか出せません。"))
                }
            }
            YakuTableSection(header: tr("反則上がり")) {
                HStack(spacing: 10) {
                    RuleMiniCardRow(overlap: 10) {
                        RuleMiniCard("2", suit: .spade, isHighlighted: true)
                        RuleMiniCard("8", suit: .heart, isHighlighted: true)
                        RuleMiniCard("JK", isHighlighted: true)
                    }
                    Image(systemName: "arrow.right")
                        .scaledFont(14, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("最後の 1 手だと大貧民"), color: Theme.coralText)
                }
                .frame(maxWidth: .infinity)
                ruleRow(tr("最後の 1 手が 2・8・ジョーカーだと反則。上がっても大貧民に落ちます。"))
            }
        }
    }

    private func strengthRow(title: String, isRevolution: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .themeBody(13, weight: .black)
                .foregroundStyle(Theme.ink)
            let order = DaifugoReference.strengthOrder(isRevolution: isRevolution)
            RuleMiniCardWrap(count: order.count, perRow: 7) { index in
                RuleMiniCard(DaifugoReference.rankLabel(order[index]),
                             suit: order[index] == DaifugoRules.jokerRank ? nil : .spade)
            }
            .frame(maxWidth: .infinity)
            RuleFigureLabel(tr("左上がいちばん弱く、右下がいちばん強い"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + " " + DaifugoReference.strengthOrder(isRevolution: isRevolution)
            .map(DaifugoReference.rankLabel).joined(separator: " "))
    }

    private func ruleRow(_ text: String) -> some View {
        Label {
            Text(text)
                .themeBody(13, weight: .medium)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.fill")
                .scaledFont(5, maxScale: 1.15)
                .foregroundStyle(Theme.inkSubText)
        }
    }
}
