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
    ///
    /// 大きさ 0 の卓（SwiftUI が最初のレイアウトで渡してくる）では `w / bottomWidth` が 0 ÷ 0 で NaN になり、
    /// それが牌の幅・位置すべてに広がって「Invalid frame dimension」の連発と、幅 393pt 以下の端末での
    /// クラッシュを起こしていた（v1.1.5 の開発版で会長が実機・当番が iPhone SE で再現）。
    /// 縮尺は「0 の卓では 0」とし、NaN を作らない。描画側は `MahjongView.mahjongTable` が一辺 0 以下では
    /// 中身を作らないので、ここは二重の守り。
    public func project(u: CGFloat, v: CGFloat) -> Projected {
        let vv = pow(max(0, v), Self.depthPower)
        let w = topWidth + (bottomWidth - topWidth) * vv
        let scale = bottomWidth > 0 ? w / bottomWidth : 0
        return Projected(x: size.width / 2 + (u - 0.5) * w, y: feltTop + vv * feltHeight, scale: scale)
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

    /// CPU の手牌 `index` 枚目（0 が奥／左端）。対面は `count` 枚を中央寄せ、上家・下家は
    /// **下家は手前の端（v 0.88）、上家は奥の端（v 0.13）に固定**して枚数ぶん縮む
    /// （副露で減った分だけ、その家の右側＝下家は奥・上家は手前の端が空き、そこへ河と同じ大きさの
    /// 副露を置く。会長指摘 2026-09-13「左右の鳴き牌の大きさが直っていない」）。
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
            let start: CGFloat = seat == 1 ? 0.88 - CGFloat(count) * dv : 0.13
            let v0 = start + CGFloat(index) * dv
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
    /// - 上家・下家: 立て牌の壁と同じ列で、副露のぶん短くなった壁の空いた端（下家は奥、上家は手前）から
    ///   **1 列** に並べる（`handBlock` が壁を片側に寄せる）。河と同じ大きさ。1 枚ずつの置き場は
    ///   `sideMeldSlot`（台形の縁に沿うので列は少し斜め）。ここの `Slot` は列の先端。
    /// - 自分: 手牌一覧（`handOverview`）の **上の段**、右寄りに 1 組ずつ上へ積む。一覧が河と同じ
    ///   大きさになって手前の辺をほぼ使い切る（会長指摘 2026-09-13）ので、角には置けない。
    ///   右端 u 0.885 は下家の立て牌（u 0.948〜、上端が中央へ傾く）に触れない位置、左端は自分の河の右端（u 0.66）より右。
    public func meldSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: 0.10, v: 0.10); rotation = 180
        case 1: g = project(u: Self.sideMeldU(seat: 1), v: Self.sideMeldStartV(seat: 1)); rotation = -90
        case 3: g = project(u: Self.sideMeldU(seat: 3), v: Self.sideMeldStartV(seat: 3)); rotation = 90
        default: g = project(u: 0.885, v: 0.885); rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 副露の牌の幅（縮尺 1 のとき）。自分・上家・下家は河と同じ（会長指摘 2026-09-13）、
    /// 対面は 0.9 倍（左上の角から下へ積むぶん、上家の河の先頭に近い）。
    public func meldTileWidth(seat: Int) -> CGFloat {
        seat == 2 ? riverTileWidth * 0.9 : riverTileWidth
    }

    /// 上家・下家の 1 列に並べた副露の、組と組の間隔（pt）。
    public static let meldGroupSpacing: CGFloat = 3

    /// 上家・下家の副露の列の u（壁の列に揃える。下家の壁は u 0.948〜、上家は 0.02〜）。
    static func sideMeldU(seat: Int) -> CGFloat { seat == 1 ? 0.955 : 0.045 }
    /// 列の先端の v。下家は奥の縁ぎりぎり（牌の縁がフェルトの奥の辺に掛からない最小）、
    /// 上家は手牌一覧（v 0.955、上端はその 12pt ほど上）に触れない位置。
    static func sideMeldStartV(seat: Int) -> CGFloat { seat == 1 ? 0.05 : 0.885 }

    /// 上家・下家の副露 1 枚の置き場。`ordinal` は全組を通した通し番号（0 が列の先端）、`gaps` は
    /// その前にある組の区切りの数。壁と同じ列（u 一定）に沿って、下家は奥から手前へ、上家は手前から奥へ、
    /// **画面上の距離**で牌の幅ぶんずつ進める（奥ほど縮むので v の歩幅は一定にしない）。
    public func sideMeldSlot(seat: Int, ordinal: Int, gaps: Int) -> Slot {
        let u = Self.sideMeldU(seat: seat)
        let dir: CGFloat = seat == 1 ? 1 : -1
        var g = project(u: u, v: Self.sideMeldStartV(seat: seat))
        for _ in 0..<max(0, ordinal) {
            // 隣の牌の中心までの距離は「両方の牌の幅の平均」。次の縮尺は 1 歩先で読み直す
            let w0 = riverTileWidth * g.scale
            let probe = projectAt(u: u, y: g.y + dir * w0)
            g = projectAt(u: u, y: g.y + dir * (w0 + riverTileWidth * probe.scale) / 2)
        }
        if gaps > 0 { g = projectAt(u: u, y: g.y + dir * CGFloat(gaps) * Self.meldGroupSpacing) }
        return Slot(center: g.point, scale: g.scale, rotation: seat == 1 ? -90 : 90)
    }

    /// 画面の y から卓上の v を戻して写す（`project(u:v:)` の逆）。
    private func projectAt(u: CGFloat, y: CGFloat) -> Projected {
        let vv = min(1, max(0, (y - feltTop) / feltHeight))
        return project(u: u, v: pow(vv, 1 / Self.depthPower))
    }

    /// 上家・下家の副露 1 枚が画面上で占める矩形（横向きなので幅が牌の高さ）。
    public func sideMeldRect(seat: Int, ordinal: Int, gaps: Int) -> CGRect {
        let slot = sideMeldSlot(seat: seat, ordinal: ordinal, gaps: gaps)
        let w = riverTileWidth * slot.scale
        let h = w * Self.tileAspect
        return CGRect(x: slot.center.x - h / 2, y: slot.center.y - w / 2, width: h, height: w)
    }

    /// `groups` 組・合計 `count` 枚の副露を、重なりの検査用に矩形の列で返す。対面・自分は `meldRegion`
    /// 1 つ、上家・下家は 1 枚ずつ（列が斜めなので、外接矩形では縁の判定が粗すぎる）。
    /// 組の区切りは 3 枚ごとにあるとみなす（ポンとチーは 3 枚。カンが混じると区切りは少なめに出る）。
    public func meldTileRects(seat: Int, groups: Int, tiles count: Int) -> [CGRect] {
        guard seat == 1 || seat == 3 else { return [meldRegion(seat: seat, groups: groups, tiles: count)] }
        return (0..<count).map { sideMeldRect(seat: seat, ordinal: $0, gaps: min($0 / 3, max(0, groups - 1))) }
    }

    /// 副露の牌の幅（自分の値。互換のため残す）。
    public var meldTileWidth: CGFloat { meldTileWidth(seat: 0) }

    /// `groups` 組・合計 `count` 枚の副露が占める画面上の矩形（重なりの検査用。`MahjongTableView.meldRow`
    /// の置き方に合わせる: 対面・自分は `slot.center` が **1 組目の行の縦の中央**で、1 組 1 行
    /// （`MahjongMeldRow.packRows` は 3 枚 + 3 枚を同じ行に詰めない）、行の高さ `w × 1.34` を間隔 1pt で積む。
    /// 上家・下家は 1 枚ずつの矩形（`meldTileRects`）の外接矩形。
    public func meldRegion(seat: Int, groups: Int, tiles count: Int) -> CGRect {
        if seat == 1 || seat == 3 {
            return meldTileRects(seat: seat, groups: groups, tiles: count).reduce(CGRect.null) { $0.union($1) }
        }
        let slot = meldSlot(seat: seat)
        let w = meldTileWidth(seat: seat) * slot.scale
        let h = w * 1.34
        let c = slot.center
        let rows = CGFloat(max(1, groups))
        let stack = h * rows + (rows - 1)
        if seat == 2 { // 左上から下へ、1 組 1 行
            return CGRect(x: c.x, y: c.y - h / 2, width: w * 4, height: stack)
        }
        // 自分: 右下から上へ、1 組 1 行
        return CGRect(x: c.x - w * 4, y: c.y + h / 2 - stack, width: w * 4, height: stack)
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

    /// 打牌が飛び始める点（#738）。CPU はその家の立て牌の列の中ほど。自分は切った牌が一覧の
    /// どこにあったかで決める（`handOverviewTileCenter`。会長指摘 2026-09-13「真ん中ではなく端っこから」）ので、
    /// ここは位置が分からないときの既定値＝**ツモ牌の位置（右端）**。一覧の牌は河と同じ大きさなので、
    /// 飛ぶ間に大きさを変えなくてよい。
    public func discardOrigin(seat: Int) -> CGPoint {
        switch seat {
        case 2: return project(u: 0.5, v: 0.07).point
        case 3: return project(u: 0.05, v: 0.50).point
        case 1: return project(u: 0.95, v: 0.50).point
        default: return handOverviewTileCenter(index: 13, count: 14)
        }
    }

    /// 手牌一覧の `count` 枚中 `index` 枚目（0 始まり。ツモ牌は末尾）の中心。一覧は中央寄せ。
    public func handOverviewTileCenter(index: Int, count: Int) -> CGPoint {
        let o = handOverview
        let n = max(1, count)
        let pitch = o.tileWidth + Self.handOverviewSpacing
        let rowWidth = o.tileWidth * CGFloat(n) + Self.handOverviewSpacing * CGFloat(n - 1)
        let i = CGFloat(min(max(0, index), n - 1))
        return CGPoint(x: o.center.x - rowWidth / 2 + i * pitch + o.tileWidth / 2, y: o.center.y)
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
