import Core
import CoreMiniCard
import SwiftUI

/// 対局中に開ける早見表（#2788）の中身のうち、**ルールの値から作るもの**。
///
/// 表の数字を文字で書き写さず `HeartsRules` / `HeartsCard` から引く。ルールを変えたら表も変わり、
/// 食い違いは `HeartsReferenceTests` が検出する。
enum HeartsReference {
    /// 札の数字（`HeartsCard.rank` 2〜14）を図用の札の表記にする。
    static func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        default: return "\(rank)"
        }
    }

    /// 強い順（A → 2）に並べた数字。`trickWinner` が使う比べ方（同じスートの `rank` の大小）をそのまま使う。
    static var strengthOrder: [Int] {
        HeartsCard.makeDeck().filter { $0.suit == .club }.map(\.rank).sorted(by: >)
    }

    /// 点の一覧（札・点）。点になる札と、ならない札の代表を並べる。
    static var pointEntries: [(rank: Int, suit: HeartsSuit, points: Int)] {
        [
            (5, .heart, HeartsCard(.heart, 5).points),
            (HeartsCard.queenOfSpades.rank, HeartsCard.queenOfSpades.suit, HeartsCard.queenOfSpades.points),
            (13, .club, HeartsCard(.club, 13).points),
        ]
    }
}

extension RuleMiniCard.Suit {
    init(_ suit: HeartsSuit) {
        switch suit {
        case .club: self = .club
        case .diamond: self = .diamond
        case .spade: self = .spade
        case .heart: self = .heart
        }
    }
}

// MARK: - 早見表のシート

/// ハーツの早見表（#2788）。ヘッダーの丸ボタンから開く（ポーカーの点数表と同じ置き場・同じ枠）。
/// 文章より図と短い言葉で、「どの札が強いか」「誰が取るか」「何点か」の順に並べる。
struct HeartsReferenceSheet: View {
    var body: some View {
        YakuTableSheet(title: tr("ハーツの早見表")) {
            YakuTableSection(
                header: tr("札の強さ"),
                footer: tr("強さを比べるのは同じマークの中だけ。マークどうしに強い・弱いはありません。")
            ) {
                HeartsHowToFigures.StrengthFigure()
                    .frame(maxWidth: .infinity)
            }
            YakuTableSection(
                header: tr("誰が取る？"),
                footer: tr("別のマークの札は、A でも勝てません。切り札はありません。")
            ) {
                Text(tr("最初に出たマークと同じマークのうち、いちばん強い札を出した人が 4 枚を取ります。"))
                    .themeBody(13, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HeartsHowToFigures.TakeFigure()
                    .frame(maxWidth: .infinity)
            }
            YakuTableSection(
                header: tr("点数"),
                footer: tr("1 手で動く点は全部で %lld 点。だれかが %lld 点に届いたら終わりです。",
                           HeartsRules.pointsPerHand, HeartsRules.targetScore)
            ) {
                Text(tr("点が少ないほど勝ち。札を取らないようにするゲームです。"))
                    .themeBody(13, weight: .medium)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HeartsHowToFigures.PointsFigure()
                    .frame(maxWidth: .infinity)
            }
            YakuTableSection(header: tr("出せる札")) {
                ruleRow(tr("最初の 1 枚は、クラブの 2 を持っている人から。"))
                ruleRow(tr("同じマークがあれば必ず出します。無ければ、どの札でも出せます。"))
                ruleRow(tr("ハートは、だれかが場に出すまで先頭に出せません（手札がハートだけなら出せます）。"))
                ruleRow(tr("1 巡目はハートとスペードの Q を出せません（それしか無いときは出せます）。"))
            }
        }
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
