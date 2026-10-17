import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// 盆栽の絵（#2361）。会長提供の盆栽シート（ChatGPT 生成・2026-10-17）から切り出した透過 PNG
/// （`Resources/Bonsai/`。出どころは docs/design/bonsai/assets-license.md）。
///
/// 見た目は会長決裁の**案 B「木を大きく見せる」**: 当たり判定は円のまま、絵は円の直径の `canvasScale` 倍の
/// 正方形の枠に収め、**鉢の底（絵の下端）を円の下端に合わせる**。木は円から上へはみ出す。
/// **絵は回転させない**（物理の円が転がっても鉢は傾けない。`Fruit.angle` は描画に使わない）。
///
/// 鉢は段ごとに形が違う（#2388。丸鉢・懸崖鉢・水盤・卓に載せた鉢など。同じ色の段を大きさ以外でも見分ける）。
/// 形は `docs/design/bonsai/make_pots.py` で元の絵の鉢の部分だけを伸縮・卓を足して作ってあり、
/// 卓に載せた段は卓の底が絵の下端になる。
///
/// GameKit は macOS でも `swift test` するので UIImage は使わず ImageIO で読む（`OjisanPuzzleArt` と同じ作法）。
public enum BonsaiArt {
    /// 絵の枠の一辺は円の直径の何倍か（くっつきフルーツの茎・葉と同じ 1.3 倍）。
    public static let canvasScale: Double = 1.3

    /// 段ごとの絵。起動後の初回参照で 1 度だけ読む。
    static let images: [FruitKind: CGImage] = {
        var out: [FruitKind: CGImage] = [:]
        for kind in FruitKind.allCases {
            if let url = Bundle.module.url(forResource: kind.artName, withExtension: "png", subdirectory: "Bonsai"),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                out[kind] = image
            }
        }
        return out
    }()

    /// `kind` の絵。読めなければ nil。
    public static func image(_ kind: FruitKind) -> CGImage? { images[kind] }

    /// 絵の大きさ（盤の抽象単位）。一辺 `radius × 2 × canvasScale` の正方形に縦横比を保って収める。
    public static func spriteSize(for kind: FruitKind) -> CGSize {
        let side = kind.radius * 2 * canvasScale
        guard let image = images[kind], image.width > 0, image.height > 0 else {
            return CGSize(width: side, height: side)
        }
        let aspect = Double(image.width) / Double(image.height)
        return aspect >= 1
            ? CGSize(width: side, height: side / aspect)
            : CGSize(width: side * aspect, height: side)
    }

    /// 円（中心 `x`,`y`・`kind` の半径）に対する絵の枠（盤の抽象単位・**下が原点**）。
    /// 横は円の中心に揃え、下端は円の下端（鉢の底）に揃える。
    public static func spriteFrame(for kind: FruitKind, x: Double, y: Double) -> CGRect {
        let size = spriteSize(for: kind)
        return CGRect(x: x - size.width / 2, y: y - kind.radius, width: size.width, height: size.height)
    }
}

/// 盆栽 1 鉢の絵を出す SwiftUI の部品（「つぎ」の表示・縁側のおじさんの手元）。
public struct BonsaiIcon: View {
    private let kind: FruitKind

    public init(_ kind: FruitKind) {
        self.kind = kind
    }

    public var body: some View {
        if let image = BonsaiArt.image(kind) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
