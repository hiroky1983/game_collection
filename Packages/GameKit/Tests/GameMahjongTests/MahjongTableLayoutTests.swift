import Testing
import Foundation
import CoreGraphics
@testable import GameMahjong

/// 卓の遠近レイアウト（#736）。絵は測れないので、重なり・密着・収まりだけを機械的に縛る。
@Suite("卓の遠近レイアウト")
struct MahjongTableLayoutTests {
    static let phone = MahjongTableLayout(size: CGSize(width: 393, height: 393))
    static let pad = MahjongTableLayout(size: CGSize(width: 700, height: 700))

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
        values += [layout.centerPanel.minX, layout.centerPanel.minY, layout.centerPanel.width, layout.centerPanel.height]
        let nonFinite = values.filter { !$0.isFinite }
        #expect(nonFinite.isEmpty, "0 ÷ 0 の NaN が混ざっている: \(nonFinite.count) 件")
        // 寸法（幅・高さ・縮尺）は負にならない。座標は原点まわりの引き算で -1 程度になってよい
        let sizes = [layout.riverTileWidth, layout.handOverview.width, layout.handOverview.tileWidth,
                     layout.centerPanel.width, layout.centerPanel.height]
            + (0..<4).flatMap { seat in layout.meldTileRects(seat: seat, groups: 2, tiles: 6).flatMap { [$0.width, $0.height] } }
            + (0..<4).flatMap { seat in (0..<18).map { layout.riverSlot(seat: seat, index: $0).scale } }
        let negative = sizes.filter { $0 < 0 }
        #expect(negative.isEmpty, "負の寸法が混ざっている: \(negative)")
    }

    @Test("奥ほど小さく、手前ほど大きい。中央線は幅の中央")
    func projection() {
        let l = Self.phone
        let far = l.project(u: 0.5, v: 0.1), near = l.project(u: 0.5, v: 0.9)
        #expect(far.scale < near.scale)
        #expect(far.y < near.y)
        #expect(abs(far.x - 393 / 2) < 0.001 && abs(near.x - 393 / 2) < 0.001)
        #expect(l.project(u: 1, v: 1).scale == 1)
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

    @Test("上家・下家の立て牌は下家が手前の端、上家が奥の端に固定され、副露で減った分だけ反対の端が空く")
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
        // 対面は中央寄せのまま
        let mid13 = l.handBlock(seat: 2, index: 6, count: 13).0
        let mid7 = l.handBlock(seat: 2, index: 3, count: 7).0
        #expect(abs(mid13.a.x - mid7.a.x) < 0.01)
    }

    @Test("上家・下家の副露は河と同じ幅で、2 組まで（ツモ番の壁とも）河・パネル・フェルトの縁と重ならない",
          arguments: [1, 3])
    func sideMeldsFitBesideWall(seat: Int) {
        // #918 で河（＝副露）を 2 割大きくしてからは、3 組（10 枚）だと 10 枚目が壁の上面に 7〜9pt 掛かる
        // （壁の列は「副露 + 残りの壁」で卓の奥行きを使い切る）。3 組の鳴きは実戦でまれなので 2 組までを縛る。
        let l = Self.phone
        #expect(l.meldTileWidth(seat: seat) == l.riverTileWidth)
        for groups in 1...2 {
            let tiles = groups * 3 + 1                // カン 1 つ + ポン／チー（全部カンは想定しない）
            let wallCount = 13 - groups * 3 + 1       // ツモ番（1 枚多い）が最も長い
            let rects = l.meldTileRects(seat: seat, groups: groups, tiles: tiles)
            #expect(rects.count == tiles)
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

    @Test("副露は 4 家とも 2 組（6 枚・カン無し）まで、河 18 枚・中央パネル・他家の副露と重ならない")
    func meldRegionsClearEverything() {
        // カン（4 枚幅の行）は #918 以降、自分は自分の河の右端の列に約 17pt、対面は対面の河の奥の行に約 1pt 掛かる
        // （河 6 枚 + 4 枚幅の副露 + 壁が手前の辺に収まらない）。ポン・チーだけの 2 組（3 枚幅）で縛る。
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

    @Test("自分の副露は河と同じ幅で 3 組（9 枚・カン無し）まで一覧の上に積み、一覧・河・下家の立て牌・パネルと重ならない")
    func ownMeldsStackAboveOverview() {
        // #918 以前は 4 組 16 枚。河を大きくしてからは、自分の副露の置き場（下家の河の手前〜一覧の上、
        // 自分の河の右〜下家の壁の左）が縦 96pt × 横 73pt しか無く、4 組（4 行）は下家の河に、カン（4 枚幅）は
        // 自分の河に掛かる。ポン・チーの 3 組で縛る（`meldRegionsClearEverything` も同じ理由でカン無し）。
        let l = Self.phone
        #expect(l.meldTileWidth(seat: 0) == l.riverTileWidth)
        let o = l.handOverview
        let overviewTop = o.center.y - o.tileWidth * MahjongTableLayout.tileAspect / 2
        let region = l.meldRegion(seat: 0, groups: 3, tiles: 9)
        // 一覧で選んだ牌は 3pt 持ち上がるので、その分も空ける
        #expect(region.maxY < overviewTop - 3, "副露の下端 \(region.maxY) が一覧の上端 \(overviewTop) に近い")
        #expect(!region.intersects(l.centerPanel))
        for corner in Self.corners(region) {
            #expect(l.feltContains(corner), "副露の角 \(corner) がフェルトの外")
        }
        for seat in 0..<4 { for i in 0..<18 {
            #expect(!region.intersects(l.riverRect(seat: seat, index: i)), "副露が seat \(seat) の河 \(i) に重なる")
        } }
        for other in 1...3 {
            #expect(!region.intersects(l.meldRegion(seat: other, groups: 2, tiles: 6)), "seat \(other) の副露と重なる")
        }
        // 下家の立て牌（ツモ番の 14 枚が最も手前まで伸びる）の占める矩形
        for i in 0..<14 {
            #expect(!region.intersects(Self.wallRect(l, seat: 1, index: i, count: 14)), "下家の立て牌 \(i) と重なる")
        }
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

    @Test("副露の矩形は描画の置き方どおり: 1 組目の行の中央が slot.center（対面は下へ、自分は上へ積む）")
    func meldRegionMatchesDrawing() {
        let l = Self.phone
        for seat in [0, 2] {
            let slot = l.meldSlot(seat: seat)
            let h = l.meldTileWidth(seat: seat) * slot.scale * 1.34
            let one = l.meldRegion(seat: seat, groups: 1, tiles: 3)
            #expect(abs(one.midY - slot.center.y) < 0.01, "seat \(seat): 1 組の縦の中央が slot.center でない")
            #expect(abs(one.height - h) < 0.01)
            let two = l.meldRegion(seat: seat, groups: 2, tiles: 7)
            #expect(abs(two.height - (h * 2 + 1)) < 0.01, "2 行は行の高さ 2 つ + 間隔 1pt")
            // 対面は 1 組目の下へ、自分は 1 組目の上へ増える
            #expect((abs(two.minY - one.minY) < 0.01) == (seat == 2))
            #expect((abs(two.maxY - one.maxY) < 0.01) == (seat == 0))
        }
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
}
