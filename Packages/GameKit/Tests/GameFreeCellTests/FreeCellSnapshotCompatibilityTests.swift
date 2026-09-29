import Testing
import Foundation
import Core
@testable import GameFreeCell
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("フリーセル: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct FreeCellSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"seed":42,"elapsedSeconds":75,"undosRemaining":2,"moves":[{"tableauToCell":{"from":0,"cell":0}}\#
        ,{"tableauToCell":{"from":1,"cell":1}}]}
        """#

    @Test("v1.1.6 の中断データを読み、配り番号・手順・経過時間が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(FreeCellSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.seed == 42)
        #expect(snap.moves == [.tableauToCell(from: 0, cell: 0), .tableauToCell(from: 1, cell: 1)])
        #expect(snap.elapsedSeconds == 75)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "freecell")
        let model = FreeCellModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.dealNumber == 42)
        #expect(model.moveCount == 2)
        #expect(model.elapsedSeconds == 75)
        #expect(model.undosRemaining == 2)
        // 手順が再生されている = 2 枚がフリーセルに入っている（v1.1.6 で撮った札）
        #expect(model.board.cells.map { $0?.id } == [28, 51, nil, nil])
    }
}
