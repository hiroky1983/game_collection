import Testing
import Foundation
import Core
@testable import GameMahjong
import CoreTestSupport

/// 人数・山の位置が合わない中断データは消して新規開始に倒す（#1913。#1384 の取りこぼし）。
@Suite("麻雀の壊れた中断データ")
@MainActor
struct MahjongBrokenSnapshotTests {
    private func store(patching key: String, to jsonValue: String) throws -> MemorySnapshotStore {
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(MahjongSnapshotCompatibilityTests.v116JSON.utf8)) as? [String: Any])
        json[key] = try JSONSerialization.jsonObject(with: Data(jsonValue.utf8), options: .fragmentsAllowed)
        let store = MemorySnapshotStore()
        store.inject(try JSONSerialization.data(withJSONObject: json), for: "mahjong4")
        return store
    }

    private func open(_ store: MemorySnapshotStore) -> MahjongModel {
        MahjongModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 42)
    }

    @Test("手牌が 3 要素・山の位置が負や超過・手番が範囲外は、落ちずに新規開始し中断データを消す",
          arguments: [
            ("hands", "[{},{},{}]"),
            ("hands", "[]"),
            ("wallIndex", "-5"),
            ("wallIndex", "100000"),
            ("currentPlayer", "7"),
            ("scores", "[25000]"),
            ("melds", "[[]]"),
        ])
    func brokenSnapshotIsDiscarded(key: String, json: String) throws {
        let store = try store(patching: key, to: json)
        let model = open(store)
        #expect(model.hands.count == MahjongModel.playerCount)
        #expect(store.load(MahjongSnapshot.self, for: "mahjong4") == nil)
    }

    @Test("正常な中断データは捨てない（対照）")
    func validSnapshotIsKept() throws {
        let store = MemorySnapshotStore()
        store.inject(Data(MahjongSnapshotCompatibilityTests.v116JSON.utf8), for: "mahjong4")
        _ = open(store)
        #expect(store.load(MahjongSnapshot.self, for: "mahjong4") != nil)
    }
}
