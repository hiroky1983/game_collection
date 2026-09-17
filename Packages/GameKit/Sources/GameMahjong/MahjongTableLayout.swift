import CoreGraphics
import Foundation
import MahjongTiles

// MARK: - 卓のレイアウト（麻雀刷新 #736 → 長方形 #927）
//
// 卓を真上から見た**縦長の長方形**の幾何だけをここに置く。描画（SwiftUI）は `MahjongView` が持ち、
// ここは純関数なのでテストで縛れる。
//
// #736〜#926 は斜め上から見る台形（`docs/ui-review/mahjong-3d/mock-v12.png`）だったが、会長 QA
// （2026-09-15「台形じゃなくて縦長の長方形にできん？ 真ん中のセクションが見えんわ」#927）で平行投影にした。
// `project(u:v:)` は残し、縮尺は全域 1（`Projected.scale` は互換のために残す）。立て牌の側面だけは
// 「立っている」見た目を残すため固定の drop/lean で描く。
//
// 座標系: 卓上の位置を (u, v) で表す。u は左→右（0〜1、幅で写す）、v は奥→手前（0〜1、高さで写す）。
// 河・立て牌・副露・中央パネルの置き場をすべてこの写像で決める
// （要素どうしの重なりは `MahjongTableLayoutTests` が機械的に検査する）。

public struct MahjongTableLayout: Sendable {
    /// 卓（木枠を含む）の矩形。`aspect`（縦長）を想定するが、縦横比が違っても壊れない。
    /// iPad では卓そのものが大きくなる（`MahjongView.mahjongTable` が幅いっぱい）ので、牌の寸法は
    /// すべて卓の幅からの比で決め、`AdaptiveLayout.elementScale` は掛けない（二重拡大になる）。
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    /// 卓の縦横比（高さ ÷ 幅）。iPhone の縦画面の余りを卓に使う（#927）。
    public static let aspect: CGFloat = 1.2

    // MARK: 寸法の比率（幅 393pt を 1 とした値）
    //
    // 横は「上家の副露の列（＝壁の列）→ 上家の河 3 列 → 立直棒 → 中央パネル → 立直棒 → 下家の河 3 列 → 下家の副露の列」
    // で使い切り（余白 1〜2pt）、縦は「対面の壁 → 対面の河 3 行 → 左右の河 6 枚 → 自分の河 3 行 → 手牌一覧」に
    // 10〜12pt ずつの余白がある。数字を動かすときは `MahjongTableLayoutTests` と
    // `docs/ui-review/927-mahjong-rectangle/` の描画で確かめること。

    /// 木枠の太さ（幅に対する比）: 左右・下は 12/393、上は 16/393。
    static let frameSide: CGFloat = 12 / 393
    static let frameTop: CGFloat = 16 / 393
    static let frameBottom: CGFloat = 12 / 393
    /// 河の牌の基準幅（幅 393pt に対する比。#918 で 21 → 25）。iPhone 17（卓幅 361pt）で 21.6pt。
    /// 平行投影なのでどの家・どの行でも同じ大きさ。
    static let riverTileWidthRatio: CGFloat = 25 / 393
    /// 寝かせた牌の縦横比（`MahjongTileView` の河と同じ）。
    public static let tileAspect: CGFloat = 1.38
    /// 1 行の枚数（実物と同じ 6 枚）。
    public static let riverPerRow = 6
    /// 立て牌の側面の高さ（幅 393pt のときの pt。卓の幅に比例）。真上からの投影では本来見えないが、
    /// 「立っている」見た目を残すため固定で与える（#927）。
    static let standingHeight: CGFloat = 18
    /// 中央パネルの幅・高さ（幅 393pt に対する比）。横は河の列に挟まれて 90 が上限、縦は余裕があるので 108
    /// （面積は #927 の目安 96×96 より広い）。
    static let centerPanelWidthRatio: CGFloat = 90 / 393
    static let centerPanelHeightRatio: CGFloat = 108 / 393
    /// 中央パネルの v。左右の河の列と左右の立直棒もこの v を中心に置く。
    static let centerPanelV: CGFloat = 0.493

