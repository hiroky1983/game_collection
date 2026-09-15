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

    /// CPU の手牌 `index` 枚目（0 が奥／左端）。対面は `count` 枚を中央寄せ（足元 v 0.066。上面はフェルトの
    /// 奥の縁に接する）、上家・下家は**下家は手前の端（v 0.88）、上家は奥の端（v 0.13）に固定**して枚数ぶん縮む
    /// （副露で減った分だけ、その家の右側＝下家は奥・上家は手前の端が空き、そこへ河と同じ大きさの
    /// 副露を置く。会長指摘 2026-09-13「左右の鳴き牌の大きさが直っていない」）。
    /// 側面（drop）・傾き（lean）・膨らみ（bulge）は平行投影でも立って見えるよう固定値（卓の幅に比例）。
    /// 描く側は **index の昇順**で渡す（奥から手前）。
    public func handBlock(seat: Int, index: Int, count: Int) -> (MahjongTileBlockGeometry, MahjongTileBlockFacing) {
        let h = Self.standingHeight
        let sc = widthScale
        switch seat {
        case 2:
            let du: CGFloat = 0.05, tv: CGFloat = 0.026
            let u0 = 0.5 + (CGFloat(index) - CGFloat(count) / 2) * du
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

    /// 副露の置き場。実物どおり**各家から見て右側**の角: 対面＝画面左上、下家（右）＝右上、
    /// 上家（左）＝左下、自分＝右下。`Slot.center` はその角に寄せる基準点。
    ///
    /// 置き方は家ごとに違う（会長 QA「鳴きが多くなると重なる」）:
    /// - 対面: 左上の角から **1 組ずつ行を分けて下へ** 積む（横に伸ばすと対面の壁の下に潜る）。
    ///   上家の壁の右（u 0.08）・対面の壁の足元の下（v 0.103）。カン（4 枚幅）の右端は対面の河の奥の行に接する。
    /// - 上家・下家: 立て牌の壁と同じ列で、副露のぶん短くなった壁の空いた端（下家は奥、上家は手前）から
    ///   **1 列** に並べる（`handBlock` が壁を片側に寄せる）。河と同じ大きさ。1 枚ずつの置き場は `sideMeldSlot`。
    ///   ここの `Slot` は列の先端。
    /// - 自分: 手牌一覧（`handOverview`）の **上の段**、右寄りに 1 組ずつ上へ積む。一覧が河と同じ
    ///   大きさになって手前の辺をほぼ使い切る（会長指摘 2026-09-13）ので、角には置けない。
    ///   右端 u 0.898 は下家の立て牌（u 0.948〜、足元が中央へ寄る）に触れない位置、左端は 3 枚幅なら自分の河の
    ///   右端より右。3 組の下端が一覧の 3.5pt 上（v 0.874）。**カン（4 枚幅）は自分の河の右端の列に
    ///   約 17pt 掛かる**（#918 で河を大きくした代償。実戦でまれなのでテストはカン無しの 3 組で縛る）。
    public func meldSlot(seat: Int) -> Slot {
        let g: Projected
        let rotation: Double
        switch seat {
        case 2: g = project(u: 0.08, v: 0.103); rotation = 180
        case 1: g = project(u: Self.sideMeldU(seat: 1), v: Self.sideMeldStartV(seat: 1)); rotation = -90
        case 3: g = project(u: Self.sideMeldU(seat: 3), v: Self.sideMeldStartV(seat: 3)); rotation = 90
        default: g = project(u: 0.898, v: 0.874); rotation = 0
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
    /// 0.953 は横向きの牌（河の牌の高さぶん）の外側の縁が木枠に 1pt で掛からない限界。
    static func sideMeldU(seat: Int) -> CGFloat { seat == 1 ? 0.953 : 0.047 }
    /// 列の先端の v。下家は奥の縁ぎりぎり（牌の縁がフェルトの奥の辺に掛からない）、
    /// 上家は手牌一覧（v 0.961、上端はその 16pt ほど上）に触れない位置。
    static func sideMeldStartV(seat: Int) -> CGFloat { seat == 1 ? 0.035 : 0.885 }

    /// 上家・下家の副露 1 枚の置き場。`ordinal` は全組を通した通し番号（0 が列の先端）、`gaps` は
    /// その前にある組の区切りの数。壁と同じ列（u 一定）に沿って、下家は奥から手前へ、上家は手前から奥へ、
    /// 牌の幅ぶんずつ進める。
    public func sideMeldSlot(seat: Int, ordinal: Int, gaps: Int) -> Slot {
        let u = Self.sideMeldU(seat: seat)
        let dir: CGFloat = seat == 1 ? 1 : -1
        let head = project(u: u, v: Self.sideMeldStartV(seat: seat))
        let advance = riverTileWidth * CGFloat(max(0, ordinal)) + CGFloat(max(0, gaps)) * Self.meldGroupSpacing
        let center = CGPoint(x: head.x, y: head.y + dir * advance)
        return Slot(center: center, scale: head.scale, rotation: seat == 1 ? -90 : 90)
    }

    /// 上家・下家の副露 1 枚が画面上で占める矩形（横向きなので幅が牌の高さ）。
    public func sideMeldRect(seat: Int, ordinal: Int, gaps: Int) -> CGRect {
        let slot = sideMeldSlot(seat: seat, ordinal: ordinal, gaps: gaps)
        let w = riverTileWidth * slot.scale
        let h = w * Self.tileAspect
        return CGRect(x: slot.center.x - h / 2, y: slot.center.y - w / 2, width: h, height: w)
    }

    /// `groups` 組・合計 `count` 枚の副露を、重なりの検査用に矩形の列で返す。対面・自分は `meldRegion`
    /// 1 つ、上家・下家は 1 枚ずつ。
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
    /// 幅は行が角へ寄る（自分は右寄せ、対面は左寄せ）ので、カンが混じる（`count > groups × 3`）ときだけ
    /// 4 枚ぶん、それ以外は 3 枚ぶん。
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
        let perRow: CGFloat = count > max(1, groups) * 3 ? 4 : 3
        if seat == 2 { // 左上から下へ、1 組 1 行
            return CGRect(x: c.x, y: c.y - h / 2, width: w * perRow, height: stack)
        }
        // 自分: 右下から上へ、1 組 1 行
        return CGRect(x: c.x - w * perRow, y: c.y + h / 2 - stack, width: w * perRow, height: stack)
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
        let g = project(u: 0.5, v: 0.961)   // 下端がフェルトの手前の辺の 1pt 上
        let tile = riverTileWidth * g.scale
        return (g.point, tile * 14 + Self.handOverviewSpacing * 13, tile)
    }
}
