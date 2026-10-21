import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// 盆栽の絵（#2361）。会長提供の盆栽シート（ChatGPT 生成・2026-10-17）から切り出した透過 PNG
/// （`Resources/Bonsai/`。出どころは docs/design/bonsai/assets-license.md）。
///
/// 見た目は、**絵の全体（葉・枝・鉢・台）が当たり判定の円の内側に収まる**ように描く（#2418。#2361 の案 B は
/// 絵を円より大きく描いて木をはみ出させたが、大きい盆栽の葉が隣の小さい盆栽を隠した）。絵の不透明な画素を
/// すべて囲む最小に近い円を求め、その円が当たり判定の円（`FruitKind.radius`）にぴったり重なる大きさ・位置で描く。
/// 物理の半径は変えない。
/// **絵は回転させない**（物理の円が転がっても鉢は傾けない。`Fruit.angle` は描画に使わない）。
///
/// 鉢は段ごとに形が違う（#2388。丸鉢・懸崖鉢・水盤・卓に載せた鉢など。同じ色の段を大きさ以外でも見分ける）。
/// 形は `docs/design/bonsai/make_pots.py` で元の絵の鉢の部分だけを伸縮・卓を足して作ってある。
///
/// GameKit は macOS でも `swift test` するので UIImage は使わず ImageIO で読む（`OjisanPuzzleArt` と同じ作法）。
public enum BonsaiArt {
    /// 絵を囲む円。座標は画素（原点は絵の左上・下向きが正）。
    struct Enclosure {
        var cx: Double
        var cy: Double
        var radius: Double
    }

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

    /// 段ごとの、絵の不透明な部分を囲む円。
    static let enclosures: [FruitKind: Enclosure] = {
        var out: [FruitKind: Enclosure] = [:]
        for (kind, image) in images {
            out[kind] = enclosure(of: image)
        }
        return out
    }()

    /// `kind` の絵。読めなければ nil。
    public static func image(_ kind: FruitKind) -> CGImage? { images[kind] }

    /// 絵の画素 1 画素あたりの盤の抽象単位（囲む円の半径が `kind.radius` になる倍率）。
    static func unitsPerPixel(for kind: FruitKind) -> Double {
        guard let enclosure = enclosures[kind], enclosure.radius > 0 else { return 0 }
        return kind.radius / enclosure.radius
    }

    /// 絵の大きさ（盤の抽象単位）。縦横比は保つ。読めなければ円の直径の正方形。
    public static func spriteSize(for kind: FruitKind) -> CGSize {
        guard let image = images[kind], image.width > 0, image.height > 0 else {
            return CGSize(width: kind.radius * 2, height: kind.radius * 2)
        }
        let k = unitsPerPixel(for: kind)
        return CGSize(width: Double(image.width) * k, height: Double(image.height) * k)
    }

    /// 絵の中で円の中心にあたる点（`SKSpriteNode.anchorPoint` と同じ 0〜1・**下が原点**）。
    /// ノードをこの点を基準にして円の中心に置く。
    public static func anchor(for kind: FruitKind) -> CGPoint {
        guard let image = images[kind], let enclosure = enclosures[kind], image.width > 0, image.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(x: enclosure.cx / Double(image.width),
                       y: 1 - enclosure.cy / Double(image.height))
    }

    /// 円（中心 `x`,`y`・`kind` の半径）に対する絵の枠（盤の抽象単位・**下が原点**）。
    /// 絵を囲む円が、この円に重なる。
    public static func spriteFrame(for kind: FruitKind, x: Double, y: Double) -> CGRect {
        let size = spriteSize(for: kind)
        let anchor = anchor(for: kind)
        return CGRect(x: x - anchor.x * size.width, y: y - anchor.y * size.height,
                      width: size.width, height: size.height)
    }

    /// 不透明な画素（α > 16）の外周をすべて囲む円。まず外接する長方形の中心を置き、いちばん遠い点へ
    /// 少しずつ寄せていく（Bădoiu–Clarkson 法）。最後に半径を実際のいちばん遠い点まで広げて、必ず全体を囲む。
    static func enclosure(of image: CGImage) -> Enclosure {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard width > 0, height > 0,
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Enclosure(cx: Double(width) / 2, cy: Double(height) / 2, radius: Double(max(width, height)) / 2) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && data[(y * width + x) * 4 + 3] > 16
        }
        // 外周の画素だけを集める（内側の画素は外周より必ず近い）。画素の四隅を点として使う。
        var points: [(Double, Double)] = []
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                if !(opaque(x - 1, y) && opaque(x + 1, y) && opaque(x, y - 1) && opaque(x, y + 1)) {
                    for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                        points.append((Double(x) + dx, Double(y) + dy))
                    }
                }
            }
        }
        guard let first = points.first else {
            return Enclosure(cx: Double(width) / 2, cy: Double(height) / 2, radius: Double(max(width, height)) / 2)
        }
        var minX = first.0, maxX = first.0, minY = first.1, maxY = first.1
        for p in points {
            minX = min(minX, p.0); maxX = max(maxX, p.0); minY = min(minY, p.1); maxY = max(maxY, p.1)
        }
        var cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        for i in 1...400 {
            var far = first
            var farDistance = -1.0
            for p in points {
                let d = (p.0 - cx) * (p.0 - cx) + (p.1 - cy) * (p.1 - cy)
                if d > farDistance { farDistance = d; far = p }
            }
            cx += (far.0 - cx) / Double(i + 1)
            cy += (far.1 - cy) / Double(i + 1)
        }
        var radius = 0.0
        for p in points {
            radius = max(radius, ((p.0 - cx) * (p.0 - cx) + (p.1 - cy) * (p.1 - cy)).squareRoot())
        }
        return Enclosure(cx: cx, cy: cy, radius: radius)
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
