import Testing
import CoreGraphics
import Foundation
@testable import GameFruits

/// 盆栽の絵（#2361・案 B「木を大きく見せる」）。素材が全段そろって読めることと、絵の枠の置き方を確かめる。
@Suite("盆栽の絵")
struct ArtTests {
    @Test("11 段すべての絵が読め、段ごとに違う絵になっている")
    func everyTierHasItsOwnArt() throws {
        var seen: [Data] = []
        for kind in FruitKind.allCases {
            let image = try #require(BonsaiArt.image(kind), "\(kind.name)（\(kind.artName)）が読めない")
            #expect(image.width > 0 && image.height > 0)
            let bytes = try #require(image.dataProvider?.data as Data?)
            #expect(!seen.contains(bytes), "\(kind.name) の絵が別の段と同じ")
            seen.append(bytes)
        }
    }

    @Test("素材は表示の大きさに見合う解像度に縮めてある（小さい段ほど小さい・最大でも 320px）")
    func artIsDownscaled() throws {
        for kind in FruitKind.allCases {
            let image = try #require(BonsaiArt.image(kind))
            #expect(max(image.width, image.height) <= 320, "\(kind.name) が \(image.width)×\(image.height)")
            // 盤の幅 400pt・3x の画面で、絵の枠（直径の 1.3 倍）を 1px 以上の細かさで出せる大きさの 8 割はある。
            let needed = kind.radius * 2 * BonsaiArt.canvasScale / FruitField.Metrics.width * 400 * 3 * 0.8
            #expect(Double(max(image.width, image.height)) >= min(needed, 280), "\(kind.name) が粗すぎる")
        }
        #expect(try #require(BonsaiArt.image(.sakura)).width < (try #require(BonsaiArt.image(.kinmatsu))).width)
    }

    @Test("絵は円の直径の 1.3 倍の枠に収まり、鉢の底は円の下端・横は円の中心に揃う（案 B）")
    func spriteFrameSitsOnTheCircleBottom() {
        #expect(BonsaiArt.canvasScale == 1.3)
        for kind in FruitKind.allCases {
            let frame = BonsaiArt.spriteFrame(for: kind, x: 40, y: 30)
            let side = kind.radius * 2 * BonsaiArt.canvasScale
            #expect(abs(frame.minY - (30 - kind.radius)) < 1e-9, "\(kind.name) の鉢の底が円の下端に無い")
            #expect(abs(frame.midX - 40) < 1e-9)
            #expect(frame.width <= side + 1e-9 && frame.height <= side + 1e-9)
            #expect(max(frame.width, frame.height) > side - 1e-9, "長い辺は枠いっぱい")
            // 木は円の上端より上へはみ出す。
            #expect(frame.maxY > 30 + kind.radius)
        }
    }
}
