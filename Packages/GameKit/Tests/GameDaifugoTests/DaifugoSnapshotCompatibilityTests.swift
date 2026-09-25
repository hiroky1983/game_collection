import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("大富豪: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct DaifugoSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"isRevolution":false,"lastRanking":[],"fouls":[],"fieldOwner":3,"finishOrder":[],"gameNumber":1\#
        ,"hands":[[{"suit":0,"id":3,"rank":4},{"suit":2,"id":29,"rank":4},{"suit":0,"id":4,"rank":5},{"s\#
        uit":0,"id":5,"rank":6},{"suit":2,"id":33,"rank":8},{"suit":0,"id":10,"rank":11},{"suit":1,"id":\#
        23,"rank":11},{"suit":2,"id":37,"rank":12},{"suit":2,"id":38,"rank":13},{"suit":2,"id":26,"rank"\#
        :1},{"suit":0,"id":1,"rank":2},{"suit":3,"id":40,"rank":2},{"id":52,"rank":0}],[{"suit":1,"id":1\#
        5,"rank":3},{"suit":0,"id":8,"rank":9},{"suit":2,"id":34,"rank":9},{"suit":3,"id":47,"rank":9},{\#
        "suit":0,"id":9,"rank":10},{"suit":2,"id":35,"rank":10},{"suit":2,"id":36,"rank":11},{"suit":3,"\#
        id":49,"rank":11},{"suit":1,"id":24,"rank":12},{"suit":0,"id":12,"rank":13},{"suit":1,"id":25,"r\#
        ank":13},{"suit":3,"id":39,"rank":1},{"id":53,"rank":0}],[{"suit":1,"id":16,"rank":4},{"suit":2,\#
        "id":30,"rank":5},{"suit":2,"id":31,"rank":6},{"suit":1,"id":19,"rank":7},{"suit":3,"id":45,"ran\#
        k":7},{"suit":1,"id":21,"rank":9},{"suit":0,"id":11,"rank":12},{"suit":0,"id":0,"rank":1},{"suit\#
        ":1,"id":13,"rank":1},{"suit":2,"id":27,"rank":2}],[{"suit":3,"id":42,"rank":4},{"suit":1,"id":1\#
        8,"rank":6},{"suit":3,"id":44,"rank":6},{"suit":2,"id":32,"rank":7},{"suit":0,"id":7,"rank":8},{\#
        "suit":1,"id":20,"rank":8},{"suit":1,"id":22,"rank":10},{"suit":3,"id":48,"rank":10},{"suit":3,"\#
        id":50,"rank":12},{"suit":3,"id":51,"rank":13},{"suit":1,"id":14,"rank":2}]],"lastActions":["3",\#
        "7","3 3","5 5"],"currentPlayer":0,"passedPlayers":[],"field":[{"suit":1,"id":17,"rank":5},{"sui\#
        t":3,"id":43,"rank":5}]}
        """#

    @Test("v1.1.6 の中断データを読み、手札・場・手番が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(DaifugoSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.hands.map(\.count) == [13, 13, 10, 11])
        #expect(snap.field.map(\.id) == [17, 43])
        #expect(snap.fieldOwner == 3)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "daifugo")
        let model = DaifugoModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 42
        )
        #expect(model.phase == .playing)
        #expect(model.hands.map(\.count) == [13, 13, 10, 11])
        #expect(model.field.map(\.id) == [17, 43])
        #expect(model.fieldOwner == 3)
        #expect(model.currentPlayer == 0)
    }
}
