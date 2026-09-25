import Testing
import Foundation
import Core
@testable import GameHanafuda
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("花札: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct HanafudaSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"dealer":0,"hands":[[{"id":28},{"id":24},{"id":11},{"id":14},{"id":19},{"id":22},{"id":23},{"id\#
        ":43}],[{"id":12},{"id":46},{"id":44},{"id":0},{"id":6},{"id":32},{"id":8},{"id":25}]],"koiKoiCo\#
        unts":[0,0],"phase":"playing","deck":[{"id":15},{"id":34},{"id":5},{"id":16},{"id":7},{"id":30},\#
        {"id":36},{"id":27},{"id":17},{"id":42},{"id":31},{"id":1},{"id":18},{"id":20},{"id":10},{"id":4\#
        },{"id":3},{"id":41},{"id":33},{"id":37},{"id":9},{"id":39},{"id":26},{"id":21}],"message":"1局目・\#
        親はあなた","totals":[0,0],"field":[{"id":40},{"id":29},{"id":13},{"id":2},{"id":35},{"id":38},{"id":\#
        45},{"id":47}],"options":{"sakeYakuEnabled":false,"rounds":12,"difficulty":"normal"},"captured":\#
        [[],[]],"claimed":[0,0],"hasExtendedMatch":false,"round":1,"turn":0}
        """#

    @Test("v1.1.6 の中断データを読み、手札・場・山・試合設定が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(HanafudaSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.hands[0].map(\.id) == [28, 24, 11, 14, 19, 22, 23, 43])
        #expect(snap.phase == .playing)
        #expect(snap.options?.rounds == 12)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: HanafudaModel.gameID)
        let model = HanafudaModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 1
        )
        // 検証に落ちると `.idle`（新しい試合の前）になる
        #expect(model.phase == .playing)
        #expect(model.humanHand.map(\.id) == [28, 24, 11, 14, 19, 22, 23, 43])
        #expect(model.field.map(\.id) == [40, 29, 13, 2, 35, 38, 45, 47])
        #expect(model.deck.count == 24)
        #expect(model.options.rounds == 12)
        #expect(!model.options.sakeYakuEnabled)
    }
}
