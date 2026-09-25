import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("2048: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct Game2048SnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"hasWon":false,"score":132,"continueUsed":true,"board":[[2,4,8,16],[0,2,0,0],[0,0,4,0],[0,0,0,2\#
        ]],"showWinPrompt":false}
        """#

    @Test("v1.1.6 の中断データを読み、盤・得点・コンティニュー使用済みが戻る")
    func restoresV116Snapshot() throws {
        let board = [[2, 4, 8, 16], [0, 2, 0, 0], [0, 0, 4, 0], [0, 0, 0, 2]]
        let snap = try JSONDecoder().decode(Game2048Snapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.board == board)
        #expect(snap.score == 132)
        #expect(snap.continueUsed)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "2048")
        let model = Game2048Model(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.board == board)
        #expect(model.score == 132)
        #expect(model.continueUsed)
        #expect(!model.gameOver)
    }
}
