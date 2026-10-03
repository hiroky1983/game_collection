import Testing
import Foundation
import simd
@testable import GameHomerun

/// 月へ飛ぶ球の火の玉（#1687）の形・色の段・板の並び。
@Suite("柵越えおじさんの火の玉の絵")
struct HomerunFireballArtTests {
    typealias Art = HomerunFireballArt

    @Test("炎の形: 頭は丸く幅いっぱい・尾の先へ細くなる・外は描かない")
    func flameShape() {
        for style in [Art.Style.outer, .inner, .tail] {
            let head = 0.5 / Art.aspect(style)
            #expect(abs((Art.halfWidth(y: head, side: 1, style: style) ?? 0) - 0.5) < 1e-9, "頭の円の中心で幅いっぱい")
            #expect((Art.halfWidth(y: 0.97, side: 1, style: style) ?? 1) < 0.1, "尾の先は細い")
            #expect(Art.halfWidth(y: 1.2, side: 1, style: style) == nil)
            #expect(Art.band(x: 0.49, y: 0.95, style: style) == nil, "細い所の外は透明")
        }
        // 左右の縁は別の位相で波打つ（舌のようにゆらめく）。
        let l = Art.halfWidth(y: 0.6, side: -1, style: .outer)!, r = Art.halfWidth(y: 0.6, side: 1, style: .outer)!
        #expect(abs(l - r) > 0.005)
    }

    @Test("色の段: 中心は白〜黄・外側は橙〜赤・縁は濃い赤の細い線。内側の炎は白と黄だけ")
    func colorBands() {
        let head = 0.5 / Art.aspect(.outer)
        #expect(Art.band(x: 0, y: head * 0.5, style: .outer) == 0, "芯は白")
        #expect(Art.band(x: 0.47, y: head, style: .outer) ?? 0 >= 2, "外側は橙〜赤")
        #expect(Art.band(x: 0.49, y: head, style: .outer) == Art.palette.count, "縁は細い線")
        var bands = Set<Int>()
        for i in 0..<40 { for j in 0..<40 {
            if let b = Art.band(x: Double(i) / 40 - 0.5, y: Double(j) / 40, style: .inner), b < Art.palette.count { bands.insert(b) }
        } }
        #expect(bands == [0, 1])
        // 画像の大きさ・透明な外・炎の中の赤の成分（切り抜きのしきい値 0.5 より上）。
        let p = Art.pixels(.tail)
        #expect(p.bytes.count == p.width * p.height * 4)
        #expect(p.bytes[3] == 0, "左上（尾の先の外）は透明")
        let reds = stride(from: 0, to: p.bytes.count, by: 4).filter { p.bytes[$0 + 3] == 255 }.map { p.bytes[$0] }
        #expect(!reds.isEmpty && reds.allSatisfy { $0 >= 0xB0 })
    }

    @Test("板の並び: 枚数は固定・カメラの面の中で尾は火の尾の向き・炎は球を中心に揺らぐ")
    func spriteLayout() throws {
        let t = HomerunMoonShot.impact - 0.8
        let fire = try #require(HomerunMoonShot.fireball(at: t))
        let camera = HomerunMoonShot.cameraPosition
        let sprites = Art.sprites(fire, camera: camera)
        #expect(sprites.count == Art.spriteCount)
        #expect(Set(sprites.map(\.layer)).count == sprites.count)
        let tail = try #require(sprites.first { $0.layer == .tail })
        // 火の尾は球の後ろ（尾の向き）へ長く伸びる。
        #expect(simd_dot(tail.axis, fire.trail) > 0.8)
        #expect(tail.size.y > fire.radius * 10)
        #expect(simd_dot(tail.center - fire.center, tail.axis) > 0)
        // 頭（尾と反対の端）は球の近く。
        let head = tail.center - tail.axis * (tail.size.y / 2 - tail.size.x / 2)
        #expect(simd_distance(head, fire.center) < fire.radius * 0.5)
        // 時間で舌の長さが変わる（揺らめく）。
        var later = fire
        later.time += 0.05
        let a = sprites.first { $0.layer == .tongue(1) }!, b = Art.sprites(later, camera: camera).first { $0.layer == .tongue(1) }!
        #expect(a.size != b.size)
        // 同じ入力は同じ並び（乱数なし）。
        #expect(Art.sprites(fire, camera: camera) == sprites)
        // 火の粉は尾の側にある。
        for s in sprites { if case .spark = s.layer { #expect(simd_dot(s.center - fire.center, fire.trail) > 0) } }
    }
}
