import Testing
import Foundation
import Core
@testable import GameConcentration
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
///
/// 保存型 `ConcentrationSnapshot` は `private` で型として読めないので、`JSONDecoder` での読み込みは
/// Model の復元（`SnapshotStore.load` が内部で `JSONDecoder().decode` する）を通して確かめる。
/// 復元に失敗すると新しい盤（12 組）で始まるので、組数・取った札が戻っていれば読めている。
@Suite("神経衰弱: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct ConcentrationSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"symbols":["seaOtter","apple","camel","rabbit","camel","koala","rabbit","guitar","seaOtter","ap\#
        ple","gorilla","guitar","gorilla","drum","drum","koala"],"mattaUsed":false,"cpuScore":0,"mismatc\#
        hedIndices":[],"isMatched":[true,false,false,false,false,false,false,false,true,false,false,fals\#
        e,false,false,false,false],"pairCount":8,"playerScore":1,"currentPlayer":0,"cpuLevel":1,"isFaceU\#
        p":[true,true,false,false,false,false,false,false,true,false,false,false,false,false,false,false\#
        ]}
        """#

    @Test("v1.1.6 の中断データを読み、組数・取った札・得点・めくりかけの 1 枚が戻る")
    func restoresV116Snapshot() {
        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "concentration")
        let model = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.pairCount == .small)
        #expect(model.cards.count == 16)
        #expect(model.cards.indices.filter { model.cards[$0].isMatched } == [0, 8])
        #expect(model.playerScore == 1)
        #expect(model.cpuScore == 0)
        #expect(model.isHumanTurn)
        #expect(model.firstFlippedIndex == 1)
    }
}
