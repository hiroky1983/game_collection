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

    @Test("自分の出発点は切った牌の位置（既定はツモ牌＝一覧の右端）で、一覧の範囲に収まる")
    func ownOriginIsTilePosition() {
        let l = MahjongTableLayout(size: CGSize(width: 393, height: 393))
        let o = l.handOverview
        let left = o.center.x - o.width / 2, right = o.center.x + o.width / 2
        let first = l.handOverviewTileCenter(index: 0, count: 14)
        let last = l.handOverviewTileCenter(index: 13, count: 14)
        #expect(abs(first.x - (left + o.tileWidth / 2)) < 0.01)
        #expect(abs(last.x - (right - o.tileWidth / 2)) < 0.01)
        #expect(first.y == o.center.y && last.y == o.center.y)
        #expect(l.discardOrigin(seat: 0) == last, "既定はツモ牌の位置")
        // 枚数が少ないときは左詰め（#960。11 枚でも 1 枚目は 14 枚のときと同じ位置）
        #expect(abs(l.handOverviewTileCenter(index: 0, count: 11).x - first.x) < 0.01)
        // 範囲外の index は端に丸める
        #expect(l.handOverviewTileCenter(index: 99, count: 14) == last)
    }

    @Test("出発点は 4 家ともフェルトの内側")
    func originsInsideFelt() {
        let l = MahjongTableLayout(size: CGSize(width: 393, height: 393))
        for seat in 0..<4 {
            #expect(l.feltContains(l.discardOrigin(seat: seat)), "seat \(seat)")
        }
    }
}
