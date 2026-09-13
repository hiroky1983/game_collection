import Testing
import Foundation
import CoreGraphics
@testable import GameMahjong

/// 卓の遠近レイアウト（#736）。絵は測れないので、重なり・密着・収まりだけを機械的に縛る。
@Suite("卓の遠近レイアウト")
struct MahjongTableLayoutTests {
    static let phone = MahjongTableLayout(size: CGSize(width: 393, height: 393))
    static let pad = MahjongTableLayout(size: CGSize(width: 700, height: 700))

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

    @Test("CPU の立て牌は 13 枚が奥から手前の順に並び、足元はフェルトの内側")
    func handBlocks() {
        let l = Self.phone
        for seat in [1, 2, 3] {
            var lastY: CGFloat = -1
            for i in 0..<13 {
                let (g, facing) = l.handBlock(seat: seat, index: i, count: 13)
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

    @Test("副露の角は 4 家で別々の角にあり、河 18 枚と重ならない")
    func meldCornersDistinct() {
        let l = Self.phone
        let pts = (0..<4).map { l.meldSlot(seat: $0).center }
        let mid = CGPoint(x: l.size.width / 2, y: l.size.height / 2)
        // 対面=左上, 下家=右上, 上家=左下, 自分=右下
        #expect(pts[2].x < mid.x && pts[2].y < mid.y)
        #expect(pts[1].x > mid.x && pts[1].y < mid.y)
        #expect(pts[3].x < mid.x && pts[3].y > mid.y)
        #expect(pts[0].x > mid.x && pts[0].y > mid.y)
        let tile = l.meldTileWidth
        for seat in 0..<4 {
            let c = pts[seat]
            let r = CGRect(x: c.x - tile * 2, y: c.y - tile * 2, width: tile * 4, height: tile * 4)
            for other in 0..<4 { for i in 0..<18 {
                #expect(!r.intersects(l.riverRect(seat: other, index: i)), "seat \(seat) の副露の角が seat \(other) の河 \(i) に重なる")
            } }
        }
    }

    @Test("卓上の手牌一覧は、自分の副露（カン 4 枚）と重ならない")
    func overviewClearsOwnMelds() {
        let l = Self.phone
        let overview = l.handOverview
        let overviewRight = overview.center.x + overview.width / 2
        let meld = l.meldSlot(seat: 0)
        let kanLeft = meld.center.x - l.meldTileWidth * meld.scale * 4 - 3
        #expect(kanLeft - overviewRight > 2, "一覧の右端 \(overviewRight) とカンの左端 \(kanLeft)")
    }

    @Test("多角形の内外判定")
    func polygon() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        #expect(MahjongTableLayout.contains(polygon: sq, point: CGPoint(x: 5, y: 5)))
        #expect(!MahjongTableLayout.contains(polygon: sq, point: CGPoint(x: 11, y: 5)))
    }
}
