import CoreGraphics
import Foundation
import MahjongTiles

// MARK: - 卓の遠近レイアウト（麻雀刷新 #736）
//
// 卓を斜め上から見る見た目（`docs/ui-review/mahjong-3d/mock-v12.png`）の**幾何だけ**をここに置く。
// 描画（SwiftUI）は `MahjongView` が持ち、ここは純関数なのでテストで縛れる。
//
// 座標系: 卓上の位置を (u, v) で表す。u は左→右（0〜1）、v は奥→手前（0〜1）。
// `project(u:v:)` が画面上の点と縮尺（奥ほど小さい）に写す。以前の `VStack`/`HStack` の
// 自動フローはやめ、河・立て牌・副露・中央パネルの置き場をすべてこの写像で決める
// （要素どうしの重なりは `MahjongTableLayoutTests` が機械的に検査する）。

public struct MahjongTableLayout: Sendable {
    /// 卓（木枠を含む）の矩形。正方形を想定するが、縦横比が違っても壊れない。
    /// iPad では卓そのものが大きくなる（`aspectRatio(1)` で幅いっぱい）ので、牌の寸法は
    /// すべて卓の幅からの比で決め、`AdaptiveLayout.elementScale` は掛けない（二重拡大になる）。
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    // MARK: 寸法の比率（モック v12・幅 393pt を 1 とした値）

    /// 奥の辺の幅（手前の辺に対する比）。小さいほど遠近が強い。
    static let topWidthRatio: CGFloat = 270 / 393
    /// 木枠の太さ（幅に対する比）: 左右・下は 12/393、上は 16/393。
    static let frameSide: CGFloat = 12 / 393
    static let frameTop: CGFloat = 16 / 393
    static let frameBottom: CGFloat = 12 / 393
    /// 奥行きの詰め。v をこの冪で曲げて奥を詰め、遠近を強める。
    static let depthPower: CGFloat = 1.25
    /// 河の牌の基準幅（手前の縮尺 1 のとき、幅 393pt に対する比）。
    static let riverTileWidthRatio: CGFloat = 21 / 393
    /// 寝かせた牌の縦横比（`MahjongTileView` の河と同じ）。
    public static let tileAspect: CGFloat = 1.38
    /// 1 行の枚数（実物と同じ 6 枚）。
    public static let riverPerRow = 6
    /// 立て牌の高さ（pt。縮尺前）。
    static let standingHeight: CGFloat = 22
    /// 中央パネルの一辺（幅 393pt に対する比）。
    static let centerPanelRatio: CGFloat = 86 / 393

    // MARK: 写像

    public struct Projected: Sendable, Equatable {
        public var x: CGFloat
        public var y: CGFloat
        /// 縮尺（手前の辺で 1）。
        public var scale: CGFloat
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    private var feltTop: CGFloat { size.width * Self.frameTop }
    private var feltBottom: CGFloat { size.height - size.width * Self.frameBottom }
    private var feltHeight: CGFloat { feltBottom - feltTop }
    private var bottomWidth: CGFloat { size.width - 2 * size.width * Self.frameSide }
    private var topWidth: CGFloat { size.width * Self.topWidthRatio }

    /// 卓上の (u, v) を画面へ。
    public func project(u: CGFloat, v: CGFloat) -> Projected {
        let vv = pow(max(0, v), Self.depthPower)
        let w = topWidth + (bottomWidth - topWidth) * vv
        return Projected(x: size.width / 2 + (u - 0.5) * w, y: feltTop + vv * feltHeight, scale: w / bottomWidth)
    }

    /// 高さ z（pt。縮尺前）を持つ点。上へ持ち上げる量は縮尺に比例。
    public func project(u: CGFloat, v: CGFloat, z: CGFloat) -> CGPoint {
        let g = project(u: u, v: v)
        return CGPoint(x: g.x, y: g.y - z * g.scale)
    }

    // MARK: 卓の面

