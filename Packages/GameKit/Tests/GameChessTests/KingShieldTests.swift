import Testing
import Foundation
@testable import GameChess

/// チェスの玉の安全性の評価（`kingShield`・将棋の `kingExposure`/`kingShelter` に当たる項）を
/// 固定局面の**値**で確かめる（#1390）。
///
/// `kingShield` は「キングの 1 段前（白は上・黒は下）の左・正面・右の 3 マスに自分のポーンが
/// あれば 1 枚 14 点」。中盤（キング・ポーン以外の駒の総額がルーク 2 枚ぶんを超える）だけ
/// `evaluate` に足される。期待値は下の各局面で手で数えた値。
@Suite("チェスのキングの盾（kingShield・#1390）")
struct ChessKingShieldTests {

    private let context = ChessSearchContext(
        maxDepth: 1, usePositional: true, useQuiescence: false, timeLimit: 0
    )

    private func position(_ fen: String) throws -> ChessPosition {
        try #require(ChessPosition.fromFEN(fen))
    }

    private func shield(_ fen: String, _ color: ChessColor = .white) throws -> Int {
        context.kingShield(try position(fen), color)
    }

    @Test("初期局面は白黒とも 3 枚の盾 = 42")
    func startPosition() throws {
        #expect(try shield(ChessPosition.startFEN, .white) == 42)
        #expect(try shield(ChessPosition.startFEN, .black) == 42)
    }

    @Test("キャスリング後の形: f2 g2 h2 は 42、h ポーンを h3 に突くと 28")
    func castledShield() throws {
        #expect(try shield("4k3/8/8/8/8/8/5PPP/6K1 w - - 0 1") == 42)
        // h3 は 2 段前なので盾に数えない。
        #expect(try shield("4k3/8/8/8/8/7P/5PP1/6K1 w - - 0 1") == 28)
    }

    @Test("盤端のキングは 2 マスしか見ない: h1 に g2 h2 で 28")
    func edgeKing() throws {
        #expect(try shield("4k3/8/8/8/8/8/6PP/7K w - - 0 1") == 28)
    }

    @Test("相手のポーン・自分のポーン以外の駒は盾にならない")
    func onlyOwnPawnsCount() throws {
        #expect(try shield("4k3/8/8/8/8/8/3ppp2/4K3 w - - 0 1") == 0)
        #expect(try shield("4k3/8/8/8/8/8/3NBN2/4K3 w - - 0 1") == 0)
    }

    @Test("前後の向き: 白の盾は上（1 段前）で、後ろのポーンは数えない")
    func forwardDirectionForWhite() throws {
        #expect(try shield("4k3/8/8/8/3PPP2/4K3/8/8 w - - 0 1") == 42)
        #expect(try shield("4k3/8/8/8/8/4K3/3PPP2/8 w - - 0 1") == 0)
    }

    @Test("黒の盾は下向き: g8 に f7 g7 h7 で 42（白のポーンは数えない）")
    func blackShield() throws {
        #expect(try shield("5rk1/5ppp/8/8/8/8/8/4K3 b - - 0 1", .black) == 42)
        #expect(try shield("5rk1/5PPP/8/8/8/8/8/4K3 b - - 0 1", .black) == 0)
    }

    @Test("evaluate への寄与: 中盤は盾の差 42 がそのまま出て、終盤は 0")
    func evaluateAddsShieldOnlyInMiddlegame() throws {
        // g1 と b1 は中盤の位置表で同点（自陣の段 18 + 端寄せ 14 = 32）、終盤表でも中央から
        // 同じ距離 3 なので、キングを動かした差は盾（g1: f2 g2 h2 = 42、b1: 0）だけになる。
        // 中盤: Q + R = 1400 > ルーク 2 枚ぶん 1000。
        let middleG1 = try position("4k3/8/8/8/8/8/5PPP/3QR1K1 w - - 0 1")
        let middleB1 = try position("4k3/8/8/8/8/8/5PPP/1K1QR3 w - - 0 1")
        #expect(context.evaluate(middleG1) - context.evaluate(middleB1) == 42)

        // 終盤（ポーンとキングだけ）: 盾は足されないので差は 0。
        let endG1 = try position("4k3/8/8/8/8/8/5PPP/6K1 w - - 0 1")
        let endB1 = try position("4k3/8/8/8/8/8/5PPP/1K6 w - - 0 1")
        #expect(context.evaluate(endG1) - context.evaluate(endB1) == 0)
    }
}
