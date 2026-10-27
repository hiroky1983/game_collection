import Core
import MahjongTiles
import SwiftUI

/// 図入りの遊び方（#2044）の麻雀ソリティアの図。文言は `HowToPlayGuide.mahjongSolitaire.items`（Core）と同じ順。
/// 牌は本番と同じ `MahjongTileView`（取れない牌は本番と同じく暗く落とす）。
@MainActor
enum MahjongSolitaireHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PairFigure()) },
        { AnyView(FreeTileFigure()) },
        { AnyView(BonusPairFigure()) },
        { AnyView(ClearFigure()) },
    ]

    private static let tileWidth: CGFloat = 26
    private static let tileHeight: CGFloat = 35

    static func tile(_ face: MahjongFace, blocked: Bool = false, selected: Bool = false) -> some View {
        MahjongTileView(face: face, width: tileWidth, height: tileHeight, isBlocked: blocked, isSelected: selected)
    }

    /// 牌 1 枚ぶんの空き（消えたあと）。
    private struct EmptySpot: View {
        var body: some View {
            RoundedRectangle(cornerRadius: Theme.cornerSmall / 3, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: MahjongSolitaireHowToFigures.tileWidth, height: MahjongSolitaireHowToFigures.tileHeight)
        }
    }

    /// 同じ絵柄の 2 枚をタップ → 消える。
    struct PairFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if index == 0 {
                            MahjongSolitaireHowToFigures.tile(.circles(3), selected: true)
                            MahjongSolitaireHowToFigures.tile(.bamboos(5))
                            MahjongSolitaireHowToFigures.tile(.circles(3), selected: true)
                        } else {
                            EmptySpot()
                            MahjongSolitaireHowToFigures.tile(.bamboos(5))
                            EmptySpot()
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("同じ牌を 2 枚タップ") : tr("消える"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 取れる牌・取れない牌。左右の端は取れる／両どなりがふさがった牌と、上に牌が乗った牌は取れない。
    struct FreeTileFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                // 横一列: 端の牌は取れる・まん中は取れない。
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        MahjongSolitaireHowToFigures.tile(.characters(2))
                        MahjongSolitaireHowToFigures.tile(.characters(7), blocked: true)
                        MahjongSolitaireHowToFigures.tile(.bamboos(4))
                    }
                    HStack(spacing: 0) {
                        RuleVerdictMark(true).frame(width: MahjongSolitaireHowToFigures.tileWidth)
                        RuleVerdictMark(false).frame(width: MahjongSolitaireHowToFigures.tileWidth)
                        RuleVerdictMark(true).frame(width: MahjongSolitaireHowToFigures.tileWidth)
                    }
                    RuleFigureLabel(tr("端は取れる"))
                }
                // 上に牌が乗っている: 下の牌は取れない。
                VStack(spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        MahjongSolitaireHowToFigures.tile(.wind(1), blocked: true)
                        MahjongSolitaireHowToFigures.tile(.dragon(1))
                            .offset(x: 10, y: -12)
                    }
                    .padding(.top, 12)
                    .frame(width: MahjongSolitaireHowToFigures.tileWidth + 10, alignment: .leading)
                    RuleVerdictMark(false)
                    RuleFigureLabel(tr("下の牌は取れない"))
                }
            }
        }
    }

    /// 花牌どうし・季節牌どうしは、絵柄がちがってもペア。
    struct BonusPairFigure: View {
        var body: some View {
            HStack(spacing: 20) {
                pair(.flower(0), .flower(1), tr("花牌"))
                pair(.season(0), .season(3), tr("季節牌"))
            }
        }

        private func pair(_ a: MahjongFace, _ b: MahjongFace, _ name: String) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    MahjongSolitaireHowToFigures.tile(a, selected: true)
                    Image(systemName: "equal")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                    MahjongSolitaireHowToFigures.tile(b, selected: true)
                }
                RuleFigureLabel(name)
            }
        }
    }

    /// 積まれた牌を全部消したらクリア。
    struct ClearFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        ZStack {
                            HStack(spacing: 0) {
                                ForEach(0..<4, id: \.self) { i in
                                    MahjongSolitaireHowToFigures.tile([.circles(1), .bamboos(8), .characters(5), .wind(2)][i],
                                                                      blocked: i == 1 || i == 2)
                                }
                            }
                            HStack(spacing: 0) {
                                MahjongSolitaireHowToFigures.tile(.characters(9))
                                MahjongSolitaireHowToFigures.tile(.circles(9))
                            }
                            .offset(x: 3, y: -9)
                        }
                        .padding(.top, 9)
                        RuleFigureLabel(tr("積まれた牌を"))
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .scaledFont(30, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(Color(hex: 0x2E9D6B))
                            .frame(height: MahjongSolitaireHowToFigures.tileHeight + 9)
                        RuleFigureLabel(tr("全部消したらクリア"), color: Theme.coralText)
                    }
                }
            }
        }
    }
}
