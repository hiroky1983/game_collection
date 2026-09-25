import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("麻雀: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct MahjongSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"melds":[[],[],[],[]],"turnCount":1,"scores":[25000,25000,25000,25000],"hasRevivedThisGame":fal\#
        se,"wall":[{"wind":{"_0":2}},{"circles":{"_0":8}},{"bamboos":{"_0":5}},{"circles":{"_0":5}},{"wi\#
        nd":{"_0":0}},{"bamboos":{"_0":8}},{"dragon":{"_0":1}},{"wind":{"_0":0}},{"circles":{"_0":4}},{"\#
        circles":{"_0":1}},{"circles":{"_0":5}},{"wind":{"_0":3}},{"circles":{"_0":4}},{"circles":{"_0":\#
        3}},{"bamboos":{"_0":6}},{"characters":{"_0":9}},{"circles":{"_0":2}},{"characters":{"_0":1}},{"\#
        characters":{"_0":1}},{"bamboos":{"_0":4}},{"bamboos":{"_0":6}},{"bamboos":{"_0":6}},{"character\#
        s":{"_0":2}},{"circles":{"_0":2}},{"circles":{"_0":9}},{"bamboos":{"_0":1}},{"bamboos":{"_0":7}}\#
        ,{"dragon":{"_0":2}},{"dragon":{"_0":0}},{"wind":{"_0":0}},{"bamboos":{"_0":3}},{"bamboos":{"_0"\#
        :2}},{"characters":{"_0":7}},{"bamboos":{"_0":4}},{"bamboos":{"_0":9}},{"characters":{"_0":4}},{\#
        "wind":{"_0":1}},{"bamboos":{"_0":5}},{"dragon":{"_0":0}},{"wind":{"_0":2}},{"bamboos":{"_0":3}}\#
        ,{"bamboos":{"_0":5}},{"circles":{"_0":6}},{"bamboos":{"_0":2}},{"characters":{"_0":7}},{"circle\#
        s":{"_0":1}},{"characters":{"_0":2}},{"bamboos":{"_0":9}},{"characters":{"_0":7}},{"bamboos":{"_\#
        0":4}},{"wind":{"_0":2}},{"characters":{"_0":1}},{"bamboos":{"_0":7}},{"circles":{"_0":8}},{"cha\#
        racters":{"_0":6}},{"bamboos":{"_0":9}},{"circles":{"_0":8}},{"wind":{"_0":1}},{"characters":{"_\#
        0":9}},{"dragon":{"_0":2}},{"characters":{"_0":3}},{"bamboos":{"_0":6}},{"circles":{"_0":8}},{"c\#
        ircles":{"_0":6}},{"circles":{"_0":1}},{"circles":{"_0":7}},{"dragon":{"_0":1}},{"wind":{"_0":0}\#
        },{"circles":{"_0":6}},{"circles":{"_0":3}},{"bamboos":{"_0":3}},{"characters":{"_0":6}},{"circl\#
        es":{"_0":1}},{"wind":{"_0":1}},{"characters":{"_0":8}},{"characters":{"_0":4}},{"wind":{"_0":2}\#
        },{"dragon":{"_0":1}},{"characters":{"_0":9}},{"characters":{"_0":4}},{"bamboos":{"_0":7}},{"dra\#
        gon":{"_0":2}},{"characters":{"_0":5}},{"bamboos":{"_0":8}},{"dragon":{"_0":2}},{"characters":{"\#
        _0":8}},{"dragon":{"_0":0}},{"bamboos":{"_0":8}},{"characters":{"_0":8}},{"characters":{"_0":1}}\#
        ,{"circles":{"_0":5}},{"dragon":{"_0":0}},{"circles":{"_0":9}},{"dragon":{"_0":1}},{"circles":{"\#
        _0":4}},{"circles":{"_0":7}},{"bamboos":{"_0":7}},{"characters":{"_0":3}},{"characters":{"_0":4}\#
        },{"circles":{"_0":2}},{"characters":{"_0":5}},{"characters":{"_0":7}},{"bamboos":{"_0":8}},{"ba\#
        mboos":{"_0":9}},{"wind":{"_0":3}},{"wind":{"_0":3}},{"characters":{"_0":8}},{"bamboos":{"_0":2}\#
        },{"characters":{"_0":6}},{"characters":{"_0":9}},{"circles":{"_0":2}},{"circles":{"_0":3}},{"ba\#
        mboos":{"_0":1}},{"circles":{"_0":7}},{"wind":{"_0":3}},{"circles":{"_0":7}},{"characters":{"_0"\#
        :5}},{"characters":{"_0":3}},{"characters":{"_0":2}},{"bamboos":{"_0":3}},{"circles":{"_0":4}},{\#
        "wind":{"_0":1}}],"honba":0,"roundNumber":1,"deadWall":[{"bamboos":{"_0":2}},{"bamboos":{"_0":1}\#
        },{"bamboos":{"_0":5}},{"bamboos":{"_0":4}},{"circles":{"_0":6}},{"characters":{"_0":2}},{"chara\#
        cters":{"_0":6}},{"circles":{"_0":3}},{"circles":{"_0":9}},{"circles":{"_0":5}},{"circles":{"_0"\#
        :9}},{"characters":{"_0":5}},{"bamboos":{"_0":1}},{"characters":{"_0":3}}],"endsAfterThisHand":f\#
        alse,"riichiSticks":0,"currentPlayer":0,"discardedKinds":[[],[],[],[]],"deadWallDraws":0,"gameLe\#
        ngth":"tonpuu","dealer":0,"wallIndex":53,"drawnTile":{"bamboos":{"_0":7}},"hands":[{"counts":[0,\#
        0,0,0,0,0,0,0,0,1,0,0,2,2,0,0,1,0,0,0,0,0,1,0,0,1,0,2,0,1,1,0,1,0]},{"counts":[2,1,0,0,0,0,0,0,1\#
        ,0,2,1,0,0,0,0,0,1,1,0,0,1,0,3,0,0,0,0,0,0,0,0,0,0]},{"counts":[0,0,0,1,0,0,1,0,0,0,0,0,0,0,0,0,\#
        0,0,0,1,1,1,1,0,1,0,1,1,1,0,0,2,0,1]},{"counts":[1,1,0,0,0,0,2,0,0,1,0,0,0,0,1,0,0,0,0,1,1,1,1,0\#
        ,0,0,1,0,0,2,0,0,0,0]}],"discards":[[],[],[],[]],"riichiFuriten":[false,false,false,false],"riic\#
        hi":[false,false,false,false],"revealedDoraCount":1,"hasExtendedGame":false}
        """#

    @Test("v1.1.6 の中断データを読み、配牌・ツモ牌・持ち点・残り枚数が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(MahjongSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.drawnTile == .bamboos(7))
        #expect(snap.scores == [25000, 25000, 25000, 25000])
        #expect(snap.wallIndex == 53)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "mahjong4")
        let model = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 1
        )
        #expect(model.phase == .playing)
        #expect(model.drawnTile == .bamboos(7))
        #expect(model.hands == snap.hands)
        #expect(model.scores == [25000, 25000, 25000, 25000])
        #expect(model.remainingTiles == 69)
        #expect(model.currentPlayer == 0)
        #expect(model.gameLength == .tonpuu)
    }
}
