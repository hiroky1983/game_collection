import Testing
import Foundation
import CoreGraphics
@testable import GameMahjong

/// 卓のレイアウト（#736、長方形 #927）。絵は測れないので、重なり・密着・収まりだけを機械的に縛る。
@Suite("卓のレイアウト")
struct MahjongTableLayoutTests {
    static let phone = MahjongTableLayout(size: CGSize(width: 393, height: 393 * MahjongTableLayout.aspect))
    static let pad = MahjongTableLayout(size: CGSize(width: 700, height: 700 * MahjongTableLayout.aspect))
    /// iPhone 17 の卓幅（画面 393 − 左右の余白 16 × 2）。
    static let phone17 = MahjongTableLayout(size: CGSize(width: 361, height: 361 * MahjongTableLayout.aspect))

    @Test("大きさ 0 の卓でも NaN を作らない（SwiftUI の最初のレイアウトは 0 で来る。開発版 v1.1.5 のクラッシュ）")
    func zeroSizeProducesFiniteValues() {
        let layout = MahjongTableLayout(size: .zero)
        var values: [CGFloat] = [layout.riverTileWidth, layout.handOverview.width, layout.handOverview.tileWidth,
                                 layout.handOverview.center.x, layout.handOverview.center.y]
        for seat in 0..<4 {
            for index in 0..<18 {
                let slot = layout.riverSlot(seat: seat, index: index)
                values += [slot.center.x, slot.center.y, slot.scale]
                let (block, _) = layout.handBlock(seat: seat, index: index % 13, count: 13)
                values += [block.a.x, block.a.y, block.c.x, block.c.y, block.drop, block.lean, block.bulge]
            }
            let meld = layout.meldSlot(seat: seat)
            values += [meld.center.x, meld.center.y, meld.scale, layout.meldTileWidth(seat: seat)]
            let stick = layout.riichiStickSlot(seat: seat)
            values += [stick.center.x, stick.center.y, stick.scale]
            values += [layout.discardOrigin(seat: seat).x, layout.discardOrigin(seat: seat).y]
            values += layout.meldTileRects(seat: seat, groups: 2, tiles: 6)
                .flatMap { [$0.minX, $0.minY, $0.width, $0.height] }
        }
        for seat in [0, 2] {
            let row = layout.inlineMelds(seat: seat, handCount: 4, meldSizes: [4, 3, 3])
            values += [row.tileWidth, row.frame.minX, row.frame.minY, row.frame.width, row.frame.height]
            values += row.groupRects.flatMap { [$0.minX, $0.minY, $0.width, $0.height] }
            values += [layout.handOverviewTileCenter(index: 0, count: 4).x]
        }
        values += [layout.centerPanel.minX, layout.centerPanel.minY, layout.centerPanel.width, layout.centerPanel.height]
        let nonFinite = values.filter { !$0.isFinite }
        #expect(nonFinite.isEmpty, "0 ÷ 0 の NaN が混ざっている: \(nonFinite.count) 件")
        // 寸法（幅・高さ・縮尺）は負にならない。座標は原点まわりの引き算で -1 程度になってよい
        let sizes = [layout.riverTileWidth, layout.handOverview.width, layout.handOverview.tileWidth,
                     layout.centerPanel.width, layout.centerPanel.height]
            + (0..<4).flatMap { seat in layout.meldTileRects(seat: seat, groups: 2, tiles: 6).flatMap { [$0.width, $0.height] } }
            + [0, 2].map { layout.inlineMelds(seat: $0, handCount: 4, meldSizes: [4, 3, 3]).tileWidth }
            + (0..<4).flatMap { seat in (0..<18).map { layout.riverSlot(seat: seat, index: $0).scale } }
        let negative = sizes.filter { $0 < 0 }
        #expect(negative.isEmpty, "負の寸法が混ざっている: \(negative)")
    }

    @Test("平行投影: 縮尺は全域 1、v は奥から手前へ y が増え、中央線は幅の中央")
    func projection() {
        let l = Self.phone
        let far = l.project(u: 0.5, v: 0.1), near = l.project(u: 0.5, v: 0.9)
        #expect(far.scale == 1 && near.scale == 1)
        #expect(far.y < near.y)
        #expect(abs(far.x - 393 / 2) < 0.001 && abs(near.x - 393 / 2) < 0.001)
        // 同じ u は奥でも手前でも同じ x（台形の名残が無い）
        #expect(abs(l.project(u: 0.2, v: 0).x - l.project(u: 0.2, v: 1).x) < 0.001)
    }