    // MARK: 写像

    public struct Projected: Sendable, Equatable {
        public var x: CGFloat
        public var y: CGFloat
        /// 縮尺。平行投影なので 1（大きさ 0 の卓では 0）。
        public var scale: CGFloat
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    private var feltTop: CGFloat { size.width * Self.frameTop }
    private var feltBottom: CGFloat { size.height - size.width * Self.frameBottom }
    private var feltHeight: CGFloat { feltBottom - feltTop }
    private var feltLeft: CGFloat { size.width * Self.frameSide }
    private var feltWidth: CGFloat { size.width - 2 * size.width * Self.frameSide }
    /// 幅 393pt を 1 とした縮尺（立て牌の側面など、pt で決めた値を卓の幅に合わせる）。
    private var widthScale: CGFloat { size.width / 393 }

    /// 卓上の (u, v) を画面へ。u は幅、v は高さで写す平行投影。
    ///
    /// 大きさ 0 の卓（SwiftUI が最初のレイアウトで渡してくる）で NaN を作らないこと（#874。以前は
    /// 0 ÷ 0 が牌の幅・位置すべてに広がり、幅 393pt 以下の端末で落ちていた）。縮尺は「0 の卓では 0」。
    /// 描画側は `MahjongView.mahjongTable` が一辺 0 以下では中身を作らないので、ここは二重の守り。
    public func project(u: CGFloat, v: CGFloat) -> Projected {
        Projected(x: feltLeft + u * feltWidth, y: feltTop + v * feltHeight, scale: feltWidth > 0 ? 1 : 0)
    }

    /// 高さ z（幅 393pt のときの pt）を持つ点。上へ持ち上げる量は卓の幅に比例。
    public func project(u: CGFloat, v: CGFloat, z: CGFloat) -> CGPoint {
        let g = project(u: u, v: v)
        return CGPoint(x: g.x, y: g.y - z * widthScale)
    }

    // MARK: 卓の面

    /// 木枠（外形の長方形）。a: 奥左, b: 奥右, c: 手前右, d: 手前左。
    public var woodFrame: [CGPoint] {
        [
            CGPoint(x: -2, y: 0),
            CGPoint(x: size.width + 2, y: 0),
            CGPoint(x: size.width + 2, y: size.height),
            CGPoint(x: -2, y: size.height),
        ]
    }

    /// フェルト（緑の長方形）。
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
    /// 6 枚で折り返し、各家から見て左から右へ並ぶ。牌は隙間なく密着させる（歩幅＝牌の寸法の比）。
    ///
    /// 置き場（#927。幅 393pt・高さ 471.6pt のとき）:
    /// - 対面の 1 行目 v 0.271（3 行目の上端が対面の壁の足元の 10pt 下）
    /// - 左右の列は中央パネルの v を中心に 6 枚（対面・自分の河と 12pt 離れる）。列の u は 0.685 / 0.315
    ///   （1 列目の内側の縁とパネルの隙間 7pt に立直棒が入り、3 列目の外側の縁が壁の列の副露に 1pt で届かない）
    /// - 自分の 1 行目 v 0.715（3 行目の下端が手牌一覧の 12pt 上）
    public struct Slot: Sendable, Equatable {
        public var center: CGPoint
        public var scale: CGFloat
        /// 度。各家の向き（自分 0、下家 -90、対面 180、上家 90）。
        public var rotation: Double
    }

    /// 河の牌の幅。フェルトの幅に比を掛ける。u の歩幅も同じ比なので、隣の牌と隙間なく密着する。
    public var riverTileWidth: CGFloat { feltWidth * Self.riverTileWidthRatio }
    /// 河の牌の高さ（寝かせた牌の長辺）。
    private var riverTileHeight: CGFloat { riverTileWidth * Self.tileAspect }

