import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire

// MARK: - レイアウト

@Suite("麻雀ソリティアのレイアウト")
struct MahjongLayoutTests {

    @Test("標準の亀型レイアウトは144枚で、段ごとの枚数が 87/36/16/4/1")
    func layoutShape() {
        let layout = MahjongSolitaireRules.layout
        #expect(layout.count == 144)
        let perLayer = (0...4).map { layer in layout.filter { $0.layer == layer }.count }
        #expect(perLayer == [87, 36, 16, 4, 1])
    }

    @Test("同じ場所に2枚置かれていない（同じ段で重なる牌が無い）")
    func noOverlapWithinLayer() {
        let layout = MahjongSolitaireRules.layout
        #expect(Set(layout).count == layout.count, "完全に同じ座標は無い")
        for (i, a) in layout.enumerated() {
            for b in layout[(i + 1)...] where a.layer == b.layer {
                #expect(!a.overlaps(b), "同じ段の \(a) と \(b) が重なっている")
            }
        }
    }

    @Test("上の段の牌は必ず下の段の牌に載っている")
    func upperLayersRestOnLowerOnes() {
        let layout = MahjongSolitaireRules.layout
        for tile in layout where tile.layer > 0 {
            let supported = layout.contains { $0.layer == tile.layer - 1 && $0.overlaps(tile) }
            #expect(supported, "\(tile) の下に牌が無い")
        }
    }
}

// MARK: - 取得可否

@Suite("取れる牌の判定")
struct MahjongFreeTests {

    /// 指定した位置だけが残っている盤面を作る。
    private func remaining(_ indices: [Int]) -> [Bool] {
        var flags = [Bool](repeating: false, count: MahjongSolitaireRules.layout.count)
        for index in indices { flags[index] = true }
        return flags
    }

    private func index(_ layer: Int, _ hx: Int, _ hy: Int) -> Int {
        guard let index = MahjongSolitaireRules.index(layer: layer, hx: hx, hy: hy) else {
            Issue.record("レイアウトに (\(layer), \(hx), \(hy)) が無い")
            return 0
        }
        return index
    }

    @Test("上に牌が載っていると取れない")
    func coveredTileIsNotFree() {
        let top = index(4, 13, 7)          // 最上段の1枚
        let under = index(3, 12, 6)        // その真下（第4段）
        let flags = remaining([top, under])
        #expect(MahjongSolitaireRules.isFree(top, remaining: flags))
        #expect(!MahjongSolitaireRules.isFree(under, remaining: flags), "上に載っているので取れない")
    }

    @Test("左右とも塞がれていると取れず、どちらかが空けば取れる")
    func flankedTileIsNotFree() {
        let left = index(0, 2, 0)
        let middle = index(0, 4, 0)
        let right = index(0, 6, 0)

        let all = remaining([left, middle, right])
        #expect(!MahjongSolitaireRules.isFree(middle, remaining: all), "両隣が塞がっていると取れない")
        #expect(MahjongSolitaireRules.isFree(left, remaining: all), "左端は取れる")
        #expect(MahjongSolitaireRules.isFree(right, remaining: all), "右端は取れる")

        let opened = remaining([middle, right])
        #expect(MahjongSolitaireRules.isFree(middle, remaining: opened), "左が空けば取れる")
    }

    @Test("行の間にまたがるヒレは同じ段の両隣として扱われる")
    func fintTileBlocksNeighbours() {
        let fin = index(0, 26, 7)          // 右のヒレ（内側）
        let outer = index(0, 28, 7)        // 右のヒレ（外側）
        let body = index(0, 24, 6)         // 甲羅の右端（4行目）
        let flags = remaining([fin, outer, body])
        #expect(!MahjongSolitaireRules.isFree(fin, remaining: flags), "内側のヒレは左右とも塞がっている")
        #expect(MahjongSolitaireRules.isFree(outer, remaining: flags), "外側のヒレは右が空いている")
        #expect(MahjongSolitaireRules.isFree(body, remaining: flags), "甲羅側は左が空いている")
    }