    @Test("卓は縦長の長方形: 木枠・フェルトの 4 辺が画面に平行で、高さは幅の 1.2 倍（#927）")
    func tableIsUprightRectangle() {
        for l in [Self.phone, Self.pad, Self.phone17] {
            #expect(abs(l.size.height / l.size.width - 1.2) < 0.001)
            for poly in [l.felt, l.woodFrame] {
                #expect(poly.count == 4)
                #expect(abs(poly[0].y - poly[1].y) < 0.001 && abs(poly[2].y - poly[3].y) < 0.001, "上下の辺が水平でない")
                #expect(abs(poly[1].x - poly[2].x) < 0.001 && abs(poly[3].x - poly[0].x) < 0.001, "左右の辺が垂直でない")
                #expect(poly[1].x > poly[0].x && poly[2].y > poly[1].y)
            }
            let f = l.felt
            #expect(f[2].y - f[0].y > f[1].x - f[0].x, "フェルトが縦長でない")
        }
    }

    @Test("河の牌は 4 家・全 3 行とも同じ大きさで、#918 の基準（iPhone 17 で 21.6pt）を下回らない")
    func riverTilesAreUniformAndNotSmaller() {
        let l = Self.phone17
        let base = l.riverTileWidth
        #expect(base >= 21.5, "iPhone 17 の河の牌 \(base)pt")
        for seat in 0..<4 { for i in 0..<18 {
            let r = l.riverRect(seat: seat, index: i)
            let w = seat == 1 || seat == 3 ? r.height : r.width
            #expect(abs(w - base) < 0.001, "seat \(seat) 牌 \(i) の幅 \(w) が基準 \(base) と違う")
        } }
        #expect(abs(l.handOverview.tileWidth - base) < 0.001)
    }

    @Test("中央パネルは 90×108/393 以上で、iPhone 17 では幅 82pt 以上（局・点数の文字が 11pt 以上になる幅）")
    func centerPanelIsLarge() {
        let p = Self.phone17.centerPanel
        #expect(p.width >= 82, "パネルの幅 \(p.width)")
        #expect(p.height >= p.width * 1.15, "パネルが縦長でない: \(p.size)")
        // #918 の 70/393（iPhone 17 で 64pt）より確実に広い
        #expect(p.width > 361 * 70 / 393 * 1.25)
        // 幅の中央にある
        #expect(abs(p.midX - 361 / 2) < 0.001)
    }

