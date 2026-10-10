import Testing
import Foundation
import Core
@testable import GameFifteen
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("15パズル: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct FifteenSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"moves":37,"tiles":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,0,15]}
        """#

    @Test("v1.1.6 の中断データを読み、盤と手数が戻る")
    func restoresV116Snapshot() throws {
        let tiles = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0, 15]
        let snap = try JSONDecoder().decode(FifteenSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap == FifteenSnapshot(tiles: tiles, moves: 37))

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "fifteen")
        let model = FifteenModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.tiles == tiles)
        #expect(model.moves == 37)
        #expect(!model.isSolved)
    }
}

/// ヒント（#1975）で足した `hintsUsed` は鍵が無い中断データでも読める。
@Suite("15パズル: ヒント回数の中断データ（#1975）")
@MainActor
struct FifteenHintSnapshotTests {
    @Test("鍵を持たない v1.1.10 までの中断データは未使用として読む")
    func oldSnapshotHasNoHintsUsed() throws {
        let snap = try JSONDecoder().decode(FifteenSnapshot.self, from: Data(FifteenSnapshotCompatibilityTests.v116JSON.utf8))
        #expect(snap.hintsUsed == nil)
        let store = MemorySnapshotStore()
        store.inject(Data(FifteenSnapshotCompatibilityTests.v116JSON.utf8), for: "fifteen")
        let model = FifteenModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.hints.used == 0)
    }

    @Test("保存すると使った回数が鍵として書かれる")
    func savesHintsUsedKey() throws {
        let store = MemorySnapshotStore()
        let model = FifteenModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 3)
        model.requestHint()
        let data = try #require(store.rawData(for: "fifteen"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"hintsUsed\":1"))
    }
}
