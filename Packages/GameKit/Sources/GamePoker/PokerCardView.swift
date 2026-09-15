import SwiftUI
import Core

// MARK: - Card View

struct CardView: View {
    let card: PokerCard
    var faceUp: Bool = true
    var selected: Bool = false

    /// 画面の広さ（#458）。この画面は `GeometryReader` を 1 つも持たず札が固定 pt なので、
    /// iPad では 5 枚並べても 310pt しか占めず左右に大きな空白が残る。ここで札ごと拡大する。
    @Environment(\.adaptiveLayout) private var layout

    private var metrics: PlayingCardMetrics {
        PlayingCardMetrics.standard.scaled(by: layout.elementScale)
    }

    var body: some View {
        ZStack {
            // 外形・面・裏はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: selected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: selected ? 2 : 0.5,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )

            if faceUp {
                PlayingCardFace(figure: card.figure, metrics: metrics)
            } else {
                PlayingCardBack(metrics: metrics)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}
