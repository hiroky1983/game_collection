import Testing
import Foundation
import SwiftUI
@testable import MahjongTiles

/// 立てた牌のブロック（#735）。絵の良し悪しは測れないので「壊れていない」ことだけ縛る:
/// 3つの向きで部品が揃う・部品が幾何の外へ出ない・裏地が3色を使う・寝かせた牌は無変更。
@Suite("立てた牌のブロック")
struct MahjongTileBlockTests {
    /// 対面の列の1枚（上面が奥へ細い帯、裏地が手前）。
    static let front = MahjongTileBlockGeometry(
        a: CGPoint(x: 100, y: 50), b: CGPoint(x: 118, y: 50),
        c: CGPoint(x: 118, y: 54), d: CGPoint(x: 100, y: 54),
        drop: 22, lean: 0, bulge: 2)
    /// 左の家の1枚（中央が右）。
    static let left = MahjongTileBlockGeometry(
        a: CGPoint(x: 20, y: 100), b: CGPoint(x: 32, y: 100),
        c: CGPoint(x: 33, y: 118), d: CGPoint(x: 21, y: 118),
        drop: 22, lean: 8, bulge: 5)

    @Test("3つの向きで部品が揃う", arguments: [MahjongTileBlockFacing.viewer, .centerOnRight, .centerOnLeft])
    func partsExist(facing: MahjongTileBlockFacing) {
        let parts = MahjongTileBlockArt.parts(Self.left, facing: facing)
        // 対面は 裏地・上面・照り の3つ、左右は 裏地・断面・上面・稜線・照り の5つ。
        // 個数で縛るのは、断面（隣の牌に隠れる面）が消えても他の検査では気づけないため（verifier 指摘）。
        #expect(parts.count == (facing == .viewer ? 3 : 5), "\(facing): 部品が \(parts.count) 個")
        #expect(parts.contains { $0.strokeWidth == nil }, "塗りの部品が無い")
        #expect(parts.contains { $0.strokeWidth != nil }, "線の部品が無い")
    }

    @Test("部品は幾何の外へ大きく出ない（膨らみと足元のずれの分だけ許す）")
    func partsStayNearGeometry() {
        let g = Self.left
        let allowed = CGRect(x: g.a.x - g.lean - g.bulge - 1, y: g.a.y - g.bulge - 1,
                             width: (g.c.x - g.a.x) + 2 * (g.lean + g.bulge) + 2,
                             height: (g.c.y - g.a.y) + g.drop + 2 * g.bulge + 2)
        for facing in [MahjongTileBlockFacing.viewer, .centerOnRight, .centerOnLeft] {
            for part in MahjongTileBlockArt.parts(g, facing: facing) {
                #expect(allowed.contains(part.path.boundingRect), "\(facing): \(part.path.boundingRect) が \(allowed) の外")
            }
        }
    }

    @Test("裏地は左右・対面で同じ3色を使う")
    func backUsesSharedPalette() {
        func backColors(_ facing: MahjongTileBlockFacing) -> [Color]? {
            let first = MahjongTileBlockArt.parts(Self.left, facing: facing).first
            if case let .radial(colors, _, _)? = first?.shading { return colors }
            return nil
        }
        let expected = [MahjongBackPalette.top, MahjongBackPalette.mid, MahjongBackPalette.edge]
        #expect(backColors(.viewer) == expected)
        #expect(backColors(.centerOnRight) == expected)
        #expect(backColors(.centerOnLeft) == expected)
    }

    @Test("左の家と右の家は裏地の膨らみが逆向き")
    func bulgeMirrors() {
        let g = Self.left
        let right = MahjongTileBlockArt.parts(g, facing: .centerOnRight)[0].path.boundingRect
        let leftF = MahjongTileBlockArt.parts(g, facing: .centerOnLeft)[0].path.boundingRect
        // 中央が右なら裏地は b/c（右側）から右へ膨らみ、中央が左なら a/d（左側）から左へ膨らむ
        #expect(right.maxX > g.c.x + g.lean)
        #expect(leftF.minX < g.a.x - g.lean)
    }

    @Test("寝かせた牌（MahjongTileView）の側面の割合は #366 のまま")
    func flatTileUnchanged() {
        #expect(MahjongTileArt.sideHeightRatio == 0.08)
    }
}
