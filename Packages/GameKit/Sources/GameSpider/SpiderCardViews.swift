import SwiftUI
import Core

// MARK: - 札 1 枚の見た目

/// 札 1 枚の外形と中身（表 / 裏）。
struct SpiderCardBody: View {
    let card: SpiderCard
    let faceUp: Bool
    let isSelected: Bool
    let isCovered: Bool
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5
            )
            if !faceUp {
                PlayingCardBack(metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            } else if isCovered {
                SpiderCardIndex(card: card, metrics: metrics)
            } else {
                PlayingCardFace(figure: card.figure, metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

/// 重なって隠れた札の見出し（ランク + スートを左上に小さく）。
struct SpiderCardIndex: View {
    let card: SpiderCard
    let metrics: PlayingCardMetrics

    var body: some View {
        HStack(spacing: 2) {
            Text(card.rankLabel)
                .font(.system(size: metrics.rankFont * 0.72, weight: .black, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: metrics.suitFont * 0.72))
        }
        .foregroundStyle(PlayingCardInk.color(for: card.suit.playingCardSuit))
        .padding(.leading, metrics.cornerRadius * 0.7)
        .padding(.top, metrics.cornerRadius * 0.4)
    }
}

// MARK: - 配札

/// 配られてくる 1 枚。最初の 54 枚は列ごとに順に、山札からの 10 枚は列の順に飛ぶ。
struct SpiderDealtCardView<Content: View>: View {
    let pile: Int
    let depth: Int
    let restY: CGFloat
    let metrics: PlayingCardMetrics
    let dealing: Bool
    /// 山札からの配りか（最初の配札より速く、列の順だけで飛ぶ）。
    let fromStock: Bool
    let content: Content

    init(pile: Int, depth: Int, restY: CGFloat, metrics: PlayingCardMetrics,
         dealing: Bool, fromStock: Bool, @ViewBuilder content: () -> Content) {
        self.pile = pile
        self.depth = depth
        self.restY = restY
        self.metrics = metrics
        self.dealing = dealing
        self.fromStock = fromStock
        self.content = content()
    }

    var body: some View {
        CardDealtView(
            startOffset: SpiderMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics),
            animation: fromStock
                ? SpiderMotion.stockDealAppear(pile: pile)
                : SpiderMotion.dealAppear(pile: pile, depth: depth),
            dealing: dealing
        ) {
            content
        }
    }
}