    @Test("河の牌は 4 家とも 18 枚（3 行）までフェルトの内側に収まる", arguments: [0, 1, 2, 3])
    func riverInsideFelt(seat: Int) {
        for l in [Self.phone, Self.pad] {
            for i in 0..<18 {
                let r = l.riverRect(seat: seat, index: i)
                for corner in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                               CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                    #expect(l.feltContains(corner), "seat \(seat) 牌 \(i) の角 \(corner) がフェルトの外")
                }
            }
        }
    }

    @Test("河の同じ行の隣どうしは隙間なく密着する（対面・自分は横、左右は縦）", arguments: [0, 1, 2, 3])
    func riverTilesTouch(seat: Int) {
        let l = Self.phone
        for i in 0..<5 {
            let a = l.riverRect(seat: seat, index: i), b = l.riverRect(seat: seat, index: i + 1)
            if seat == 0 || seat == 2 {
                let gap = abs(abs(b.midX - a.midX) - a.width)
                #expect(gap < 0.6, "seat \(seat) \(i)→\(i + 1) の横の隙間 \(gap)")
            } else {
                let gap = abs(abs(b.midY - a.midY) - a.height)
                #expect(gap < 2.5, "seat \(seat) \(i)→\(i + 1) の縦の隙間 \(gap)")
            }
        }
    }

    @Test("河の 4 家は互いに重ならず、中央パネルにも重ならない")
    func riversDoNotOverlap() {
        let l = Self.phone
        var rects: [(Int, Int, CGRect)] = []
        for seat in 0..<4 { for i in 0..<18 { rects.append((seat, i, l.riverRect(seat: seat, index: i))) } }
        let panel = l.centerPanel
        for (seat, i, r) in rects {
            #expect(!r.intersects(panel), "seat \(seat) 牌 \(i) が中央パネルに重なる")
        }
        for (s1, i1, r1) in rects {
            for (s2, i2, r2) in rects where s1 < s2 {
                #expect(!r1.insetBy(dx: 0.5, dy: 0.5).intersects(r2), "seat \(s1) 牌 \(i1) と seat \(s2) 牌 \(i2) が重なる")
            }
        }
    }

    @Test("CPU の立て牌は 13 枚（ツモ番は 14 枚）が奥から手前の順に並び、足元はフェルトの内側", arguments: [13, 14])
    func handBlocks(count: Int) {
        let l = Self.phone
        for seat in [1, 2, 3] {
            var lastY: CGFloat = -1
            for i in 0..<count {
                let (g, facing) = l.handBlock(seat: seat, index: i, count: count)
                #expect(g.drop > 5, "高さが無い")
                // 上面は立っているぶん木枠に掛かってよい。足元（d を drop だけ下ろした点）が内側なら卓上にある
                let foot = CGPoint(x: g.d.x, y: g.d.y + g.drop)
                #expect(l.feltContains(foot), "seat \(seat) 牌 \(i) の足元 \(foot) がフェルトの外")
                switch seat {
                case 2: #expect(facing == .viewer)
                case 3: #expect(facing == .centerOnRight); #expect(g.d.y >= lastY); lastY = g.d.y
                default: #expect(facing == .centerOnLeft); #expect(g.d.y >= lastY); lastY = g.d.y
                }
            }
        }
    }

    @Test("iPad は卓ごと相似に大きくなる（牌の幅は卓の幅に比例、二重に拡大しない）")
    func padScales() {
        #expect(abs(Self.pad.riverTileWidth / Self.pad.size.width - Self.phone.riverTileWidth / Self.phone.size.width) < 0.0001)
        #expect(abs(Self.pad.centerPanel.width / 700 - Self.phone.centerPanel.width / 393) < 0.0001)
    }

    @Test("左右の河は 3 行目までその家の立て牌の壁に届かず、中央パネルとの間に 1 枚ぶんの余白がある")
    func sideRiversStayBetweenWallAndPanel() {
        // 開始位置（u 0.30 / 0.70）を壁側へ戻す回帰を検知する（verifier 指摘）。
        let l = Self.phone
        let panel = l.centerPanel
        let tile = l.riverTileWidth
        // 右の家: 3 行目（index 12〜17）の右端 < 壁の足元の左端
        let rightWall = l.handBlock(seat: 1, index: 6, count: 13).0
        let rightWallFootX = rightWall.a.x
        for i in 12..<18 {
            #expect(l.riverRect(seat: 1, index: i).maxX < rightWallFootX - 2, "右の河 \(i) が壁に届く")
        }
        // 左の家: 3 行目の左端 > 壁の足元の右端
        let leftWall = l.handBlock(seat: 3, index: 6, count: 13).0
        let leftWallFootX = leftWall.b.x
        for i in 12..<18 {
            #expect(l.riverRect(seat: 3, index: i).minX > leftWallFootX + 2, "左の河 \(i) が壁に届く")
        }
        // 1 行目はパネルから 1 枚ぶん以内に寄っている（遠すぎても回帰）
        #expect(l.riverRect(seat: 1, index: 0).minX - panel.maxX < tile * 1.5)
        #expect(panel.minX - l.riverRect(seat: 3, index: 0).maxX < tile * 1.5)
    }

    @Test("左右の河の同じ列は画面上で垂直に並ぶ（台形に引きずられない）", arguments: [1, 3])
    func sideRiverColumnsAreVertical(seat: Int) {
        let l = Self.phone
        for row in 0..<3 {
            let xs = (0..<6).map { l.riverSlot(seat: seat, index: row * 6 + $0).center.x }
            #expect(xs.allSatisfy { abs($0 - xs[0]) < 0.001 }, "seat \(seat) 行 \(row) の x がずれる: \(xs)")
        }
    }

    @Test("立直棒は 4 家とも河の牌にも中央パネルにも重ならない")
    func riichiSticksClearRivers() {
        let l = Self.phone
        for seat in 0..<4 {
            let s = l.riichiStickSlot(seat: seat)
            let len = 46 * s.scale, thick = 4 * s.scale
            let sideways = seat == 1 || seat == 3
            let rect = CGRect(x: s.center.x - (sideways ? thick : len) / 2, y: s.center.y - (sideways ? len : thick) / 2,
                              width: sideways ? thick : len, height: sideways ? len : thick)
            #expect(!rect.intersects(l.centerPanel), "seat \(seat) の立直棒がパネルに重なる")
            for other in 0..<4 { for i in 0..<18 {
                #expect(!rect.intersects(l.riverRect(seat: other, index: i)), "seat \(seat) の立直棒が seat \(other) の河 \(i) に重なる")
            } }
        }
    }

    @Test("CPU の立て牌は下家が手前の端、上家が奥の端、対面が画面の右端に固定され、副露で減った分だけ反対の端が空く")
    func sideWallsAnchor() {
        let l = Self.phone
        // 下家: 最後の 1 枚は枚数によらず同じ位置（手前の端）
        let last13 = l.handBlock(seat: 1, index: 12, count: 13).0
        let last10 = l.handBlock(seat: 1, index: 9, count: 10).0
        #expect(abs(last13.d.y - last10.d.y) < 0.01)
        // 上家: 最初の 1 枚は枚数によらず同じ位置（奥の端）
        let first13 = l.handBlock(seat: 3, index: 0, count: 13).0
        let first10 = l.handBlock(seat: 3, index: 0, count: 10).0
        #expect(abs(first13.a.y - first10.a.y) < 0.01)
        // 対面: 最後の 1 枚（画面の右端）は枚数によらず同じ位置。副露は空いた左側に置く（#960）
        let right13 = l.handBlock(seat: 2, index: 12, count: 13).0
        let right7 = l.handBlock(seat: 2, index: 6, count: 7).0
        #expect(abs(right13.b.x - right7.b.x) < 0.01)
        // 14 枚のときは以前の中央寄せ（u 0.15〜0.85）と同じ位置
        let first14 = l.handBlock(seat: 2, index: 0, count: 14).0
        #expect(abs(first14.a.x - l.project(u: 0.15, v: 0).x) < 0.01)
    }

    @Test("上家・下家の副露は 4 組まで（ツモ番の壁とも）河・パネル・フェルトの縁と重ならない。2 組までは河と同じ幅",
          arguments: [1, 3])
    func sideMeldsFitBesideWall(seat: Int) {
        // 壁の列は「副露 + 残りの壁」で卓の奥行きを使い切る。河（＝副露）と同じ幅のままだと、4 組（13 枚）で
        // 上家の 12 枚目がツモ番の壁に 4〜5pt 掛かる（#926 の頃は 3 組で掛かり、ここを 2 組までに緩めていた）。
        // 収まらないときは `sideMeldTileWidth` が牌を縮めて列に収める（#1065。4 組は鳴けるだけ鳴く東風戦の
        // 通しテストで届く上限）。
        for l in [Self.phone, Self.phone17, Self.pad] {
            #expect(l.meldTileWidth(seat: seat) == l.riverTileWidth)
            for groups in 1...4 {
                let tiles = groups * 3 + 1                // カン 1 つ + ポン／チー（全部カンは想定しない）
                let wallCount = 13 - groups * 3 + 1       // ツモ番（1 枚多い）が最も長い
                let rects = l.meldTileRects(seat: seat, groups: groups, tiles: tiles)
                #expect(rects.count == tiles)
                let width = l.sideMeldTileWidth(seat: seat, meldSizes: MahjongTableLayout.meldSizes(groups: groups, tiles: tiles))
                if groups <= 2 {
                    #expect(width == l.riverTileWidth, "seat \(seat) \(groups) 組は縮めない")
                }
                // 縮めても河の 6 割は残す（牌の絵柄が読める大きさ）
                #expect(width >= l.riverTileWidth * 0.6, "seat \(seat) \(groups) 組の牌の幅 \(width)")
                for (k, r) in rects.enumerated() {
                    for corner in Self.corners(r) {
                        #expect(l.feltContains(corner), "seat \(seat) \(groups) 組 \(k) 枚目: 角 \(corner) がフェルトの外")
                    }
                    #expect(!r.intersects(l.centerPanel))
                    for other in 0..<4 { for i in 0..<18 {
                        #expect(!r.intersects(l.riverRect(seat: other, index: i)),
                                "seat \(seat) \(groups) 組 \(k) 枚目が seat \(other) の河 \(i) に重なる")
                    } }
                    for i in 0..<wallCount {
                        #expect(!r.intersects(Self.wallRect(l, seat: seat, index: i, count: wallCount)),
                                "seat \(seat) \(groups) 組 \(k) 枚目が自分の立て牌 \(i)/\(wallCount) に重なる")
                    }
                    // 隣の牌と密着し（1pt 以内）、重ならない
                    if k > 0 {
                        let prev = rects[k - 1]
                        let gap = seat == 1 ? r.minY - prev.maxY : prev.minY - r.maxY
                        let expected: CGFloat = (k % 3 == 0 && k / 3 <= groups - 1) ? MahjongTableLayout.meldGroupSpacing : 0
                        #expect(abs(gap - expected) < 1, "seat \(seat) \(k) 枚目の隙間 \(gap)")
                    }
                }
            }
        }
    }

    @Test("上家・下家の副露は 4 組すべてカン（16 枚）でも、描画と同じ置き方で壁・河・フェルトの縁と重ならず、列の先端の縁は動かない（#1065）",
          arguments: [1, 3])
    func sideMeldsFitWithFourKans(seat: Int) {
        for l in [Self.phone, Self.phone17, Self.pad] {
            let sizes = [4, 4, 4, 4]
            let width = l.sideMeldTileWidth(seat: seat, meldSizes: sizes)
            #expect(width < l.riverTileWidth, "seat \(seat) 16 枚は縮む")
            #expect(width >= l.riverTileWidth * 0.6, "seat \(seat) 16 枚の牌の幅 \(width)")
            // `MahjongTableView.sideMelds` と同じ: 通し番号と、その牌が属する組の番号（＝前にある区切りの数）
            let groupOfTile = sizes.enumerated().flatMap { gi, n in Array(repeating: gi, count: n) }
            let rects = groupOfTile.enumerated().map { ordinal, gi in
                l.sideMeldRect(seat: seat, ordinal: ordinal, gaps: gi, tileWidth: width)
            }
            let wallCount = 14 - 3 * sizes.count
            for (k, r) in rects.enumerated() {
                for corner in Self.corners(r) {
                    #expect(l.feltContains(corner), "seat \(seat) \(k) 枚目: 角 \(corner) がフェルトの外")
                }
                for other in 0..<4 { for i in 0..<18 {
                    #expect(!r.intersects(l.riverRect(seat: other, index: i)), "seat \(seat) \(k) 枚目が seat \(other) の河 \(i) に重なる")
                } }
                for i in 0..<wallCount {
                    #expect(!r.intersects(Self.wallRect(l, seat: seat, index: i, count: wallCount)),
                            "seat \(seat) \(k) 枚目が自分の立て牌 \(i)/\(wallCount) に重なる")
                }
            }
            // 縮めても先端の縁（下家は奥、上家は手前）は河と同じ幅のときと同じ位置
            let unscaled = l.sideMeldRect(seat: seat, ordinal: 0, gaps: 0)
            if seat == 1 {
                #expect(abs(rects[0].minY - unscaled.minY) < 1e-9)
            } else {
                #expect(abs(rects[0].maxY - unscaled.maxY) < 1e-9)
            }
        }
    }

    @Test("副露は 4 家とも 2 組（6 枚・カン無し）まで、河 18 枚・中央パネル・他家の副露と重ならない")
    func meldRegionsClearEverything() {
        // 上家・下家は 2 組まで（#926）。自分・対面は手牌の行の横（#960。カン入り 3 組は `inlineMeldsClearEverything`）。
        let l = Self.phone
        let pts = (0..<4).map { l.meldSlot(seat: $0).center }
        let mid = CGPoint(x: l.size.width / 2, y: l.size.height / 2)
        // 対面=左上, 下家=右上, 上家=左下, 自分=右下
        #expect(pts[2].x < mid.x && pts[2].y < mid.y)
        #expect(pts[1].x > mid.x && pts[1].y < mid.y)
        #expect(pts[3].x < mid.x && pts[3].y > mid.y)
        #expect(pts[0].x > mid.x && pts[0].y > mid.y)
        let regions = (0..<4).map { l.meldTileRects(seat: $0, groups: 2, tiles: 6) }
        for (seat, rects) in regions.enumerated() {
            for r in rects {
                #expect(!r.intersects(l.centerPanel), "seat \(seat) の副露がパネルに重なる")
                for corner in Self.corners(r) {
                    #expect(l.feltContains(corner), "seat \(seat) の副露 \(corner) がフェルトの外")
                }
                for other in 0..<4 { for i in 0..<18 {
                    #expect(!r.intersects(l.riverRect(seat: other, index: i)), "seat \(seat) の副露が seat \(other) の河 \(i) に重なる")
                } }
                for (o, rects2) in regions.enumerated() where o > seat {
                    for r2 in rects2 {
                        #expect(!r.intersects(r2), "seat \(seat) と seat \(o) の副露が重なる")
                    }
                }
            }
        }
    }

    @Test("卓上の手牌一覧は河の牌と同じ大きさで、14 枚がフェルトの手前の縁に収まり河と重ならない")
    func overviewMatchesRiverTiles() {
        let l = Self.phone
        let o = l.handOverview
        // 一覧は最手前なので、河の 3 行目（縮尺が少し小さい）以上、手前の辺の基準幅以下
        #expect(o.tileWidth >= l.riverTileWidth * l.riverSlot(seat: 0, index: 12).scale)
        #expect(o.tileWidth <= l.riverTileWidth)
        #expect(o.tileWidth > l.riverTileWidth * 0.95, "河の牌と同じ大きさに寄せる（会長指摘）")
        #expect(o.width >= o.tileWidth * 14, "14 枚（手牌 13 + ツモ）が収まる幅")
        let h = o.tileWidth * MahjongTableLayout.tileAspect
        let rect = CGRect(x: o.center.x - o.width / 2, y: o.center.y - h / 2, width: o.width, height: h)
        for corner in Self.corners(rect) {
            #expect(l.feltContains(corner), "一覧の角 \(corner) がフェルトの外")
        }
        for seat in 0..<4 { for i in 0..<18 {
            #expect(!rect.intersects(l.riverRect(seat: seat, index: i)), "一覧が seat \(seat) の河 \(i) に重なる")
        } }
    }

    /// #960 の検査で使う卓の幅。320 は iPhone SE で卓に使える最小の幅（会長の受け入れ条件）、343 は SE の
    /// 実際の卓幅（375 − 16 × 2）、361 は iPhone 17、393 は基準、700 は iPad。
    static let inlineWidths: [CGFloat] = [320, 343, 361, 393, 700]
    static func layout(width: CGFloat) -> MahjongTableLayout {
        MahjongTableLayout(size: CGSize(width: width, height: width * MahjongTableLayout.aspect))
    }

    @Test("自分・対面の副露は手牌の行の横に並び、3 組（カン入り）まで河・パネル・他家の副露・立て牌と重ならず、手牌と 0.5 枚ぶん空く（#960）",
          arguments: [0, 2])
    func inlineMeldsClearEverything(seat: Int) {
        for width in Self.inlineWidths {
            let l = Self.layout(width: width)
            let gap = l.riverTileWidth * MahjongTableLayout.inlineMeldGapRatio
            for sizes in [[3], [4], [3, 3], [4, 3], [3, 3, 3], [4, 3, 3], [4, 4, 4]] {
                let groups = sizes.count
                let handCount = 14 - groups * 3   // ツモ番（1 枚多い）が最も長い
                let row = l.inlineMelds(seat: seat, handCount: handCount, meldSizes: sizes)
                #expect(row.groupRects.count == groups)
                #expect(row.tileWidth > 0)
                for (k, r) in row.groupRects.enumerated() {
                    let tag = "幅 \(width) seat \(seat) \(sizes) の \(k) 組目"
                    for corner in Self.corners(r) {
                        #expect(l.feltContains(corner), "\(tag): 角 \(corner) がフェルトの外")
                    }
                    #expect(!r.intersects(l.centerPanel), "\(tag) がパネルに重なる")
                    for other in 0..<4 { for i in 0..<18 {
                        #expect(!r.intersects(l.riverRect(seat: other, index: i)), "\(tag) が seat \(other) の河 \(i) に重なる")
                    } }
                    for other in [1, 3] {
                        for r2 in l.meldTileRects(seat: other, groups: 2, tiles: 7) {
                            #expect(!r.intersects(r2), "\(tag) が seat \(other) の副露に重なる")
                        }
                        for i in 0..<14 {
                            #expect(!r.intersects(Self.wallRect(l, seat: other, index: i, count: 14)), "\(tag) が seat \(other) の立て牌 \(i) に重なる")
                        }
                    }
                }
                // 手牌の行と同じ側にあり、手牌との間が 0.5 枚ぶん以上
                if seat == 0 {
                    let o = l.handOverview
                    let handRight = l.handOverviewTileCenter(index: handCount - 1, count: handCount).x + o.tileWidth / 2
                    #expect(row.frame.minX >= handRight + gap - 0.01, "幅 \(width) \(sizes): 副露の左端 \(row.frame.minX) が手牌の右端 \(handRight) に近い")
                    #expect(row.frame.maxX <= o.center.x + o.width / 2 + 0.01, "幅 \(width) \(sizes): 副露が一覧の行の右端を越える")
                    let handBottom = o.center.y + o.tileWidth * MahjongTableLayout.tileAspect / 2
                    #expect(abs(row.frame.maxY - handBottom) < 0.01, "副露の下端が手牌の下端と揃わない")
                } else {
                    let wall = l.handBlock(seat: 2, index: 0, count: handCount).0
                    let wallLeft = min(wall.a.x, wall.d.x)
                    #expect(row.frame.maxX <= wallLeft - gap + 0.01, "幅 \(width) \(sizes): 副露の右端 \(row.frame.maxX) が対面の壁の左端 \(wallLeft) に近い")
                    #expect(row.frame.minX >= l.project(u: MahjongTableLayout.farMeldRowLeftU, v: 0).x - 0.01)
                    // 対面の河の 3 行目（最も奥）より奥にある
                    #expect(row.frame.maxY < l.riverRect(seat: 2, index: 12).minY - 1, "対面の副露が対面の河に近い")
                }
            }
        }
    }

    @Test("手牌 4 枚（＋ツモ）＋副露 3 組は幅 320 / 393 の卓で 1 行に収まり、手牌の大きさは変えず副露だけ縮む（#960）",
          arguments: [0, 2])
    func inlineMeldsFitInRow(seat: Int) {
        for width: CGFloat in [320, 393] {
            let l = Self.layout(width: width)
            let river = l.riverTileWidth
            // 手牌の大きさは副露があっても変わらない
            #expect(abs(l.handOverview.tileWidth - river) < 0.001)
            let wall13 = l.handBlock(seat: 2, index: 0, count: 13).0
            let wall4 = l.handBlock(seat: 2, index: 0, count: 4).0
            #expect(abs((wall13.b.x - wall13.a.x) - (wall4.b.x - wall4.a.x)) < 0.001, "対面の立て牌の幅が変わった")
            for handCount in [4, 5] {
                // ポン・チー 3 組（9 枚）は 393 では河とほぼ同じ大きさ（自分は手牌 4 枚なら縮まない。ツモ番の 5 枚と
                // 対面（壁の右端 u 0.85 まで）は 1〜2pt 縮む）
                let pons = l.inlineMelds(seat: seat, handCount: handCount, meldSizes: [3, 3, 3])
                if width == 393 {
                    #expect(pons.tileWidth >= river * 0.9, "幅 393 seat \(seat) 手牌 \(handCount): ポン 3 組で縮みすぎ \(pons.tileWidth) / \(river)")
                    if seat == 0 && handCount == 4 {
                        #expect(abs(pons.tileWidth - river) < 0.001, "幅 393 手牌 4 枚: ポン 3 組で縮んだ \(pons.tileWidth) / \(river)")
                    }
                }
                #expect(pons.tileWidth <= river + 0.001)
                #expect(pons.tileWidth >= river * 0.6, "幅 \(width) seat \(seat): ポン 3 組で縮みすぎ \(pons.tileWidth) / \(river)")
                // カン 3 組（12 枚）でも収まる（縮む）
                let kans = l.inlineMelds(seat: seat, handCount: handCount, meldSizes: [4, 4, 4])
                #expect(kans.tileWidth >= river * 0.6, "幅 \(width) seat \(seat): カン 3 組で縮みすぎ \(kans.tileWidth) / \(river)")
                #expect(kans.tileWidth <= pons.tileWidth + 0.001)
                for row in [pons, kans] {
                    let f = row.frame
                    #expect(f.minX >= l.project(u: 0, v: 0).x - 0.01 && f.maxX <= l.project(u: 1, v: 0).x + 0.01,
                            "幅 \(width) seat \(seat) 手牌 \(handCount): 副露 \(f) がフェルトの幅を越える")
                }
            }
        }
    }

    @Test("副露の行の矩形は描画（`MahjongMeldRow`）どおり: 組の幅は枚数 × 牌幅 + 1pt の隙間、組の間は 3pt、高さは牌幅 × 1.34", arguments: [0, 2])
    func inlineMeldsMatchDrawing(seat: Int) {
        let l = Self.phone
        let sizes = [4, 3, 3]
        // 手牌 5 枚（ツモ番。`meldTileRects` が取る最も長い場合）
        let row = l.inlineMelds(seat: seat, handCount: 5, meldSizes: sizes)
        let w = row.tileWidth
        #expect(row.rotation == (seat == 2 ? 180 : 0))
        var union = CGRect.null
        for (k, r) in row.groupRects.enumerated() {
            union = union.union(r)
            #expect(abs(r.width - (CGFloat(sizes[k]) * w + CGFloat(sizes[k] - 1) * MahjongTableLayout.meldTileSpacing)) < 0.01)
            #expect(abs(r.height - w * MahjongTableLayout.meldTileAspect) < 0.01)
            #expect(abs(r.minY - row.frame.minY) < 0.01, "組が同じ行にない")
            if k > 0 {
                let prev = row.groupRects[k - 1]
                let gap = seat == 0 ? r.minX - prev.maxX : prev.minX - r.maxX
                #expect(abs(gap - MahjongTableLayout.meldGroupSpacing) < 0.01, "組の間隔 \(gap)")
            }
        }
        #expect(abs(union.minX - row.frame.minX) < 0.01 && abs(union.maxX - row.frame.maxX) < 0.01)
        #expect(abs(union.minY - row.frame.minY) < 0.01 && abs(union.maxY - row.frame.maxY) < 0.01)
        // 副露が無いときは幅 0 の矩形（描かない）
        let none = l.inlineMelds(seat: seat, handCount: 13, meldSizes: [])
        #expect(none.groupRects.isEmpty && none.frame.width == 0)
        // `meldTileRects` / `meldRegion` はこの行を返す
        let rects = l.meldTileRects(seat: seat, groups: 3, tiles: 10)
        #expect(rects == row.groupRects)
        #expect(l.meldRegion(seat: seat, groups: 3, tiles: 10) == row.frame)
    }

    @Test("手牌一覧は左詰め: 13 枚でも 14 枚でも 1 枚目の位置が同じで、ツモ牌は右端に足される（#960）")
    func overviewIsLeadingAligned() {
        let l = Self.phone
        let o = l.handOverview
        let first13 = l.handOverviewTileCenter(index: 0, count: 13)
        let first14 = l.handOverviewTileCenter(index: 0, count: 14)
        #expect(abs(first13.x - first14.x) < 0.01)
        #expect(abs(first14.x - (o.center.x - o.width / 2 + o.tileWidth / 2)) < 0.01)
        let last14 = l.handOverviewTileCenter(index: 13, count: 14)
        #expect(abs(last14.x - (o.center.x + o.width / 2 - o.tileWidth / 2)) < 0.01)
    }

    /// 立て牌 1 枚が画面上で占める矩形（上面の 4 点 + 傾き + 高さぶんの落ち）。
    private static func wallRect(_ l: MahjongTableLayout, seat: Int, index: Int, count: Int) -> CGRect {
        let (g, _) = l.handBlock(seat: seat, index: index, count: count)
        let xs = [g.a, g.b, g.c, g.d].map(\.x), ys = [g.a, g.b, g.c, g.d].map(\.y)
        return CGRect(x: xs.min()! - g.lean, y: ys.min()!,
                      width: xs.max()! - xs.min()! + g.lean * 2, height: ys.max()! - ys.min()! + g.drop)
    }

    private static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    @Test("対面の河は 3 行目まで対面の立て牌の足元に掛からず、自分の河は 3 行目まで手牌一覧の上にある")
    func farAndNearRowsStayClearOfWallAndOverview() {
        // #918 で卓の縦を使い切ったので、対面の壁・対面の河・自分の河・一覧の並びが崩れる回帰を検知する
        let l = Self.phone
        let wall = l.handBlock(seat: 2, index: 6, count: 13).0
        let wallFoot = wall.d.y + wall.drop
        for i in 12..<18 {
            #expect(l.riverRect(seat: 2, index: i).minY > wallFoot + 1, "対面の河 \(i) が対面の壁の足元 \(wallFoot) に掛かる")
        }
        let o = l.handOverview
        let overviewTop = o.center.y - o.tileWidth * MahjongTableLayout.tileAspect / 2
        for i in 12..<18 {
            #expect(l.riverRect(seat: 0, index: i).maxY < overviewTop - 1, "自分の河 \(i) が一覧に掛かる")
        }
    }

    @Test("多角形の内外判定")
    func polygon() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        #expect(MahjongTableLayout.contains(polygon: sq, point: CGPoint(x: 5, y: 5)))
        #expect(!MahjongTableLayout.contains(polygon: sq, point: CGPoint(x: 11, y: 5)))
    }

    @Test("木枠は 4 隅ともフェルトを外側から囲む（奥左・奥右・手前右・手前左の順・#833）")
    func woodFrameEnclosesFelt() {
        for l in [Self.phone, Self.pad, Self.phone17] {
            let frame = l.woodFrame
            #expect(frame.count == 4)
            for corner in l.felt {
                #expect(MahjongTableLayout.contains(polygon: frame, point: corner), "フェルトの角 \(corner) が木枠の外")
            }
            let feltXs = l.felt.map(\.x), feltYs = l.felt.map(\.y)
            let left = feltXs.min() ?? 0, right = feltXs.max() ?? 0
            let top = feltYs.min() ?? 0, bottom = feltYs.max() ?? 0
            #expect(frame[0].x < left && frame[0].y < top, "奥左")
            #expect(frame[1].x > right && frame[1].y < top, "奥右")
            #expect(frame[2].x > right && frame[2].y > bottom, "手前右")
            #expect(frame[3].x < left && frame[3].y > bottom, "手前左")
        }
    }

    @Test("上家・下家の副露 1 枚の矩形: 下家は手前へ・上家は奥へ牌の幅ずつ進み、組の区切りで間隔ぶん進む（#833）")
    func sideMeldRectAdvancesAlongColumn() {
        for l in [Self.phone, Self.pad] {
            let step = l.riverTileWidth
            for seat in [1, 3] {
                let dir: CGFloat = seat == 1 ? 1 : -1
                let head = l.sideMeldRect(seat: seat, ordinal: 0, gaps: 0)
                // 横向きなので、幅が牌の高さ・高さが牌の幅。
                #expect(abs(head.width - step * MahjongTableLayout.tileAspect) < 1e-9)
                #expect(abs(head.height - step) < 1e-9)
                var previous = head
                for ordinal in 1..<6 {
                    let rect = l.sideMeldRect(seat: seat, ordinal: ordinal, gaps: 0)
                    #expect(abs((rect.midY - previous.midY) - dir * step) < 1e-9, "席 \(seat) の \(ordinal) 枚目")
                    #expect(abs(rect.midX - head.midX) < 1e-9, "列（u）は一定")
                    previous = rect
                }
                let gapped = l.sideMeldRect(seat: seat, ordinal: 3, gaps: 1)
                let plain = l.sideMeldRect(seat: seat, ordinal: 3, gaps: 0)
                #expect(abs((gapped.midY - plain.midY) - dir * MahjongTableLayout.meldGroupSpacing) < 1e-9)
            }
        }
    }
}
