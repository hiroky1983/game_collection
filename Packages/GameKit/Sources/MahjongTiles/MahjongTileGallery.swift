#if DEBUG
import SwiftUI
import Core

/// 全 42 種（標準 34 種＋ソリティア専用の花牌 4・季節牌 4）を並べた確認用の画面。
///
/// 麻雀ソリティアは牌が積み重なって 1 枚が小さくなるため、**その大きさで全種を見分けられるか**が
/// 絵柄の設計の合否そのものになる。盤面のスクリーンショットでは重なりと減光で判定しづらいので、
/// 同じ描画を素の状態で複数サイズ並べて確認できるようにしてある。
/// アプリを `-showMahjongTiles` で起動すると出る（DEBUG 限定）。
public struct MahjongTileGallery: View {
    /// 並べる牌の幅（pt）。既定は 22pt（iPhone 17 Pro Max でズーム OFF のときの盤面の実測値）を
    /// 中心に、さらに小さい端末を想定した 18pt と、ズーム ON の 40pt を挟んだ 3 段階。
    private let widths: [CGFloat]

    public init(widths: [CGFloat] = [18, 22, 40]) {
        self.widths = widths
    }

    private static let faces: [MahjongFace] =
        MahjongTile.all.map(MahjongFace.standard)
        + (0..<4).map(MahjongFace.flower)
        + (0..<4).map(MahjongFace.season)

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(widths, id: \.self) { width in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("牌の幅 \(Int(width))pt")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                        tiles(width: width)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private func tiles(width: CGFloat) -> some View {
        let spacing = max(2, width * 0.12)
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: spacing)],
            spacing: spacing
        ) {
            ForEach(Self.faces.indices, id: \.self) { index in
                MahjongTileView(face: Self.faces[index], width: width, height: width * 1.40)
            }
        }
    }
}
#endif
