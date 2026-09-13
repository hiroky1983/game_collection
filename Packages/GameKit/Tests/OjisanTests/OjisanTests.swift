import CoreGraphics
import SwiftUI
import Testing
@testable import Core

/// おじさん（共通キャラクター・#700）の図案が、向き×表情の全組み合わせで成立していること。
///
/// 絵の良し悪しは機械では測れないので、ここで縛るのは「壊れていない」ことだけ:
/// 部品が空でない・設計座標の外へ大きくはみ出さない・ビットマップが一度しか描かれない。
@Suite("おじさんの図案")
struct OjisanArtTests {
    static let combos: [(OjisanFacing, OjisanExpression)] =
        OjisanFacing.allCases.flatMap { f in OjisanExpression.allCases.map { (f, $0) } }

    @Test("向き×表情の全組み合わせで頭の部品がある", arguments: combos)
    func headPartsExist(facing: OjisanFacing, expression: OjisanExpression) {
        let parts = OjisanArt.headParts(facing: facing, expression: expression)
        #expect(parts.count >= 15, "\(facing) \(expression): 顔・耳・髪・眉・目・メガネ・鼻・口が揃っていない")
    }

    @Test("頭の部品は設計座標（100×100）の少し外までに収まる", arguments: combos)
    func headPartsStayInDesignBox(facing: OjisanFacing, expression: OjisanExpression) {
        // 真横の鼻は輪郭の外へ出すので、右側だけ少し余裕を見る。
        let allowed = CGRect(x: -2, y: -2, width: 104, height: 104)
        for part in OjisanArt.headParts(facing: facing, expression: expression) {
            let box = part.path.boundingRect
            #expect(allowed.contains(box), "\(facing) \(expression): 部品が設計座標をはみ出した \(box)")
        }
    }

    @Test("真横では奥の目が無く、正面と 3/4 では両目がある")
    func eyeCountByFacing() {
        // 目は黒い正円（直径 7.8、奥側は 3/4 で少し縮む）。真横で 1 つ、他は 2 つ。
        // 直径 6〜8 の正円は目しかない（ハイライトは 3 未満、鼻・頬は正円でない）。
        func eyes(_ f: OjisanFacing) -> Int {
            OjisanArt.headParts(facing: f, expression: .smile).filter {
                let b = $0.path.boundingRect
                return $0.strokeWidth == nil && abs(b.width - b.height) < 0.01 && (6...8).contains(b.width)
            }.count
        }
        #expect(eyes(.front) == 2)
        #expect(eyes(.threeQuarter) == 2)
        #expect(eyes(.side) == 1)
    }

    @Test("全身の部品は設計座標に収まり、頭が上半分・脚が下端にある")
    func mascotLayout() {
        let parts = OjisanArt.poseParts(.mascotFront)
        let union = parts.map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
        #expect(CGRect(x: -2, y: -2, width: 104, height: 104).contains(union))
        #expect(union.maxY > 95, "靴が下端まで届いていない")
        #expect(union.minY < 12, "頭が上端近くまで来ていない")
    }

    @Test("アフィン変換は線の太さとグラデーションの半径も一緒に縮める")
    func transformScalesStrokeAndGradient() {
        let part = OjisanPart(Path(ellipseIn: CGRect(x: 0, y: 0, width: 10, height: 10)),
                              .radial(colors: [.red, .blue], center: CGPoint(x: 5, y: 5), startRadius: 1, endRadius: 5),
                              stroke: 2)
        let scaled = part.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
        #expect(scaled.strokeWidth == 1)
        if case let .radial(_, center, s, e) = scaled.shading {
            #expect(center == CGPoint(x: 2.5, y: 2.5))
            #expect(s == 0.5 && e == 2.5)
        } else {
            Issue.record("radial のまま変換されるべき")
        }
    }
}

@Suite("おじさんのビットマップ")
@MainActor
struct OjisanBitmapTests {
    @Test("同じ絵は一度しか描かず、同じインスタンスを返す")
    func cached() {
        let a = OjisanBitmap.head(facing: .front, pixels: 64)
        let b = OjisanBitmap.head(facing: .front, pixels: 64)
        #expect(a != nil)
        #expect(a === b)
        #expect(a?.width == 64 && a?.height == 64)
    }

    @Test("ハブのアイコンが描ける")
    func hubIcon() {
        #expect(OjisanBitmap.hubIcon != nil)
    }
}
