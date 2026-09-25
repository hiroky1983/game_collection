import Testing
import Foundation
import Core
@testable import GameGo
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("囲碁: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct GoSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"size":9,"humanSide":0,"handicap":0,"undoUsed":true,"phase":0,"komi":6.5,"moves":[{"play":{"_0"\#
        :{"row":2,"col":2}}},{"play":{"_0":{"col":6,"row":6}}},{"play":{"_0":{"row":2,"col":6}}},{"pass"\#
        :{}}],"startedAt":780000000,"aiLevel":2}
        """#

    @Test("v1.1.6 の中断データを読み、盤・手数・強さ・待った使用済みが戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(GoSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.size == 9)
        #expect(snap.komi == 6.5)
        #expect(snap.moves == [.play(row: 2, col: 2), .play(row: 6, col: 6), .play(row: 2, col: 6), .pass])

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "go")
        let model = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.moveCount == 4)
        #expect(model.board.stoneCount == 3)
        #expect(model.humanSide == .black)
        #expect(model.aiLevel == .hard)
        #expect(model.phase == .playing)
        #expect(model.undoUsed)
    }
}
