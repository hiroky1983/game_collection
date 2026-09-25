import Testing
import Foundation
import Core
@testable import GameRunner
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("ランナー: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct RunnerSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"reachedStage":12,"bestSeconds":[],"stage":7}
        """#

    @Test("v1.1.6 の中断データを読み、再開する面と到達面が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(RunnerSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap == RunnerSnapshot(stage: 7, bestSeconds: [], reachedStage: 12))

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: RunnerModel.gameID)
        let model = RunnerModel(services: makeServices(store: store), preference: makePreference("snapshot-compat"))
        #expect(model.stageNumber == 7)
        #expect(model.reachedStage == 12)
    }
}
