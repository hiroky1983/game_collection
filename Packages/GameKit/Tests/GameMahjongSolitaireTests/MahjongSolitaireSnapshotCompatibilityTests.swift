import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("麻雀ソリティア: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct MahjongSolitaireSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"shuffleCount":0,"faces":[null,{"circles":{"_0":4}},{"wind":{"_0":3}},{"wind":{"_0":2}},{"drago\#
        n":{"_0":0}},{"bamboos":{"_0":6}},{"bamboos":{"_0":5}},{"circles":{"_0":9}},{"bamboos":{"_0":3}}\#
        ,{"flower":{"_0":3}},{"characters":{"_0":4}},{"bamboos":{"_0":8}},{"circles":{"_0":7}},{"bamboos\#
        ":{"_0":4}},{"circles":{"_0":9}},{"bamboos":{"_0":8}},{"wind":{"_0":0}},{"wind":{"_0":2}},{"char\#
        acters":{"_0":6}},{"flower":{"_0":1}},{"bamboos":{"_0":6}},{"dragon":{"_0":1}},{"wind":{"_0":1}}\#
        ,{"wind":{"_0":3}},{"bamboos":{"_0":9}},{"characters":{"_0":2}},{"bamboos":{"_0":9}},{"bamboos":\#
        {"_0":8}},{"season":{"_0":2}},{"circles":{"_0":2}},{"characters":{"_0":5}},{"dragon":{"_0":1}},{\#
        "season":{"_0":0}},{"wind":{"_0":3}},{"wind":{"_0":1}},{"bamboos":{"_0":6}},{"circles":{"_0":1}}\#
        ,{"circles":{"_0":1}},{"dragon":{"_0":0}},{"dragon":{"_0":2}},{"bamboos":{"_0":1}},{"circles":{"\#
        _0":9}},{"bamboos":{"_0":4}},{"bamboos":{"_0":7}},{"season":{"_0":1}},{"characters":{"_0":5}},{"\#
        characters":{"_0":1}},{"circles":{"_0":3}},{"circles":{"_0":1}},{"dragon":{"_0":2}},{"dragon":{"\#
        _0":2}},{"bamboos":{"_0":2}},{"bamboos":{"_0":4}},{"characters":{"_0":2}},{"characters":{"_0":5}\#
        },{"circles":{"_0":3}},{"circles":{"_0":2}},{"dragon":{"_0":2}},{"circles":{"_0":2}},{"wind":{"_\#
        0":1}},{"characters":{"_0":9}},{"circles":{"_0":5}},{"dragon":{"_0":0}},{"bamboos":{"_0":3}},{"c\#
        haracters":{"_0":4}},{"wind":{"_0":3}},{"characters":{"_0":3}},{"wind":{"_0":0}},{"characters":{\#
        "_0":3}},{"characters":{"_0":7}},{"characters":{"_0":9}},{"characters":{"_0":7}},{"bamboos":{"_0\#
        ":6}},{"characters":{"_0":4}},{"circles":{"_0":7}},{"characters":{"_0":8}},{"wind":{"_0":2}},{"b\#
        amboos":{"_0":1}},{"circles":{"_0":6}},{"circles":{"_0":8}},{"characters":{"_0":3}},{"bamboos":{\#
        "_0":2}},{"bamboos":{"_0":1}},{"circles":{"_0":7}},{"characters":{"_0":8}},{"flower":{"_0":2}},{\#
        "characters":{"_0":6}},{"bamboos":{"_0":7}},{"characters":{"_0":2}},{"bamboos":{"_0":3}},{"circl\#
        es":{"_0":4}},{"dragon":{"_0":0}},{"bamboos":{"_0":3}},{"wind":{"_0":0}},{"characters":{"_0":8}}\#
        ,{"circles":{"_0":8}},{"wind":{"_0":2}},{"bamboos":{"_0":2}},{"bamboos":{"_0":5}},null,{"circles\#
        ":{"_0":3}},{"bamboos":{"_0":1}},{"characters":{"_0":7}},{"characters":{"_0":5}},{"circles":{"_0\#
        ":4}},{"bamboos":{"_0":7}},{"bamboos":{"_0":7}},{"characters":{"_0":1}},{"circles":{"_0":6}},{"c\#
        ircles":{"_0":1}},{"bamboos":{"_0":4}},{"characters":{"_0":7}},{"characters":{"_0":2}},{"circles\#
        ":{"_0":6}},{"circles":{"_0":8}},{"bamboos":{"_0":5}},{"circles":{"_0":5}},{"bamboos":{"_0":8}},\#
        {"characters":{"_0":9}},{"bamboos":{"_0":9}},{"characters":{"_0":1}},{"bamboos":{"_0":2}},{"char\#
        acters":{"_0":6}},{"flower":{"_0":0}},{"bamboos":{"_0":5}},{"circles":{"_0":3}},{"characters":{"\#
        _0":4}},{"dragon":{"_0":1}},{"characters":{"_0":3}},{"circles":{"_0":8}},{"characters":{"_0":6}}\#
        ,{"wind":{"_0":0}},{"characters":{"_0":9}},{"wind":{"_0":1}},{"circles":{"_0":9}},{"circles":{"_\#
        0":2}},{"dragon":{"_0":1}},{"circles":{"_0":7}},{"season":{"_0":3}},{"bamboos":{"_0":9}},{"circl\#
        es":{"_0":4}},{"circles":{"_0":6}},{"characters":{"_0":1}},{"characters":{"_0":8}}],"elapsedSeco\#
        nds":0,"hintCount":0,"undoCount":0,"layoutID":"turtle"}
        """#

    @Test("v1.1.6 の中断データを読み、配置・取った牌・残り枚数が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(MahjongSolitaireSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.faces.count == MahjongSolitaireLayout.turtle.count)
        #expect(snap.faces.filter { $0 == nil }.count == 2)
        #expect(snap.layoutID == "turtle")

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "mahjong")
        let model = MahjongSolitaireModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 1)
        model.pauseTimer()
        #expect(model.layout == .turtle)
        #expect(model.faces == snap.faces)
        #expect(model.faces[0] == nil)
        #expect(model.faces[99] == nil)
        #expect(model.remainingCount == 142)
        #expect(model.phase == .playing)
    }
}
