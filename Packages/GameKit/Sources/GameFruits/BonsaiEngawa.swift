import Core
import CoreGraphics
import CoreOjisanPixel
import Foundation
import ImageIO
import SwiftUI

/// 縁側に立つおじさんの絵（#2361）。
///
/// **専用のドット絵は会長が作る**（作業服ではなく盆栽の世界観のおじさん）。それまでは おじさんの荷物運びパズルの
/// 作業服おじさん（`OjisanWork_carry_light_smile`・Codex 製。出所は docs/design/ojisan-pixel-pipeline）から
/// 段ボール箱だけを消したコマ（`Resources/BonsaiOjisan_hold.png`）で代用している。
///
/// **差し替えるときはこの型の定数だけを直す**: 画像名（`holdImageName`）・手の位置（`handDot`）・
/// しかめ面のかぶせ方（`worriedFaceRect`。専用の絵にしかめ面のコマがあれば `worriedImageName` に名前を入れる）。
enum BonsaiOjisanArt {
    /// 盆栽を両手で持って立つコマ（1 ドット = 1px・透明背景・右向き）。
    static let holdImageName = "BonsaiOjisan_hold"
    /// 危険線に近いときのコマ。専用の絵ができるまでは nil で、代わりに共通のしかめ面（`OjisanFace_frown`）を頭にかぶせる。
    static let worriedImageName: String? = nil
    /// 手の位置（画像の左上からのドット）。持っている盆栽の**鉢の底の中央**をここに合わせる。
    static let handDot = CGPoint(x: 24, y: 34)
    /// しかめ面（Core の `OjisanPixel.faceImages[.frown]`・64×60）を頭にかぶせる枠（ドット・左上原点）。
    /// `worriedImageName` があるときは使わない。
    static let worriedFaceRect = CGRect(x: 0, y: -3, width: 32, height: 30)

    static let holdImage: CGImage? = load(holdImageName)
    static let worriedImage: CGImage? = worriedImageName.flatMap(load)

    private static func load(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// コマのドット数。読めなければ荷物運びパズルのコマと同じ 37×47 とみなす。
    static var dotSize: CGSize {
        guard let image = holdImage else { return CGSize(width: 37, height: 47) }
        return CGSize(width: image.width, height: image.height)
    }
}

/// 縁側の寸法と、おじさん・手元の盆栽の置き場所（#2361）。単位は盤の抽象単位（盤の幅 = 100）で、
/// **座標は上が原点**（SwiftUI と同じ向き。0 = 縁側の上端、`height` = 縁側の下端 = 庭の上端）。
enum BonsaiEngawaLayout {
    /// 縁側の高さ。手元の盆栽（落とせる最大のみかん）の木が縁側から大きくはみ出さない高さ。
    static let height: Double = 22
    /// おじさんの 1 ドットの大きさ。37×47 ドットのコマが縁側にほぼ収まる（盤の幅 100 に対しておじさんの背丈 22.6）。
    static let dot: Double = 0.48
    /// おじさんの足を縁側の下端からどれだけ下（庭の側）へ出すか。縁側の框（かまち）に立って見える。
    static let footSink: Double = 1

    /// 縁側と盤を合わせた枠の縦横比（幅 / 高さ）。View はこの比で枠を作る。
    static var aspectRatio: Double { FruitField.Metrics.width / (FruitField.Metrics.height + height) }

    /// おじさんの枠。手が落とす位置（`cursorX`）に来るよう左右に動き、縁側の両端で止まる。
    static func ojisanFrame(cursorX: Double) -> CGRect {
        let size = BonsaiOjisanArt.dotSize
        let width = size.width * dot
        let height = size.height * dot
        let idealX = cursorX - BonsaiOjisanArt.handDot.x * dot
        let x = min(max(0, idealX), FruitField.Metrics.width - width)
        return CGRect(x: x, y: self.height + footSink - height, width: width, height: height)
    }

    /// 手に持つ盆栽の枠。**横は必ず落とす位置（`cursorX`）の真上**（おじさんが端で止まっても盆栽はずれない）。
    /// 鉢の底を手の高さに合わせ、大きさは盤の上と同じ（`BonsaiArt.spriteSize`）。
    static func heldFrame(kind: FruitKind, cursorX: Double) -> CGRect {
        let size = BonsaiArt.spriteSize(for: kind)
        let ojisan = ojisanFrame(cursorX: cursorX)
        let handY = ojisan.minY + BonsaiOjisanArt.handDot.y * dot
        return CGRect(x: cursorX - size.width / 2, y: handY - size.height, width: size.width, height: size.height)
    }
}

/// 縁側の板（背景）。木の板を横に並べ、手前（庭との境）に濃い框を引く。
struct BonsaiEngawaBoards: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: FruitsPalette.wood)))
            let boards = 5
            let frameHeight = size.height * 0.1
            let boardHeight = (size.height - frameHeight) / CGFloat(boards)
            for index in 1...boards {
                let y = boardHeight * CGFloat(index)
                context.fill(Path(CGRect(x: 0, y: y - 1.2, width: size.width, height: 0.8)),
                             with: .color(Color(hex: FruitsPalette.woodLight)))
                context.fill(Path(CGRect(x: 0, y: y - 0.4, width: size.width, height: 0.8)),
                             with: .color(Color(hex: FruitsPalette.woodDark)))
            }
            context.fill(Path(CGRect(x: 0, y: size.height - frameHeight, width: size.width, height: frameHeight)),
                         with: .color(Color(hex: FruitsPalette.woodDark)))
        }
        .accessibilityHidden(true)
    }
}

/// 縁側に立って「つぎ」の盆栽を持つおじさん。`unit` は盤の抽象単位 1 の pt。
struct BonsaiOjisanLayer: View {
    let cursorX: Double
    let heldKind: FruitKind?
    let isNearLine: Bool
    let unit: CGFloat

    var body: some View {
        let ojisan = scaled(BonsaiEngawaLayout.ojisanFrame(cursorX: cursorX))
        // 危険線に近いときはしかめ面にする。
        let worried = isNearLine
        ZStack(alignment: .topLeading) {
            if let image = (worried ? BonsaiOjisanArt.worriedImage : nil) ?? BonsaiOjisanArt.holdImage {
                pixelImage(image)
                    .frame(width: ojisan.width, height: ojisan.height)
                    .offset(x: ojisan.minX, y: ojisan.minY)
            }
            if worried, BonsaiOjisanArt.worriedImage == nil, let face = OjisanPixel.faceImages[.frown] {
                let rect = BonsaiOjisanArt.worriedFaceRect
                let dot = BonsaiEngawaLayout.dot * unit
                pixelImage(face)
                    .frame(width: rect.width * dot, height: rect.height * dot)
                    .offset(x: ojisan.minX + rect.minX * dot, y: ojisan.minY + rect.minY * dot)
            }
            if let kind = heldKind {
                let held = scaled(BonsaiEngawaLayout.heldFrame(kind: kind, cursorX: cursorX))
                BonsaiIcon(kind)
                    .frame(width: held.width, height: held.height)
                    .offset(x: held.minX, y: held.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scaled(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * unit, y: rect.minY * unit, width: rect.width * unit, height: rect.height * unit)
    }

    private func pixelImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
    }
}
