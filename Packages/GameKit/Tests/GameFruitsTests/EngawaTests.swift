import Testing
import CoreGraphics
import Core
@testable import GameFruits

/// 縁側に立つおじさんと手元の盆栽の置き場所（#2361）。座標は盤の抽象単位・上が原点（0 = 縁側の上端）。
@Suite("おじさんの盆栽: 縁側のおじさん")
struct EngawaTests {
    private typealias L = BonsaiEngawaLayout

    @Test("代用のおじさんの絵が読め、差し替え口は画像名 1 か所")
    func placeholderLoads() throws {
        #expect(BonsaiOjisanArt.holdImageName == "BonsaiOjisan_hold")
        let image = try #require(BonsaiOjisanArt.holdImage)
        #expect(image.width == Int(BonsaiOjisanArt.dotSize.width))
        #expect(image.height == Int(BonsaiOjisanArt.dotSize.height))
        // 手の位置はコマの中。
        #expect(BonsaiOjisanArt.handDot.x < BonsaiOjisanArt.dotSize.width)
        #expect(BonsaiOjisanArt.handDot.y < BonsaiOjisanArt.dotSize.height)
        // しかめ面は Core の共通の顔を使う（専用のコマができるまで）。
        #expect(BonsaiOjisanArt.worriedImageName == nil)
        #expect(OjisanPixel.faceImages[.frown] != nil)
    }

    @Test("おじさんは縁側に立ち（足は框の上）、頭は縁側からはみ出さない")
    func ojisanStandsOnTheEngawa() {
        let frame = L.ojisanFrame(cursorX: 50)
        #expect(abs(frame.maxY - (L.height + L.footSink)) < 1e-9)
        #expect(frame.minY >= 0, "頭が縁側の上へはみ出している")
    }

    @Test("盤の中ほどでは、おじさんの手が落とす位置の真上に来る")
    func handsFollowTheCursor() {
        for x in stride(from: 20.0, through: 80.0, by: 5) {
            let frame = L.ojisanFrame(cursorX: x)
            let handX = frame.minX + BonsaiOjisanArt.handDot.x * L.dot
            #expect(abs(handX - x) < 1e-9, "x=\(x) で手が \(handX)")
        }
        #expect(L.ojisanFrame(cursorX: 30).minX < L.ojisanFrame(cursorX: 70).minX, "左右に動く")
    }

    @Test("おじさんは縁側の両端で止まるが、手元の盆栽は必ず落とす位置の真上")
    func heldBonsaiAlwaysOverTheDropPoint() {
        for kind in FruitKind.dropPool {
            for x in [kind.radius, 3, 50, 97, FruitField.Metrics.width - kind.radius] {
                let ojisan = L.ojisanFrame(cursorX: x)
                #expect(ojisan.minX >= 0 && ojisan.maxX <= FruitField.Metrics.width + 1e-9, "x=\(x) でおじさんが縁側から出る")
                let held = L.heldFrame(kind: kind, cursorX: x)
                #expect(abs(held.midX - x) < 1e-9, "\(kind.name) が落とす位置からずれる（x=\(x)）")
                // 鉢の底は手の高さ。
                let handY = ojisan.minY + BonsaiOjisanArt.handDot.y * L.dot
                #expect(abs(held.maxY - handY) < 1e-9)
                // 大きさは盤の上と同じ。
                #expect(held.size == BonsaiArt.spriteSize(for: kind))
            }
        }
    }

    @Test("いちばん大きい落とす盆栽（みかん）でも、木が縁側の上へ大きくはみ出さない（盤の 4 単位まで）")
    func largestHeldBonsaiFits() {
        let held = L.heldFrame(kind: .mikan, cursorX: 50)
        #expect(held.minY > -4)
    }

    @Test("縁側と庭を合わせた枠の縦横比で切ると、庭は盤と同じ縦横比になる")
    func aspectRatioKeepsTheBoardRatio() {
        let width = 300.0
        let total = width / L.aspectRatio
        let garden = total - L.height * width / FruitField.Metrics.width
        #expect(abs(width / garden - FruitField.Metrics.aspectRatio) < 1e-9)
    }
}
