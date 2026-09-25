import Testing
import Foundation
import Core
@testable import GameSpider
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("スパイダー: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct SpiderSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"undosRemaining":3,"elapsedSeconds":0,"seed":3,"suitCount":2,"moves":[{"deal":{}}]}
        """#

    @Test("v1.1.6 の中断データを読み、配り・スート数・配った山が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(SpiderSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.seed == 3)
        #expect(snap.suitCount == 2)
        #expect(snap.moves == [.deal])

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "spider")
        let model = SpiderModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.dealNumber == 3)
        #expect(model.rules.suitCount == .two)
        #expect(model.moveCount == 1)
        #expect(model.board.stock.count == 4)
    }
}