    /// 木枠（外形の台形）。a: 奥左, b: 奥右, c: 手前右, d: 手前左。
    public var woodFrame: [CGPoint] {
        let inset = size.width * Self.frameSide
        return [
            CGPoint(x: (size.width - topWidth) / 2 - inset - 2, y: 0),
            CGPoint(x: (size.width + topWidth) / 2 + inset + 2, y: 0),
            CGPoint(x: size.width + 2, y: size.height),
            CGPoint(x: -2, y: size.height),
        ]
    }

    /// フェルト（緑の台形）。
    public var felt: [CGPoint] {
        [
            project(u: 0, v: 0).point, project(u: 1, v: 0).point,
            project(u: 1, v: 1).point, project(u: 0, v: 1).point,
        ]
    }

    /// 点がフェルトの内側か。
    public func feltContains(_ p: CGPoint) -> Bool {
        Self.contains(polygon: felt, point: p)
    }

    static func contains(polygon: [CGPoint], point p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: 河

    /// 河の 1 枚の置き場。`seat` は手番順（0=自分, 1=下家(右), 2=対面, 3=上家(左)）。
    /// 6 枚で折り返し、各家から見て左から右へ並ぶ。牌は隙間なく密着させる
    /// （u の歩幅＝牌の幅の比。縮尺は同じ v で共通なので、比で決めれば密着する）。
    public struct Slot: Sendable, Equatable {
        public var center: CGPoint
        public var scale: CGFloat
        /// 度。各家の向き（自分 0、下家 -90、対面 180、上家 90）。
        public var rotation: Double
    }

    /// 河の牌の幅（縮尺 1 のとき）。**手前の辺の幅**に比を掛ける。u の歩幅も同じ比なので、
    /// どの奥行きでも「歩幅 × w(v) ＝ 牌の幅 × 縮尺」が成り立ち、隣の牌と隙間なく密着する。
    public var riverTileWidth: CGFloat { bottomWidth * Self.riverTileWidthRatio }

    public func riverSlot(seat: Int, index: Int) -> Slot {
        let col = CGFloat(index % Self.riverPerRow)
        let row = CGFloat(index / Self.riverPerRow)
        let stepU = Self.riverTileWidthRatio                            // 牌の幅（u）
        let stepRowU = stepU * Self.tileAspect                          // 牌の高さぶんの u
        // v 方向の歩幅は奥行きで縮む画面上の距離を近似で合わせる（テストで密着を検査）
        let stepV: CGFloat = 0.066
        let stepRowV: CGFloat = 0.074
        let stepSideV: CGFloat = 0.043
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: // 対面: 右から左へ（対面から見て左→右）、奥へ積む
            g = project(u: 0.5 + (5 - col - 2.5) * stepU, v: 0.30 - row * stepRowV)
            rotation = 180
        case 3: // 上家（左）: 奥から手前へ、列は右（中央側）から左へ
            // 列の x は先頭の牌（col 0）に揃える。同じ u でも台形では奥ほど中央へ寄るため、
            // 素直に写すと列が斜めに見える（会長指摘「横並びがズレてる」）。縮尺は各牌の v で取る
            let head = project(u: 0.30 - row * stepRowU, v: 0.34)
            let own = project(u: 0.30 - row * stepRowU, v: 0.34 + col * stepSideV)
            g = Projected(x: head.x, y: own.y, scale: own.scale)
            rotation = 90
        case 1: // 下家（右）: 手前から奥へ、列は左（中央側）から右へ
            let head = project(u: 0.70 + row * stepRowU, v: 0.64)
            let own = project(u: 0.70 + row * stepRowU, v: 0.64 - col * stepSideV)
            g = Projected(x: head.x, y: own.y, scale: own.scale)
            rotation = -90
        default: // 自分: 左から右へ、手前へ積む
            g = project(u: 0.5 + (col - 2.5) * stepU, v: 0.69 + row * stepV)
            rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 河の 1 枚が画面上で占める矩形（回転は 90 度単位なので幅・高さの入れ替えで足りる）。
    public func riverRect(seat: Int, index: Int) -> CGRect {
        let s = riverSlot(seat: seat, index: index)
        let w = riverTileWidth * s.scale
        let h = w * Self.tileAspect
        let sideways = seat == 1 || seat == 3
        let rw = sideways ? h : w, rh = sideways ? w : h
        return CGRect(x: s.center.x - rw / 2, y: s.center.y - rh / 2, width: rw, height: rh)
    }

    // MARK: 立て牌（CPU の手牌）

    /// CPU の手牌 `index` 枚目（0 が奥／左端）。`count` 枚を中央寄せで並べる。
    /// 描く側は **index の昇順**で渡す（奥から手前）。
    public func handBlock(seat: Int, index: Int, count: Int) -> (MahjongTileBlockGeometry, MahjongTileBlockFacing) {
        let h = Self.standingHeight
        switch seat {
        case 2:
            let du: CGFloat = 0.0433, tv: CGFloat = 0.03
            let u0 = 0.5 + (CGFloat(index) - CGFloat(count) / 2) * du
            let v0: CGFloat = 0.04
            let g = MahjongTileBlockGeometry(
                a: project(u: u0, v: v0, z: h), b: project(u: u0 + du, v: v0, z: h),
                c: project(u: u0 + du, v: v0 + tv, z: h), d: project(u: u0, v: v0 + tv, z: h),
                drop: project(u: u0, v: v0 + tv, z: 0).y - project(u: u0, v: v0 + tv, z: h).y,
                lean: 0, bulge: 2.2 * project(u: u0, v: v0).scale)
            return (g, .viewer)
        default:
            let tu: CGFloat = 0.032, dv: CGFloat = 0.05
            let v0 = 0.18 + (CGFloat(index) - (CGFloat(count) - 13) / 2) * dv
            let u0: CGFloat = seat == 3 ? 0.02 : 0.948
            let sc = project(u: u0, v: v0).scale
            let g = MahjongTileBlockGeometry(
                a: project(u: u0, v: v0, z: h), b: project(u: u0 + tu, v: v0, z: h),
                c: project(u: u0 + tu, v: v0 + dv, z: h), d: project(u: u0, v: v0 + dv, z: h),
                drop: project(u: u0, v: v0, z: 0).y - project(u: u0, v: v0, z: h).y,
                lean: 10 * sc, bulge: 5.5 * sc)
            return (g, seat == 3 ? .centerOnRight : .centerOnLeft)
        }
    }

    // MARK: 副露・立直棒・中央・ドラ

    /// 副露の置き場。実物どおり**各家から見て右側**の角: 対面＝画面左上、下家（右）＝右上、
    /// 上家（左）＝左下、自分＝右下。`Slot.center` はその角に寄せる基準点。
    ///
    /// 置き方は家ごとに違う（会長 QA「鳴きが多くなると重なる」）:
    /// - 対面: 左上の角から **1 組ずつ行を分けて下へ** 積む（横に伸ばすと対面の壁の下に潜る）
    /// - 上家・下家: 壁と河の 3 行目の間の細い帯に、河より小さい牌（`meldTileWidth(seat:)`）で **1 列** に並べる
    /// - 自分: 手牌一覧（`handOverview`）の **上の段**、右寄りに 1 組ずつ上へ積む。一覧が河と同じ
    ///   大きさになって手前の辺をほぼ使い切る（会長指摘 2026-09-13）ので、角には置けない。
    ///   右端 u 0.885 は下家の立て牌（u 0.948〜、上端が中央へ傾く）に触れない位置、左端は自分の河の右端（u 0.66）より右。
    public func meldSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: 0.10, v: 0.10); rotation = 180
        case 1: g = project(u: 0.905, v: 0.08); rotation = -90
        case 3: g = project(u: 0.095, v: 0.92); rotation = 90
        default: g = project(u: 0.885, v: 0.91); rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 副露の牌の幅（縮尺 1 のとき）。自分は河と同じ（会長指摘 2026-09-13）、
    /// 上家・下家は帯が細いので河の 0.62 倍、対面は 0.9 倍。
    public func meldTileWidth(seat: Int) -> CGFloat {
        switch seat {
        case 1, 3: return riverTileWidth * 0.62
        case 2: return riverTileWidth * 0.9
        default: return riverTileWidth
        }
    }

    /// 副露の牌の幅（自分の値。互換のため残す）。
    public var meldTileWidth: CGFloat { meldTileWidth(seat: 0) }

    /// `count` 枚の副露が占める画面上の矩形（重なりの検査用。`MahjongMeldRow` の並びを近似:
    /// 組の間隔は無視し、牌は密着とみなす）。
    public func meldRegion(seat: Int, tiles count: Int) -> CGRect {
        let slot = meldSlot(seat: seat)
        let w = meldTileWidth(seat: seat) * slot.scale
        let h = w * 1.34
        let c = slot.center
        switch seat {
        case 2: // 左上から下へ、行あたり最大 4 枚
            let rows = CGFloat((count + 3) / 4)
            return CGRect(x: c.x, y: c.y, width: w * 4, height: h * rows)
        case 1: // 右上から下へ 1 列（牌は横向き＝画面上の高さが w）
            return CGRect(x: c.x - h / 2, y: c.y, width: h, height: w * CGFloat(count))
        case 3: // 左下から上へ 1 列
            return CGRect(x: c.x - h / 2, y: c.y - w * CGFloat(count), width: h, height: w * CGFloat(count))
        default: // 右下から上へ、行あたり最大 4 枚
            let rows = CGFloat((count + 3) / 4)
            return CGRect(x: c.x - w * 4, y: c.y - h * rows, width: w * 4, height: h * rows)
        }
    }

    /// 立直棒（各家の河の内側）。
    public func riichiStickSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: 0.5, v: 0.36); rotation = 0
        // 左右の河の列（u 0.30 / 0.70、牌の高さぶん ±0.037）とパネル（u 0.38〜0.62）の隙間に置く
        case 3: g = project(u: 0.355, v: 0.49); rotation = 90
        case 1: g = project(u: 0.645, v: 0.49); rotation = 90
        default: g = project(u: 0.5, v: 0.62); rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 中央パネル（正方形）。
    public var centerPanel: CGRect {
        let g = project(u: 0.5, v: 0.49)
        let side = size.width * Self.centerPanelRatio * g.scale
        return CGRect(x: g.x - side / 2, y: g.y - side / 2, width: side, height: side)
    }

