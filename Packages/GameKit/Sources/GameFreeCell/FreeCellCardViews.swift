import SwiftUI
import Core

// MARK: - 札 1 枚の見た目

/// 札 1 枚の外形と中身。フリーセルは**全札が表向き**なので裏面は持たない。
struct FreeCellCardBody: View {
    let card: FreeCellCard
    let isSelected: Bool
    let isCovered: Bool
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: true,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5
            )
            if isCovered {
                // 下に重なった札は段差ぶんの帯しか見えないので、左上に小さく出す。
                FreeCellCardIndex(card: card, metrics: metrics)
            } else {
                PlayingCardFace(figure: card.figure, metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

/// 重なって隠れた札の見出し（ランク + スートを左上に小さく）。
struct FreeCellCardIndex: View {
    let card: FreeCellCard
    let metrics: PlayingCardMetrics

    var body: some View {
        HStack(spacing: 2) {
            Text(card.rankLabel)
                .font(.system(size: metrics.rankFont * 0.72, weight: .black, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: metrics.suitFont * 0.72))
        }
        .foregroundStyle(PlayingCardInk.color(for: card.suit))
        .padding(.leading, metrics.cornerRadius * 0.7)
        .padding(.top, metrics.cornerRadius * 0.4)
    }
}

// MARK: - 配札（#421 の横展開）

/// 配られてくる 1 枚。配り終わったあとは素通しなので、移動の補間には干渉しない。
///
/// 動きの器は共通基盤（`CardDealtView`・#524）が持ち、ここは**フリーセル固有の
/// 「どこから」「どの順で」飛んでくるか**を `FreeCellMotion` から渡す口になる
/// （配り元は上段のいちばん左・8 列へ 1 枚ずつ順に配る）。
struct FreeCellDealtCardView<Content: View>: View {
    let pile: Int
    let depth: Int
    /// 列の上端から測った、この札の落ち着き先。飛んでくる距離の計算に使う。
    let restY: CGFloat
    let metrics: PlayingCardMetrics
    let dealing: Bool

    let content: Content

    init(pile: Int, depth: Int, restY: CGFloat, metrics: PlayingCardMetrics,
         dealing: Bool, @ViewBuilder content: () -> Content) {
        self.pile = pile
        self.depth = depth
        self.restY = restY
        self.metrics = metrics
        self.dealing = dealing
        self.content = content()
    }

    var body: some View {
        CardDealtView(
            startOffset: FreeCellMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics),
            animation: FreeCellMotion.dealAppear(pile: pile, depth: depth),
            dealing: dealing
        ) {
            content
        }
    }
}