    /// 牌の幅・高さぶんの u / v の歩幅。
    private var stepU: CGFloat { Self.riverTileWidthRatio }
    private var stepRowU: CGFloat { stepU * Self.tileAspect }
    private var stepRowV: CGFloat { feltHeight > 0 ? riverTileHeight / feltHeight : 0 }
    private var stepSideV: CGFloat { feltHeight > 0 ? riverTileWidth / feltHeight : 0 }

    /// 対面・自分の河の 1 行目の v。
    static let farRiverV: CGFloat = 0.271
    static let ownRiverV: CGFloat = 0.715
    /// 左右の河の 1 列目の u（下家。上家は左右対称）。
    static let sideRiverU: CGFloat = 0.685

    public func riverSlot(seat: Int, index: Int) -> Slot {
        let col = CGFloat(index % Self.riverPerRow)
        let row = CGFloat(index / Self.riverPerRow)
        let g: Projected
        let rotation: Double
        // 左右の列は 6 枚をパネルの v を中心に置く（先頭は中心から 2.5 枚ぶん）
        let sideStart = Self.centerPanelV - 2.5 * stepSideV
        switch seat {
        case 2: // 対面: 右から左へ（対面から見て左→右）、奥へ積む
            g = project(u: 0.5 + (5 - col - 2.5) * stepU, v: Self.farRiverV - row * stepRowV)
            rotation = 180
        case 3: // 上家（左）: 奥から手前へ、列は右（中央側）から左へ
            g = project(u: 1 - Self.sideRiverU - row * stepRowU, v: sideStart + col * stepSideV)
            rotation = 90
        case 1: // 下家（右）: 手前から奥へ、列は左（中央側）から右へ
            g = project(u: Self.sideRiverU + row * stepRowU, v: sideStart + (5 - col) * stepSideV)
            rotation = -90
        default: // 自分: 左から右へ、手前へ積む
            g = project(u: 0.5 + (col - 2.5) * stepU, v: Self.ownRiverV + row * stepRowV)
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

    /// 上家・下家の壁の 1 枚ぶんの v の歩幅。対面の壁の 1 枚ぶんの u（0.05）と画面上でほぼ同じ長さ。
    static let sideWallStepV: CGFloat = 0.0416
    /// 上家・下家の壁の列の u（上面の外側の縁）と上面の幅。
    static let sideWallU: CGFloat = 0.02
    static let sideWallWidthU: CGFloat = 0.032
    /// 対面の壁の 1 枚ぶんの u と、壁の右端（画面）の u。14 枚で 0.15〜0.85。
    static let farWallStepU: CGFloat = 0.05
    static let farWallRightU: CGFloat = 0.85

    /// CPU の手牌 `index` 枚目（0 が奥／左端）。**どの家も片側の端に固定**して枚数ぶん縮む: 下家は手前の端
    /// （v 0.88）、上家は奥の端（v 0.13）、対面は画面の右端（u 0.85。14 枚で 0.15〜0.85 に中央寄せしていた頃と
    /// 同じ右端。#960）。副露で減った分だけ、その家の右側＝下家は奥・上家は手前・対面は画面の左が空き、
    /// そこへ河と同じ大きさの副露を置く（会長指摘 2026-09-13「左右の鳴き牌の大きさが直っていない」、
    /// 2026-09-15「対面の副露も手牌の横に」）。対面の足元は v 0.066、上面はフェルトの奥の縁に接する。
    /// 側面（drop）・傾き（lean）・膨らみ（bulge）は平行投影でも立って見えるよう固定値（卓の幅に比例）。
    /// 描く側は **index の昇順**で渡す（奥から手前）。
    public func handBlock(seat: Int, index: Int, count: Int) -> (MahjongTileBlockGeometry, MahjongTileBlockFacing) {
        let h = Self.standingHeight
        let sc = widthScale
        switch seat {
        case 2:
            let du = Self.farWallStepU, tv: CGFloat = 0.026
            let u0 = Self.farWallRightU - (CGFloat(count) - CGFloat(index)) * du
            let v0: CGFloat = 0.04
            let g = MahjongTileBlockGeometry(
                a: project(u: u0, v: v0, z: h), b: project(u: u0 + du, v: v0, z: h),
                c: project(u: u0 + du, v: v0 + tv, z: h), d: project(u: u0, v: v0 + tv, z: h),
                drop: h * sc, lean: 0, bulge: 2.2 * sc)
            return (g, .viewer)
        default:
            let tu = Self.sideWallWidthU, dv = Self.sideWallStepV
            let start: CGFloat = seat == 1 ? 0.88 - CGFloat(count) * dv : 0.13
            let v0 = start + CGFloat(index) * dv
            let u0: CGFloat = seat == 3 ? Self.sideWallU : 1 - Self.sideWallU - tu
            let g = MahjongTileBlockGeometry(
                a: project(u: u0, v: v0, z: h), b: project(u: u0 + tu, v: v0, z: h),
                c: project(u: u0 + tu, v: v0 + dv, z: h), d: project(u: u0, v: v0 + dv, z: h),
                drop: h * sc, lean: 8 * sc, bulge: 5.5 * sc)
            return (g, seat == 3 ? .centerOnRight : .centerOnLeft)
        }
    }

    // MARK: 副露・立直棒・中央・ドラ

    /// 副露の置き場の基準点。実物どおり**各家から見て右側**: 下家（右）＝右上の角、上家（左）＝左下の角、
    /// 自分＝手牌一覧の行の右端、対面＝対面の壁の行の左端（画面）。
    ///
    /// 置き方は家ごとに違う（会長 QA「鳴きが多くなると重なる」）:
    /// - 上家・下家: 立て牌の壁と同じ列で、副露のぶん短くなった壁の空いた端（下家は奥、上家は手前）から
    ///   **1 列** に並べる（`handBlock` が壁を片側に寄せる）。河と同じ大きさ。1 枚ずつの置き場は `sideMeldSlot`。
    ///   ここの `Slot` は列の先端。
    /// - 自分・対面: **手牌の行の横**に 1 行で並べる（#960。会長 QA 2026-09-15「鳴いた牌が重なってる。
    ///   並べてる手持ちの横に並べられないの？」）。鳴くたびに手牌が 3 枚減って右側（対面は画面の左側）が
    ///   空くので、そこへ右詰め（対面は左詰め）で置く。置き場は `inlineMelds`、ここの `Slot` はその行の
    ///   手牌から遠い端（自分は右下、対面は左上）。以前の「一覧の上の段に積む」「左上の角から下へ積む」は
    ///   3 組で河に重なった（#918 で河を大きくした代償）。
    public func meldSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: Self.farMeldRowLeftU, v: 0); rotation = 180
        case 1: g = project(u: Self.sideMeldU(seat: 1), v: Self.sideMeldStartV(seat: 1)); rotation = -90
        case 3: g = project(u: Self.sideMeldU(seat: 3), v: Self.sideMeldStartV(seat: 3)); rotation = 90
        default:
            let o = handOverview
            g = Projected(x: o.center.x + o.width / 2, y: o.center.y + o.tileWidth * Self.tileAspect / 2, scale: 1)
            rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 副露の牌の基準の幅（縮尺 1 のとき）。4 家とも河と同じ（会長指摘 2026-09-13。対面は #960 で 0.9 倍から
    /// 河と同じに）。自分・対面は行に収まらないときだけ `inlineMelds` が、上家・下家は列に収まらないときだけ
    /// `sideMeldTileWidth` が縮める。
    public func meldTileWidth(seat: Int) -> CGFloat {
        riverTileWidth
    }

    /// 副露の組と組の間隔（pt）。上家・下家の 1 列と、自分・対面の 1 行（`MahjongMeldRow` の `groupSpacing`）。
    public static let meldGroupSpacing: CGFloat = 3
    /// 副露の 1 組の中の牌の間隔（pt）と、寝かせた副露の牌の縦横比。`MahjongMeldRow` の描き方（間隔 1・高さ 1.34 倍）
    /// に合わせる。`inlineMelds` の矩形はこの値で組の幅・高さを出す。
    public static let meldTileSpacing: CGFloat = 1
    public static let meldTileAspect: CGFloat = 1.34

    // MARK: 手牌の行の横に並べる副露（自分・対面。#960）

    /// 手牌と副露の間（河の牌の幅に対する比）。
    public static let inlineMeldGapRatio: CGFloat = 0.5
    /// 対面の副露の行の左端（画面）の u。上家の壁（v 0.13〜）より奥の帯なので木枠の際（左右の壁と同じ u 0.02）
    /// まで使える。右端は対面の壁の左端（`handBlock`。副露で減った分だけ右へ寄る）から隙間ぶん手前。
    static let farMeldRowLeftU: CGFloat = 0.02

    /// 自分・対面の副露の行。
    public struct InlineMelds: Sendable, Equatable {
        /// 副露の牌の幅。基準は河と同じ（`meldTileWidth(seat:)`）で、行に収まらないときだけ縮む（手牌は縮めない）。
        public var tileWidth: CGFloat
        /// 組ごとの矩形。`meldSizes` と同じ順（0 組目が手牌に最も近い）。
        public var groupRects: [CGRect]
        /// 行全体（全組）の矩形。副露が無ければ幅 0（描画は `MahjongTableView` が省く）。
        public var frame: CGRect
        /// 度。自分 0、対面 180（対面の手牌と同じく上下逆）。
        public var rotation: Double
    }

    /// 自分（seat 0）・対面（seat 2）の副露を手牌の行の横に 1 行で並べた置き場（#960）。
    ///
    /// - 自分: 手牌一覧（`handOverview`。左詰め）の右、行の右端に右詰め。下端は手牌の下端に揃える。
    /// - 対面: 壁（`handBlock`。右端固定）の左、行の左端（`farMeldRowLeftU`）に左詰め。上端はフェルトの奥の辺の
    ///   1pt 下（寝かせた牌は立て牌の見た目より少し高いので、壁の足元に揃えると木枠に掛かる）。
    ///
    /// 幅の勘定は `MahjongMeldRow` の描き方どおり: 組の幅 = 枚数 × 牌幅 + (枚数 − 1) × `meldTileSpacing`、
    /// 組の間は `meldGroupSpacing`。手牌との隙間（`inlineMeldGapRatio` × 河の牌の幅）を引いた残りに収まらなければ、
    /// 牌幅だけを縮めて収める（iPhone SE で手牌 4 枚 + カン 3 組 12 枚でも 1 行）。
    /// `handCount` は手牌の枚数（ツモ牌を含む）。大きさ 0 の卓では全部 0（#874）。
    public func inlineMelds(seat: Int, handCount: Int, meldSizes: [Int]) -> InlineMelds {
        let sizes = meldSizes.map { max(0, $0) }
        let rotation: Double = seat == 2 ? 180 : 0
        let tiles = CGFloat(sizes.reduce(0, +))
        let fixed = CGFloat(sizes.reduce(0) { $0 + max(0, $1 - 1) }) * Self.meldTileSpacing
            + CGFloat(max(0, sizes.count - 1)) * Self.meldGroupSpacing
        let gap = riverTileWidth * Self.inlineMeldGapRatio
        let n = CGFloat(max(0, handCount))
        // 行の範囲と、手牌が占める幅
        let rowLeft: CGFloat, rowRight: CGFloat, handWidth: CGFloat, edgeY: CGFloat
        if seat == 2 {
            rowLeft = project(u: Self.farMeldRowLeftU, v: 0).x
            rowRight = project(u: Self.farWallRightU, v: 0).x
            handWidth = n * Self.farWallStepU * feltWidth
            edgeY = feltTop + 1
        } else {
            let o = handOverview
            rowLeft = o.center.x - o.width / 2
            rowRight = o.center.x + o.width / 2
            handWidth = n > 0 ? n * o.tileWidth + (n - 1) * Self.handOverviewSpacing : 0
            edgeY = o.center.y + o.tileWidth * Self.tileAspect / 2
        }
        let available = max(0, rowRight - rowLeft - handWidth - gap)
        let base = meldTileWidth(seat: seat)
        var w = base
        if tiles > 0, tiles * base + fixed > available {
            w = max(0, (available - fixed) / tiles)
        }
        let h = w * Self.meldTileAspect
        let total = tiles * w + fixed
        // 組の矩形。自分は右端から左へ（0 組目が手牌に最も近い＝左）、対面は左端から右へ（0 組目が壁に最も近い＝右）
        var rects: [CGRect] = []
        var cursor: CGFloat = seat == 2 ? rowLeft + total : rowRight - total
        let y = seat == 2 ? edgeY : edgeY - h
        for size in sizes {
            let gw = CGFloat(size) * w + CGFloat(max(0, size - 1)) * Self.meldTileSpacing
            if seat == 2 {
                cursor -= gw
                rects.append(CGRect(x: cursor, y: y, width: gw, height: h))
                cursor -= Self.meldGroupSpacing
            } else {
                rects.append(CGRect(x: cursor, y: y, width: gw, height: h))
                cursor += gw + Self.meldGroupSpacing
            }
        }
        let frame = sizes.isEmpty
            ? CGRect(x: seat == 2 ? rowLeft : rowRight, y: y, width: 0, height: h)
            : CGRect(x: seat == 2 ? rowLeft : rowRight - total, y: y, width: total, height: h)
        return InlineMelds(tileWidth: w, groupRects: rects, frame: frame, rotation: rotation)
    }

    /// 上家・下家の副露の列の u（壁の列に揃える。下家の壁は u 0.948〜、上家は 0.02〜）。
    /// 0.953 は横向きの牌（河の牌の高さぶん）の外側の縁が木枠に 1pt で掛からない限界。
    static func sideMeldU(seat: Int) -> CGFloat { seat == 1 ? 0.953 : 0.047 }
    /// 列の先端の v。下家は奥の縁ぎりぎり（牌の縁がフェルトの奥の辺に掛からない）、
    /// 上家は手牌一覧（v 0.961、上端はその 16pt ほど上）に触れない位置。
    static func sideMeldStartV(seat: Int) -> CGFloat { seat == 1 ? 0.035 : 0.885 }

    /// 上家・下家の副露と壁の間（pt）。
    static let sideMeldWallClearance: CGFloat = 1

    /// 上家・下家の副露の牌の幅。基準は河と同じ（`meldTileWidth(seat:)`）で、`meldSizes` の全組が列の先端から
    /// 壁の手前までに収まらないときだけ縮める（#1065。河を 2 割大きくした #918 以降、3 組で壁の上面に 7〜9pt 掛かっていた）。
    /// 壁は組数から決まるツモ番の枚数（`14 − 3 × 組数`。最も長い）で取るので、手番ごとに大きさが揺れない。
    /// 大きさ 0 の卓では 0（#874）。
    public func sideMeldTileWidth(seat: Int, meldSizes: [Int]) -> CGFloat {
        let sizes = meldSizes.map { max(0, $0) }
        let tiles = CGFloat(sizes.reduce(0, +))
        let base = meldTileWidth(seat: seat)
        guard tiles > 0 else { return base }
        let fixed = CGFloat(max(0, sizes.count - 1)) * Self.meldGroupSpacing
        let wallCount = max(1, 14 - 3 * sizes.count)
        let available: CGFloat
        if seat == 1 {
            // 下家: 先端（奥）から、手前に寄せた壁の最も奥の牌の上面まで
            let lead = project(u: Self.sideMeldU(seat: 1), v: Self.sideMeldStartV(seat: 1)).y - base / 2
            let wall = handBlock(seat: 1, index: 0, count: wallCount).0
            available = min(wall.a.y, wall.b.y, wall.c.y, wall.d.y) - Self.sideMeldWallClearance - lead
        } else {
            // 上家: 先端（手前）から、奥に寄せた壁の最も手前の牌の足元まで
            let lead = project(u: Self.sideMeldU(seat: 3), v: Self.sideMeldStartV(seat: 3)).y + base / 2
            let wall = handBlock(seat: 3, index: wallCount - 1, count: wallCount).0
            available = lead - (max(wall.a.y, wall.b.y, wall.c.y, wall.d.y) + wall.drop) - Self.sideMeldWallClearance
        }
        guard tiles * base + fixed > available else { return base }
        return max(0, (available - fixed) / tiles)
    }

    /// 上家・下家の副露 1 枚の置き場。`ordinal` は全組を通した通し番号（0 が列の先端）、`gaps` は
    /// その前にある組の区切りの数。壁と同じ列（u 一定）に沿って、下家は奥から手前へ、上家は手前から奥へ、
    /// 牌の幅ぶんずつ進める。`tileWidth` は `sideMeldTileWidth` の値（省略時は河と同じ）で、縮めても列の先端の
    /// 縁は動かさない。
    public func sideMeldSlot(seat: Int, ordinal: Int, gaps: Int, tileWidth: CGFloat? = nil) -> Slot {
        let u = Self.sideMeldU(seat: seat)
        let dir: CGFloat = seat == 1 ? 1 : -1
        let head = project(u: u, v: Self.sideMeldStartV(seat: seat))
        let w = tileWidth ?? riverTileWidth
        let advance = (w - riverTileWidth) / 2 + w * CGFloat(max(0, ordinal))
            + CGFloat(max(0, gaps)) * Self.meldGroupSpacing
        let center = CGPoint(x: head.x, y: head.y + dir * advance)
        return Slot(center: center, scale: head.scale, rotation: seat == 1 ? -90 : 90)
    }

    /// 上家・下家の副露 1 枚が画面上で占める矩形（横向きなので幅が牌の高さ）。
    public func sideMeldRect(seat: Int, ordinal: Int, gaps: Int, tileWidth: CGFloat? = nil) -> CGRect {
        let slot = sideMeldSlot(seat: seat, ordinal: ordinal, gaps: gaps, tileWidth: tileWidth)
        let w = (tileWidth ?? riverTileWidth) * slot.scale
        let h = w * Self.tileAspect
        return CGRect(x: slot.center.x - h / 2, y: slot.center.y - w / 2, width: h, height: w)
    }

    /// `groups` 組・合計 `count` 枚の副露を、重なりの検査用に矩形の列で返す。上家・下家は 1 枚ずつ、
    /// 自分・対面は 1 組ずつ（`inlineMelds`。手牌はツモ番の `14 − 3 × groups` 枚として最も長い場合を取る）。
    /// 組の区切りは 3 枚ごとにあるとみなし、余った枚数はカンとして先頭の組から 1 枚ずつ足す。
    public func meldTileRects(seat: Int, groups: Int, tiles count: Int) -> [CGRect] {
        guard seat == 1 || seat == 3 else {
            return inlineMelds(seat: seat, handCount: 14 - 3 * groups, meldSizes: Self.meldSizes(groups: groups, tiles: count)).groupRects
        }
        let w = sideMeldTileWidth(seat: seat, meldSizes: Self.meldSizes(groups: groups, tiles: count))
        return (0..<count).map { sideMeldRect(seat: seat, ordinal: $0, gaps: min($0 / 3, max(0, groups - 1)), tileWidth: w) }
    }

    /// `groups` 組に `count` 枚を配る（3 枚ずつ、余りは先頭からカンに）。
    static func meldSizes(groups: Int, tiles count: Int) -> [Int] {
        let g = max(0, groups)
        guard g > 0 else { return [] }
        var sizes = Array(repeating: 3, count: g)
        var extra = count - 3 * g
        for i in 0..<g where extra > 0 { sizes[i] = 4; extra -= 1 }
        return sizes
    }

    /// `groups` 組・合計 `count` 枚の副露が占める画面上の矩形（重なりの検査用）。上家・下家は 1 枚ずつの矩形
    /// （`meldTileRects`）の外接矩形、自分・対面は行全体（`inlineMelds.frame`）。
    public func meldRegion(seat: Int, groups: Int, tiles count: Int) -> CGRect {
        if seat == 1 || seat == 3 {
            return meldTileRects(seat: seat, groups: groups, tiles: count).reduce(CGRect.null) { $0.union($1) }
        }
        return inlineMelds(seat: seat, handCount: 14 - 3 * groups, meldSizes: Self.meldSizes(groups: groups, tiles: count)).frame
    }

    /// 立直棒（各家の河の内側）。対面・自分は河の 1 行目とパネルの間の中央、左右は河の 1 列目とパネルの
    /// 隙間（7pt。棒の太さ 4pt に対して両側 1.5pt）の中央。
    public func riichiStickSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: 0.5, v: 0.339); rotation = 0
        case 3: g = project(u: 0.369, v: Self.centerPanelV); rotation = 90
        case 1: g = project(u: 0.631, v: Self.centerPanelV); rotation = 90
        default: g = project(u: 0.5, v: 0.647); rotation = 0
        }
        return Slot(center: g.point, scale: g.scale, rotation: rotation)
    }

    /// 中央パネル（縦長の長方形。#927 で 70×70 → 90×108/393）。
    public var centerPanel: CGRect {
        let g = project(u: 0.5, v: Self.centerPanelV)
        let w = size.width * Self.centerPanelWidthRatio * g.scale
        let h = size.width * Self.centerPanelHeightRatio * g.scale
        return CGRect(x: g.x - w / 2, y: g.y - h / 2, width: w, height: h)
    }

    /// 打牌が飛び始める点（#738）。CPU はその家の立て牌の列の中ほど。自分は切った牌が一覧の
    /// どこにあったかで決める（`handOverviewTileCenter`。会長指摘 2026-09-13「真ん中ではなく端っこから」）ので、
    /// ここは位置が分からないときの既定値＝**ツモ牌の位置（右端）**。一覧の牌は河と同じ大きさなので、
    /// 飛ぶ間に大きさを変えなくてよい。
    public func discardOrigin(seat: Int) -> CGPoint {
        switch seat {
        case 2: return project(u: 0.5, v: 0.05).point
        case 3: return project(u: 0.05, v: 0.50).point
        case 1: return project(u: 0.95, v: 0.50).point
        default: return handOverviewTileCenter(index: 13, count: 14)
        }
    }

    /// 手牌一覧の `count` 枚中 `index` 枚目（0 始まり。ツモ牌は末尾）の中心。一覧は**左詰め**（#960。以前は
    /// 中央寄せで、ツモのたびに 13 枚が半枚ぶん左へずれていた。左詰めなら 1 枚目の位置が変わらず、
    /// 鳴いて減った右側に副露を置ける）。14 枚のときは行を使い切るので中央寄せと同じ位置。
    public func handOverviewTileCenter(index: Int, count: Int) -> CGPoint {
        let o = handOverview
        let n = max(1, count)
        let pitch = o.tileWidth + Self.handOverviewSpacing
        let i = CGFloat(min(max(0, index), n - 1))
        return CGPoint(x: o.center.x - o.width / 2 + i * pitch + o.tileWidth / 2, y: o.center.y)
    }

    /// 手牌一覧の牌どうしの間隔（pt）。
    public static let handOverviewSpacing: CGFloat = 2

    /// 卓上の手牌一覧（`handOverviewOnTable`）の中心・幅・牌の幅。フェルトの手前の縁、中央。
    /// 牌は**河の牌と同じ幅**（会長指摘 2026-09-13。以前は幅 50% に 14 枚を詰めて 10pt ほどだった）。
    /// 幅は 14 枚（手牌 13 + ツモ）が収まる分。牌は左詰めで、自分の副露（`inlineMelds(seat: 0)`）は
    /// 鳴いて空いた右側に右詰めで並ぶ（#960）。
    public var handOverview: (center: CGPoint, width: CGFloat, tileWidth: CGFloat) {
        let g = project(u: 0.5, v: 0.961)   // 下端がフェルトの手前の辺の 1pt 上
        let tile = riverTileWidth * g.scale
        return (g.point, tile * 14 + Self.handOverviewSpacing * 13, tile)
    }
}
