import Testing
import Foundation
import MahjongTiles
@testable import GameMahjong

// MARK: - 牌の並び

@Suite("牌の通し番号")
struct MahjongTileOrderTests {

    @Test("34 種すべてが 0〜33 に 1 対 1 で対応する")
    func indexRoundTrip() {
        for index in 0..<MahjongTileOrder.kindCount {
            let tile = MahjongTileOrder.tile(at: index)
            #expect(MahjongTileOrder.index(of: tile) == index)
        }
        #expect(Set(MahjongTileOrder.all).count == 34)
    }

    @Test("ドラは表示牌の次の牌。9 → 1、北 → 東、三元牌は白 → 發 → 中 → 白で輪になる")
    func doraWrapsAround() {
        func dora(_ text: String) -> MahjongTile {
            let index = MahjongTileOrder.index(of: MahjongNotation.tile(text))
            return MahjongTileOrder.tile(at: MahjongTileOrder.doraIndex(after: index))
        }
        #expect(dora("1m") == .characters(2))
        #expect(dora("9m") == .characters(1))
        #expect(dora("9p") == .circles(1))
        #expect(dora("9s") == .bamboos(1))
        #expect(dora("1z") == .wind(1))         // 東 → 南
        #expect(dora("4z") == .wind(0))         // 北 → 東
        #expect(dora("5z") == .dragon(1))       // 白 → 發
        #expect(dora("6z") == .dragon(0))       // 發 → 中
        #expect(dora("7z") == .dragon(2))       // 中 → 白
    }

    @Test("Int.min / Int.max の牌でもオーバーフローで停止せず 0〜33 に丸まる")
    func extremeValuesDoNotOverflow() {
        // 破損したスナップショットは `MahjongTile` の associated value に任意の Int を持ちうる
        // （`Codable` は自動合成で値域を検査しない）。加算・減算をしてから丸めると
        // `.characters(Int.min)` の `n - 1` と `.circles(Int.max)` の `8 + n` が
        // オーバーフローして実行時に停止する。
        let extremes: [MahjongTile] = [
            .characters(.min), .characters(.max),
            .circles(.min), .circles(.max),
            .bamboos(.min), .bamboos(.max),
            .wind(.min), .wind(.max),
            .dragon(.min), .dragon(.max),
        ]
        for tile in extremes {
            let index = MahjongTileOrder.index(of: tile)
            #expect((0..<MahjongTileOrder.kindCount).contains(index))
        }
    }
}

// MARK: - シャンテン数

@Suite("シャンテン数と和了形")
struct MahjongShantenTests {

    @Test("4 面子 + 雀頭の和了形はシャンテン -1")
    func standardWin() {
        let hand = MahjongNotation.hand("123m456m789m123p11s")
        #expect(MahjongShanten.shanten(hand) == -1)
        #expect(MahjongShanten.isWinningHand(hand))
    }

    @Test("七対子の和了形もシャンテン -1")
    func sevenPairsWin() {
        let hand = MahjongNotation.hand("1133m5577p99s1122z")
        #expect(MahjongShanten.isWinningHand(hand))
    }

    @Test("同じ牌 4 枚は七対子にならない（2 組の対子として数えない）")
    func fourOfAKindIsNotTwoPairs() {
        // 1m×4 + 3m×2 + 5p×2 + 7p×2 + 9s×2 + 東×2 = 14 枚だが 6 種しかない。
        let hand = MahjongNotation.hand("11113m55p77p99s11z")
        #expect(MahjongShanten.sevenPairs(hand.counts) > -1)
    }

    @Test("国士無双（幺九牌 13 種 + 対子）はシャンテン -1")
    func thirteenOrphansWin() {
        let hand = MahjongNotation.hand("19m19p19s12345677z")
        #expect(MahjongShanten.isWinningHand(hand))
        #expect(MahjongShanten.thirteenOrphans(hand.counts) == -1)
    }

