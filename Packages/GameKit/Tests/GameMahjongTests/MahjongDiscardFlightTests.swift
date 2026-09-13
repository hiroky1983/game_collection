import Testing
import Foundation
import CoreGraphics
@testable import GameMahjong
@testable import MahjongTiles

/// 打牌が河へ飛ぶ動き（#738）。位置は純関数なので端点と頂点だけ縛る。
@Suite("打牌の飛行")
struct MahjongDiscardFlightTests {
    static let flight = MahjongDiscardFlight(
        seat: 0, index: 3, tile: .characters(1),
        from: CGPoint(x: 100, y: 300), to: CGPoint(x: 200, y: 200), rotation: 0, scale: 1)

    @Test("進捗 0 は出発点、1 は着地点")
    func endpoints() {
        #expect(Self.flight.position(progress: 0) == CGPoint(x: 100, y: 300))
        #expect(Self.flight.position(progress: 1) == CGPoint(x: 200, y: 200))
    }

    @Test("途中は直線より上（放物線）で、進捗は 0〜1 に丸める")
    func arcAndClamp() {
        let mid = Self.flight.position(progress: 0.5)
        #expect(mid.x == 150)
        #expect(mid.y < 250 - 20, "頂点で持ち上がっていない: \(mid.y)")
        #expect(Self.flight.position(progress: -1) == Self.flight.position(progress: 0))
        #expect(Self.flight.position(progress: 2) == Self.flight.position(progress: 1))
    }

    @Test("出発点は 4 家ともフェルトの内側")
    func originsInsideFelt() {
        let l = MahjongTableLayout(size: CGSize(width: 393, height: 393))
        for seat in 0..<4 {
            #expect(l.feltContains(l.discardOrigin(seat: seat)), "seat \(seat)")
        }
    }
}