    /// 打牌が飛び始める点（#738）。自分は手牌一覧の中央、CPU はその家の立て牌の列の中ほど。
    public func discardOrigin(seat: Int) -> CGPoint {
        switch seat {
        case 2: return project(u: 0.5, v: 0.07).point
        case 3: return project(u: 0.05, v: 0.50).point
        case 1: return project(u: 0.95, v: 0.50).point
        default: return handOverview.center
        }
    }

    /// 手牌一覧の牌どうしの間隔（pt）。
    public static let handOverviewSpacing: CGFloat = 2

    /// 卓上の手牌一覧（`handOverviewOnTable`）の中心・幅・牌の幅。フェルトの手前の縁、中央。
    /// 牌は**河の牌と同じ幅**（会長指摘 2026-09-13。以前は幅 50% に 14 枚を詰めて 10pt ほどだった）。
    /// 幅は 14 枚（手牌 13 + ツモ）が収まる分。自分の副露（`meldSlot(seat: 0)`）はこの一覧の
    /// 上の段に積む。
    public var handOverview: (center: CGPoint, width: CGFloat, tileWidth: CGFloat) {
        let g = project(u: 0.5, v: 0.955)
        let tile = riverTileWidth * g.scale
        return (g.point, tile * 14 + Self.handOverviewSpacing * 13, tile)
    }
}
