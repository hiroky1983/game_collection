import Testing
import Foundation
import Core
@testable import GameSolitaire
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("ソリティア: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct SolitaireSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"seed":2,"elapsedSeconds":0,"jokerGrants":1,"moves":[{"draw":{}},{"draw":{}}],"undosRemaining":\#
        3,"drawMode":"one"}
        """#

    @Test("v1.1.6 の中断データを読み、配り・めくった山・ルールが戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(SolitaireSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.seed == 2)
        #expect(snap.moves == [.draw, .draw])
        #expect(snap.drawMode == "one")

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "solitaire")
        let model = SolitaireModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.pauseTimer()
        // 手順（2 回めくった）が再生されている
        #expect(model.board.waste.count == 2)
        #expect(model.board.stock.count == 22)
        #expect(model.rules.drawMode == .one)
        #expect(model.undosRemaining == 3)
    }
}
