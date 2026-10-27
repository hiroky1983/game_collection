import Core
import MahjongTiles
import SwiftUI

/// 図入りの遊び方（#2044）の麻雀の図。文言は `HowToPlayGuide.mahjong.items` / `.mahjongSingleHand.items`
/// （Core）と同じ順で、先頭（対局の流れ）だけが対局の長さで変わる。牌は本番と同じ `MahjongTileView`。
@MainActor
enum MahjongHowToFigures {
    /// 東風戦の版。
    static let items: [@MainActor @Sendable () -> AnyView] = [{ AnyView(FlowFigure(rounds: 4)) }] + common

    /// 一局戦の版。
    static let singleHandItems: [@MainActor @Sendable () -> AnyView] = [{ AnyView(FlowFigure(rounds: 1)) }] + common

    private static let common: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(DrawDiscardFigure()) },
        { AnyView(WinningShapeFigure()) },
        { AnyView(RiichiFigure()) },
        { AnyView(CallFigure()) },
    ]

    /// 図の牌の寸法（手牌 14 枚が SE のカードに収まる幅）。
    private static let tileWidth: CGFloat = 19
    private static let tileHeight: CGFloat = 26

    private static func tile(_ tile: MahjongTile, selected: Bool = false, hinted: Bool = false,
                             width: CGFloat = tileWidth, height: CGFloat = tileHeight) -> some View {
        MahjongTileView(tile: tile, width: width, height: height, isSelected: selected, isHinted: hinted)
    }

    /// 東 1 局 → … → 東 4 局（一局戦は東 1 局だけ）。持ち点は 25000 点から。
    struct FlowFigure: View {
        let rounds: Int

        var body: some View {
            VStack(spacing: 8) {
                RuleFrames(count: rounds, spacing: 4) { index in
                    Text(tr("東%lld局", index + 1))
                        .scaledFont(12, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.coral.opacity(0.15)))
                }
                RuleFigureLabel(tr("持ち点 25000 点から。多い順に順位"))
            }
        }
    }

    /// 1 枚引いて（ツモ）、タップした牌を切る。
    struct DrawDiscardFigure: View {
        private let hand: [MahjongTile] = [.characters(2), .characters(3), .circles(5), .circles(6), .bamboos(9)]

        var body: some View {
            RuleFrames(count: 2, spacing: 8) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 1) {
                        ForEach(Array(hand.enumerated()), id: \.offset) { i, t in
                            MahjongHowToFigures.tile(t, selected: index == 1 && i == 4)
                                .offset(y: index == 1 && i == 4 ? -5 : 0)
                        }
                        MahjongHowToFigures.tile(.circles(7), hinted: index == 0)
                            .padding(.leading, 5)
                    }
                    .padding(.top, 5)
                    RuleFigureLabel(index == 0 ? tr("1 枚引く") : tr("タップで切る"),
                                    color: index == 1 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 和了の形: 連番 3 枚 ×2・同じ牌 3 枚 ×2・同じ牌 2 枚。
    struct WinningShapeFigure: View {
        let groups: [(tiles: [MahjongTile], label: String)] = [
            ([.characters(1), .characters(2), .characters(3)], tr("連番")),
            ([.circles(4), .circles(5), .circles(6)], tr("連番")),
            ([.bamboos(7), .bamboos(7), .bamboos(7)], tr("同じ 3 枚")),
            ([.dragon(0), .dragon(0), .dragon(0)], tr("同じ 3 枚")),
            ([.wind(0), .wind(0)], tr("同じ 2 枚")),
        ]

        var body: some View {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(spacing: 4) {
                            HStack(spacing: 0) {
                                ForEach(Array(group.tiles.enumerated()), id: \.offset) { _, t in
                                    MahjongHowToFigures.tile(t)
                                }
                            }
                            RuleFigureLabel(group.label, color: group.tiles.count == 2 ? Theme.coralText : Theme.inkSubText)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(width: MahjongHowToFigures.tileWidth * CGFloat(group.tiles.count) + 4)
                        }
                    }
                }
                RuleFigureLabel(tr("4 組 ＋ 1 組 ＝ 和了"), color: Theme.coralText)
            }
        }
    }

    /// あと 1 枚で和了（聴牌）→ 立直を宣言すると役が付く。
    struct RiichiFigure: View {
        let hand: [MahjongTile] = [
            .characters(1), .characters(2), .characters(3), .circles(4), .circles(5), .circles(6),
            .bamboos(7), .bamboos(7), .bamboos(7), .dragon(0), .dragon(0), .wind(0), .wind(0),
        ]

        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(hand.enumerated()), id: \.offset) { _, t in
                        MahjongHowToFigures.tile(t, width: 18, height: 25)
                    }
                    Image(systemName: "questionmark")
                        .scaledFont(13, weight: .black, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                        .frame(width: 18, height: 25)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 3, style: .continuous)
                            .strokeBorder(Theme.coral, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                        .padding(.leading, 4)
                }
                RuleFigureLabel(tr("あと 1 枚で和了（聴牌）"))
                HStack(spacing: 8) {
                    Text(tr("立直"))
                        .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Fill.coral))
                    Image(systemName: "arrow.right")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                    RuleFigureLabel(tr("役が付く"), color: Theme.coralText)
                }
            }
        }
    }

    /// 他の人の捨て牌をポン（同じ牌 2 枚 + 捨て牌 = 3 枚）。
    struct CallFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(alignment: .bottom, spacing: 8) {
                            VStack(spacing: 2) {
                                MahjongHowToFigures.tile(.circles(5), hinted: true)
                                RuleFigureLabel(tr("捨て牌"))
                            }
                            VStack(spacing: 2) {
                                HStack(spacing: 0) {
                                    MahjongHowToFigures.tile(.circles(5))
                                    MahjongHowToFigures.tile(.circles(5))
                                }
                                RuleFigureLabel(tr("手牌"))
                            }
                        }
                    } else {
                        VStack(spacing: 2) {
                            HStack(spacing: 0) {
                                MahjongHowToFigures.tile(.circles(5))
                                MahjongHowToFigures.tile(.circles(5), hinted: true)
                                MahjongHowToFigures.tile(.circles(5))
                            }
                            RuleFigureLabel(tr("ポン"), color: Theme.coralText)
                        }
                    }
                }
            }
        }
    }
}

extension MahjongGameLength {
    /// この長さの図入りの遊び方。ゲーム画面ヘッダーの「？」と開始シートで同じものを使う。
    @MainActor
    var howToPlayGuide: HowToPlayGuide {
        switch self {
        case .tonpuu: .mahjong.illustrated(MahjongHowToFigures.items)
        case .singleHand: .mahjongSingleHand.illustrated(MahjongHowToFigures.singleHandItems)
        }
    }

    /// 開始シートで常に見せる項目の位置（`howToPlayGuide.items` の添字）: 対局の流れ・和了の形。
    static let setupKeyItemIndices = [0, 2]

    /// 開始シートで常に見せる項目。
    @MainActor
    var setupKeyItems: [HowToPlayItem] {
        let items = howToPlayGuide.items
        return Self.setupKeyItemIndices.map { items[$0] }
    }

    /// 開始シートで折りたたむ項目（ツモと打牌・立直・鳴き）。
    @MainActor
    var setupDetailItems: [HowToPlayItem] {
        let keys = Set(Self.setupKeyItemIndices)
        return howToPlayGuide.items.enumerated().filter { !keys.contains($0.offset) }.map(\.element)
    }
}
