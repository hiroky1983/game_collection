import Testing
import Foundation
import Core
@testable import GameBlocks
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("ブロック崩し: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct BlocksSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"score":1234,"lives":2,"stage":3,"continueUsed":true}
        """#

    @Test("v1.1.6 の中断データを読み、面・得点・残機が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(BlocksSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap == BlocksSnapshot(stage: 3, score: 1234, lives: 2, continueUsed: true))

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: BlocksModel.gameID)
        let name = "asobiba.blocks.tests.snapshot-compat"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let model = BlocksModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            preference: FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
        )
        #expect(model.stageNumber == 3)
        #expect(model.score == 1234)
        #expect(model.lives == 2)
        #expect(model.continueUsed)
    }
}