    @Test("聴牌はシャンテン 0")
    func tenpai() {
        // 123m456m789m123p1s → 1s 単騎。
        let hand = MahjongNotation.hand("123m456m789m123p1s")
        #expect(hand.total == 13)
        #expect(MahjongShanten.isTenpai(hand))
    }

    @Test("配牌直後のばらばらな手はシャンテンが正の値になる")
    func farFromTenpai() {
        let hand = MahjongNotation.hand("159m159p159s1234z")
        #expect(MahjongShanten.shanten(hand) > 0)
    }

    @Test("色ごとに分けた高速版は、34 種を総当たりする素朴版と必ず同じ値を返す")
    func matchesReferenceImplementation() {
        // 高速化（色ごとの分解 + DP）で挙動が変わっていないことを、無作為な手牌で突き合わせる。
        var generator = MahjongSeededGenerator(seed: 20_260_824)
        var wall = MahjongModel.makeWall()
        for round in 0..<300 {
            wall.shuffle(using: &generator)
            // 13 枚と 14 枚の両方を見る（打牌前後のどちらでも使うため）。
            let size = round % 2 == 0 ? 13 : 14
            let hand = MahjongHand(tiles: Array(wall.prefix(size)))
            #expect(
                MahjongShanten.standard(hand.counts) == MahjongShanten.standardReference(hand.counts),
                "食い違った牌姿: \(hand.tiles.map(\.key).joined())"
            )
        }
    }

    @Test("1 シャンテンの手は、受け入れ牌を 1 枚足すと聴牌になる")
    func oneAwayFromTenpai() {
        // 123m456m789m12p35s → 3p が入れば 35s の嵌張待ち聴牌。
        let hand = MahjongNotation.hand("123m456m789m12p35s")
        #expect(MahjongShanten.shanten(hand) == 1)
        let accepted = MahjongShanten.acceptedTiles(hand)
        #expect(accepted.contains(.circles(3)))
        for tile in accepted {
            #expect(MahjongShanten.shanten(hand.adding(tile)) == 0)
        }
    }
}

// MARK: - 待ち牌

@Suite("待ち牌")
struct MahjongWaitTests {

    private func waits(_ text: String) -> Set<MahjongTile> {
        Set(MahjongShanten.waits(MahjongNotation.hand(text)))
    }

    @Test("両面待ちは 2 種")
    func twoSided() {
        // 123m456m789m11p23s → 1s / 4s 待ち。
        #expect(waits("123m456m789m11p23s") == [.bamboos(1), .bamboos(4)])
    }

    @Test("辺張待ちは 1 種（12s は 3s だけ）")
    func edgeWait() {
        #expect(waits("123m456m789m11p12s") == [.bamboos(3)])
    }

    @Test("嵌張待ちは 1 種（13s は 2s だけ）")
    func closedWait() {
        #expect(waits("123m456m789m11p13s") == [.bamboos(2)])
    }

    @Test("双碰待ちは 2 種")
    func pairWait() {
        // 123m456m789m11p22s → 1p / 2s のシャンポン待ち。
        #expect(waits("123m456m789m11p22s") == [.circles(1), .bamboos(2)])
    }

    @Test("既に 4 枚使っている牌は待ちに含めない")
    func excludesExhaustedTile() {
        // 1111m は 1m を 4 枚使っているので、1m 単騎待ちは成立しない。
        #expect(waits("1111m234m567m99m9p").contains(.characters(1)) == false)
    }

    @Test("七対子の単騎待ちも拾う")
    func sevenPairsWait() {
        #expect(waits("1133m5577p99s112z") == [.wind(1)])
    }

    @Test("国士無双の 13 面待ちは 13 種すべて")
    func thirteenWayWait() {
        let result = waits("19m19p19s1234567z")
        #expect(result.count == 13)
        #expect(result.contains(.characters(1)))
        #expect(result.contains(.dragon(0)))
    }
}
