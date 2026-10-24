import Core
import MahjongTiles
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）の麻雀ソリティア。
///
/// 取れる牌の条件・花牌と季節牌のペア・手詰まりは `MahjongSolitaireRules` / `MahjongFace.matches` の実装どおり
/// （`MahjongSolitaireOnboardingTests` が図と同じ形を実際の盤面で確かめる）。図は遊び方の図
/// （`MahjongSolitaireHowToFigures`）の部品を使い回し、牌は本番と同じ `MahjongTileView`。
/// ヒント・並べ替え・戻すの回数や広告の条件は「くわしいルール」に任せ、ここでは触れない。
@MainActor
enum MahjongSolitaireOnboarding {
    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "mahjong",
            title: tr("麻雀ソリティアのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("積まれた牌を、すべて消したらクリアです。"),
                        tr("消すのにかかった時間が、記録されます。"),
                    ],
                    figure: { AnyView(MahjongSolitaireHowToFigures.ClearFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("同じ絵柄の牌を、2 枚タップします。"),
                        tr("2 枚そろうと、牌が消えます。"),
                    ],
                    figure: { AnyView(MahjongSolitaireHowToFigures.PairFigure()) }
                ),
                OnboardingPage(
                    heading: tr("取れる牌・取れない牌"),
                    lines: [
                        tr("上に牌が乗っていない牌だけが、取れます。"),
                        tr("左右のどちらかが空いている牌だけが、取れます。"),
                    ],
                    figure: { AnyView(MahjongSolitaireHowToFigures.FreeTileFigure()) }
                ),
                OnboardingPage(
                    heading: tr("花牌と季節牌"),
                    lines: [
                        tr("花牌どうし、季節牌どうしは、絵柄がちがってもペアです。"),
                        tr("それ以外の牌は、まったく同じ絵柄の 2 枚だけが合います。"),
                    ],
                    figure: { AnyView(MahjongSolitaireHowToFigures.BonusPairFigure()) }
                ),
                OnboardingPage(
                    heading: tr("取れる組が無くなったら"),
                    lines: [
                        tr("取れる牌に同じ絵柄が無くなると、手詰まりです。"),
                        tr("広告を見て並べ替えるか、直前の 1 手を戻すか、はじめからやり直せます。"),
                    ],
                    figure: { AnyView(DeadlockFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 取れる 3 枚の絵柄がすべて違う → 手詰まり。
    private struct DeadlockFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    MahjongSolitaireHowToFigures.tile(.characters(1))
                    MahjongSolitaireHowToFigures.tile(.circles(2))
                    MahjongSolitaireHowToFigures.tile(.bamboos(7))
                }
                RuleFigureLabel(tr("同じ牌が取れる所に無い（手詰まり）"), color: Theme.coralText)
            }
        }
    }
}
