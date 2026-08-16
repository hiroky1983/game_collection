import Testing
import Foundation
@testable import MahjongTiles

@Suite("標準 34 種")
struct MahjongTileTests {
    @Test("標準牌は 34 種で重複が無い")
    func allIsThirtyFourUniqueTiles() {
        #expect(MahjongTile.all.count == 34)
        #expect(Set(MahjongTile.all).count == 34)
        #expect(Set(MahjongTile.all.map(\.key)).count == 34)
    }

    @Test("数牌は 1〜9 の数を持ち、字牌は持たない")
    func rankOnlyForSuits() {
        #expect(MahjongTile.circles(5).rank == 5)
        #expect(MahjongTile.bamboos(9).rank == 9)
        #expect(MahjongTile.characters(1).rank == 1)
        #expect(MahjongTile.wind(0).rank == nil)
        #expect(MahjongTile.dragon(2).rank == nil)
    }
}

@Suite("絵柄（標準 34 種＋ソリティア専用牌）")
struct MahjongFaceTests {
    @Test("標準牌とソリティア専用牌を型で区別できる")
    func standardTileDistinguishesSolitaireOnlyFaces() {
        #expect(MahjongFace.circles(3).standardTile == .circles(3))
        #expect(MahjongFace.dragon(2).standardTile == .dragon(2))
        // 花牌・季節牌はソリティア専用なので標準牌としては取り出せない（四人打ち麻雀に混ざらない）。
        #expect(MahjongFace.flower(0).standardTile == nil)
        #expect(MahjongFace.season(3).standardTile == nil)
    }

    @Test("糖衣コンストラクタは .standard で包んだ値と同じ")
    func sugarMatchesStandardCase() {
        #expect(MahjongFace.characters(7) == .standard(.characters(7)))
        #expect(MahjongFace.wind(1) == .standard(.wind(1)))
    }

    @Test("マッチ判定は移設前と同じ")
    func matchingIsUnchanged() {
        #expect(MahjongFace.circles(3).matches(.circles(3)))
        #expect(MahjongFace.flower(0).matches(.flower(3)), "花牌は絵柄が違っても合う")
        #expect(MahjongFace.season(1).matches(.season(2)), "季節牌は絵柄が違っても合う")
        #expect(!MahjongFace.flower(0).matches(.season(0)), "花牌と季節牌は合わない")
        #expect(!MahjongFace.characters(1).matches(.circles(1)), "数字が同じでも種類が違えば合わない")
    }

    /// `.standard` を挟んだことで JSON 表現が変わると、`FileSnapshotStore.load` が
    /// デコードに失敗して nil を返し、遊びかけの盤面が黙って消える。表現の固定はその防波堤。
    @Test("中断スナップショットの JSON 表現が移設前と同じ")
    func codableWireFormatIsStable() throws {
        let faces: [MahjongFace?] = [.characters(1), .circles(9), .bamboos(5),
                                     .wind(3), .dragon(2), .flower(0), .season(2), nil]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(data: try encoder.encode(faces), encoding: .utf8)
        #expect(json == #"[{"characters":{"_0":1}},{"circles":{"_0":9}},{"bamboos":{"_0":5}},"#
                      + #"{"wind":{"_0":3}},{"dragon":{"_0":2}},{"flower":{"_0":0}},"#
                      + #"{"season":{"_0":2}},null]"#)
    }

    @Test("移設前に保存した盤面をそのまま読める")
    func decodesLegacySnapshot() throws {
        let legacy = #"[{"characters":{"_0":4}},{"flower":{"_0":1}},null]"#
        let decoded = try JSONDecoder().decode([MahjongFace?].self, from: Data(legacy.utf8))
        #expect(decoded == [.standard(.characters(4)), .flower(1), nil])
    }

    @Test("種類が読み取れない JSON は素直に失敗する")
    func rejectsMalformedJSON() {
        let broken = #"{"characters":{"_0":1},"circles":{"_0":1}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MahjongFace.self, from: Data(broken.utf8))
        }
    }

    @Test("値域内の牌はすべて有効と判定される")
    func validRanges() {
        let standardAllValid = MahjongTile.all.allSatisfy(\.isValid)
        let solitaireAllValid = (0..<4).allSatisfy {
            MahjongFace.flower($0).isValid && MahjongFace.season($0).isValid
        }
        #expect(standardAllValid)
        #expect(solitaireAllValid)
        // 値域外（数牌の 0 と 10、風牌の 4、三元牌の 3、花牌・季節牌の 4 と -1）。
        #expect(!MahjongTile.characters(0).isValid)
        #expect(!MahjongTile.circles(10).isValid)
        #expect(!MahjongTile.wind(4).isValid)
        #expect(!MahjongTile.dragon(3).isValid)
        #expect(!MahjongFace.flower(4).isValid)
        #expect(!MahjongFace.season(-1).isValid)
    }

    /// 値域外の牌は描画時に近い値へ丸められるため、そのまま読むと別の牌に化けた盤面になる。
    @Test("値域外の数を含む JSON はデコードで拒否する", arguments: [
        #"{"characters":{"_0":0}}"#,
        #"{"circles":{"_0":10}}"#,
        #"{"bamboos":{"_0":-1}}"#,
        #"{"wind":{"_0":4}}"#,
        #"{"dragon":{"_0":3}}"#,
        #"{"flower":{"_0":4}}"#,
        #"{"season":{"_0":-1}}"#,
    ])
    func rejectsOutOfRangeValues(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MahjongFace.self, from: Data(json.utf8))
        }
    }
}
