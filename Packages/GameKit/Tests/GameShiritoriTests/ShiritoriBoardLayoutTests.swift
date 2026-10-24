import Testing
import SwiftUI
import Core
@testable import GameShiritori

/// 盤札の絵の一辺（#2847）。固定 pt のまま積むと iPhone SE で 5 行が収まらず、最上段のカードがナビバーの裏に入っていた。
@Suite("カードしりとりの盤の寸法")
struct ShiritoriBoardLayoutTests {
    private let reading = ShiritoriBoardLayout.baseReadingHeight

    @Test("30 枚は 6 列 × 5 行")
    func thirtyCardsAreFiveRows() {
        #expect(ShiritoriBoardLayout.rows(for: ShiritoriRules.boardSize) == 5)
        #expect(ShiritoriBoardLayout.rows(for: 0) == 1)
    }

    /// iPhone 17（幅 402 − 左右 16 = 370pt）: 盤の下に余りがあるので幅で決まる。6 列が横に収まる最大の絵。
    @Test("高さに余りがあれば幅で決まる（iPhone 17）")
    func wideScreenIsWidthBound() {
        let width: CGFloat = 370
        let side = ShiritoriBoardLayout.artSide(availableWidth: width, availableHeight: 600,
                                                count: ShiritoriRules.boardSize, readingHeight: reading)
        let tileWidth = (width - 16 - 6 * 5) / 6
        #expect(abs(side - (tileWidth - 4 - 6)) < 0.01)
        #expect(side > 40)
    }

    /// iPhone SE（幅 343pt・対局中に盤へ残る高さはおよそ 270〜340pt）: 高さで決まり、5 行が残りの高さに収まる。
    /// 絵の下限 16pt の盤は 259pt なので、それより低い残り（結果の画面で延長ボタンとレコメンドが同時に出たとき）は収まらず、
    /// 下端側へはみ出す（`clampsAtMinimum`）。
    @Test("高さが足りなければ高さで決まり、盤は残りの高さに収まる（iPhone SE）")
    func shortScreenFitsAvailableHeight() {
        let width: CGFloat = 343
        for height in [270.0, 300.0, 330.0] as [CGFloat] {
            let side = ShiritoriBoardLayout.artSide(availableWidth: width, availableHeight: height,
                                                    count: ShiritoriRules.boardSize, readingHeight: reading)
            let board = ShiritoriBoardLayout.boardHeight(artSide: side, count: ShiritoriRules.boardSize, readingHeight: reading)
            #expect(board <= height + 0.01, "残り \(height)pt に盤 \(board)pt が収まらない")
            #expect(board > height - 1, "余りを残しすぎている（残り \(height)pt・盤 \(board)pt）")
            #expect(side >= ShiritoriBoardLayout.minArtSide)
        }
    }

    /// 文字を大きくすると読みの行が高くなり、絵はそのぶん小さくなる（溢れる方向には行かない）。
    @Test("読みの行が高いほど絵は小さい")
    func tallerReadingShrinksArt() {
        let a = ShiritoriBoardLayout.artSide(availableWidth: 343, availableHeight: 300, count: 30, readingHeight: 13)
        let b = ShiritoriBoardLayout.artSide(availableWidth: 343, availableHeight: 300, count: 30, readingHeight: 18)
        #expect(b < a)
    }

    @Test("極端に低くても絵の下限で止まる")
    func clampsAtMinimum() {
        let side = ShiritoriBoardLayout.artSide(availableWidth: 343, availableHeight: 40, count: 30, readingHeight: 13)
        #expect(side == ShiritoriBoardLayout.minArtSide)
    }

    /// 実際の札の描画が、寸法の式どおりの高さに収まること（式が実物より小さいと計算上は収まっても溢れる）。
    @MainActor
    @Test("札の実寸は式どおり")
    func tileRendersAtComputedHeight() throws {
        let card = try #require(ShiritoriCard.deck.first)
        for side in [20.0, 32.0, 45.0] as [CGFloat] {
            let tile = ShiritoriCardTile(card: card, reading: "さかな",
                                         style: .board(owner: .player, selectable: false, isCPUCursor: false),
                                         artSide: side)
                .frame(width: 50)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: tile)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let expected = ShiritoriBoardLayout.tileHeight(artSide: side, readingHeight: reading)
            #expect(CGFloat(image.height) <= expected + 1, "絵 \(side)pt の札が \(image.height)pt（式 \(expected)pt）")
            #expect(CGFloat(image.height) >= expected - 3, "式が実物より大きすぎる（絵 \(side)pt・札 \(image.height)pt・式 \(expected)pt）")
        }
    }
}
