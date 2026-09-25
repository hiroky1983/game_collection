import Testing
import Foundation
import Core
@testable import GameBlockPuzzle
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("ブロックパズル: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct BlockPuzzleSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"board":[[5,5,5,5,5,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0\#
        ],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0],[0,0,0\#
        ,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0]],"combo":0,"continueUsed":false,"hand":[null,0,17],"score"\#
        :5}
        """#

    @Test("v1.1.6 の中断データを読み、盤・手札・得点が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(BlockPuzzleSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.board[0] == [5, 5, 5, 5, 5, 0, 0, 0, 0, 0])
        #expect(snap.hand == [nil, 0, 17])
        #expect(snap.score == 5)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: BlockPuzzleModel.gameID)
        let model = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.board == snap.board)
        #expect(model.hand.map { $0 == nil } == [true, false, false])
        #expect(model.score == 5)
        #expect(!model.gameOver)
    }
}