    @Test("初期盤面で取れるのは上に何も載っていない牌だけ（第4段は最上段に覆われている）")
    func initialFreeTiles() {
        var generator = MahjongSeededGenerator(seed: 7)
        let board = MahjongSolitaireRules.generate(using: &generator)
        let flags = MahjongSolitaireRules.remainingFlags(faces: board.faces)
        let free = MahjongSolitaireRules.freeIndices(remaining: flags)

        #expect(free.contains(index(4, 13, 7)), "てっぺんの1枚は取れる")
        for hx in [12, 14] {
            for hy in [6, 8] {
                #expect(!free.contains(index(3, hx, hy)), "第4段はてっぺんに覆われている")
            }
        }
        #expect(!free.contains(index(0, 12, 0)), "甲羅の内側は両隣が塞がっていて取れない")
        for i in free {
            let tile = MahjongSolitaireRules.layout[i]
            #expect(!MahjongSolitaireRules.layout.contains { $0.layer > tile.layer && $0.overlaps(tile) },
                    "取れる牌の上には牌が載っていない: \(tile)")
        }
    }
}

// MARK: - 牌の構成

@Suite("牌の構成")
struct MahjongFaceTests {

    @Test("144枚の内訳は 数牌27種×4 + 風牌4種×4 + 三元牌3種×4 + 花牌4 + 季節牌4")
    func deckComposition() {
        let faces = MahjongSolitaireRules.facePairs().flatMap { $0 }
        #expect(faces.count == 144)

        var counts: [MahjongFace: Int] = [:]
        for face in faces { counts[face, default: 0] += 1 }

        for n in 1...9 {
            #expect(counts[.characters(n)] == 4)
            #expect(counts[.circles(n)] == 4)
            #expect(counts[.bamboos(n)] == 4)
        }
        for n in 0..<4 { #expect(counts[.wind(n)] == 4) }
        for n in 0..<3 { #expect(counts[.dragon(n)] == 4) }
        for n in 0..<4 {
            #expect(counts[.flower(n)] == 1)
            #expect(counts[.season(n)] == 1)
        }
    }

    @Test("組はすべて合う2枚で、花牌同士・季節牌同士も合う")
    func pairsMatch() {
        for pair in MahjongSolitaireRules.facePairs() {
            #expect(pair.count == 2)
            #expect(pair[0].matches(pair[1]), "\(pair) が合わない")
        }
        #expect(MahjongFace.flower(0).matches(.flower(3)), "花牌は絵柄が違っても合う")
        #expect(MahjongFace.season(1).matches(.season(2)), "季節牌は絵柄が違っても合う")
        #expect(!MahjongFace.flower(0).matches(.season(0)), "花牌と季節牌は合わない")
        #expect(!MahjongFace.characters(1).matches(.circles(1)), "数字が同じでも種類が違えば合わない")
    }
}

// MARK: - 盤面生成（クリア可能性）

@Suite("盤面生成")
struct MahjongGenerationTests {

    /// 解法の順に取り除けるかを実際に再生して確かめる。
    /// 「そのとき本当に取れる 2 枚か」「絵柄が合うか」を毎手検証し、最後に 1 枚も残らないことを見る。
    private func replay(_ board: MahjongSolitaireRules.Board, seed: UInt64) {
        var faces = board.faces
        var flags = MahjongSolitaireRules.remainingFlags(faces: faces)
        for (step, pair) in board.solution.enumerated() {
            guard pair.count == 2 else {
                Issue.record("種 \(seed) の \(step) 手目が2枚組ではない")
                return
            }
            let (a, b) = (pair[0], pair[1])
            guard let faceA = faces[a], let faceB = faces[b] else {
                Issue.record("種 \(seed) の \(step) 手目で既に取り除かれた牌を指している")
                return
            }
            #expect(faceA.matches(faceB), "種 \(seed) の \(step) 手目の絵柄が合わない")
            #expect(MahjongSolitaireRules.isFree(a, remaining: flags), "種 \(seed) の \(step) 手目の1枚目が取れない")
            #expect(MahjongSolitaireRules.isFree(b, remaining: flags), "種 \(seed) の \(step) 手目の2枚目が取れない")
            faces[a] = nil
            faces[b] = nil
            flags[a] = false
            flags[b] = false
        }
        #expect(faces.allSatisfy { $0 == nil }, "種 \(seed) の盤面を取り切れていない")
    }

    @Test("生成した盤面は必ず取り切れる（200通りの種で解法を再生して検証）")
    func generatedBoardsAreAlwaysSolvable() {
        for seed in UInt64(1)...200 {
            var generator = MahjongSeededGenerator(seed: seed)
            let board = MahjongSolitaireRules.generate(using: &generator)
            #expect(board.faces.compactMap { $0 }.count == 144, "種 \(seed) の盤面が144枚ではない")
            #expect(board.solution.count == 72, "種 \(seed) の解法が72手ではない")
            replay(board, seed: seed)
        }
    }

    @Test("生成した盤面の牌の内訳は標準の144枚と一致する")
    func generatedBoardUsesTheStandardDeck() {
        for seed in UInt64(1)...20 {
            var generator = MahjongSeededGenerator(seed: seed)
            let board = MahjongSolitaireRules.generate(using: &generator)
            var counts: [MahjongFace: Int] = [:]
            for face in board.faces.compactMap({ $0 }) { counts[face, default: 0] += 1 }
            var expected: [MahjongFace: Int] = [:]
            for face in MahjongSolitaireRules.facePairs().flatMap({ $0 }) { expected[face, default: 0] += 1 }
            #expect(counts == expected, "種 \(seed) の内訳が標準の144枚と違う")
        }
    }

    @Test("並べ替えは残った牌だけを使い、そこから必ず取り切れる")
    func rearrangeKeepsBoardSolvable() {
        var generator = MahjongSeededGenerator(seed: 99)
        let board = MahjongSolitaireRules.generate(using: &generator)

        // 解法の前半だけ進めた「途中の盤面」を作る。
        var faces = board.faces
        for pair in board.solution.prefix(30) {
            faces[pair[0]] = nil
            faces[pair[1]] = nil
        }
        let before = faces.compactMap { $0 }.count
        #expect(before == 144 - 60)

        guard let rearranged = MahjongSolitaireRules.rearrange(faces: faces, using: &generator) else {
            Issue.record("並べ替えに失敗した")
            return
        }
        #expect(rearranged.faces.indices.allSatisfy { (faces[$0] == nil) == (rearranged.faces[$0] == nil) },
                "牌のある場所は変わらない")

        var expected: [String: Int] = [:]
        for face in faces.compactMap({ $0 }) { expected[face.matchKey, default: 0] += 1 }
        var got: [String: Int] = [:]
        for face in rearranged.faces.compactMap({ $0 }) { got[face.matchKey, default: 0] += 1 }
        #expect(got == expected, "並べ替えで牌の内訳が変わっている")

        replay(rearranged, seed: 99)
    }

    @Test("取り切れない位置の組み合わせは並べ替えを断る")
    func rearrangeRefusesUnsolvablePositions() {
        // 上下に重なった2枚だけが残った状態は、絵柄をどう入れ替えても取り切れない。
        var faces = [MahjongFace?](repeating: nil, count: MahjongSolitaireRules.layout.count)
        guard let top = MahjongSolitaireRules.index(layer: 4, hx: 13, hy: 7),
              let under = MahjongSolitaireRules.index(layer: 3, hx: 12, hy: 6) else {
            Issue.record("レイアウトの位置が見つからない")
            return
        }
        faces[top] = .dragon(0)
        faces[under] = .dragon(0)
        var generator = MahjongSeededGenerator(seed: 5)
        #expect(MahjongSolitaireRules.rearrange(faces: faces, using: &generator) == nil)
    }
}
