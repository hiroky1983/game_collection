import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

/// 人数・添字が合わない中断データは消して新規開始に倒す（#1913。#1384 の取りこぼし）。
@Suite("大富豪の壊れた中断データ")
@MainActor
struct DaifugoBrokenSnapshotTests {
    /// 正常な中断データ（v1.1.6 の実データ）の鍵を 1 つ書き換えたものを入れた店。
    private func store(patching key: String, to jsonValue: String) throws -> MemorySnapshotStore {
        var json = try #require(
            JSONSerialization.jsonObject(with: Data(DaifugoSnapshotCompatibilityTests.v116JSON.utf8)) as? [String: Any])
        json[key] = try JSONSerialization.jsonObject(with: Data(jsonValue.utf8), options: .fragmentsAllowed)
        let store = MemorySnapshotStore()
        store.inject(try JSONSerialization.data(withJSONObject: json), for: "daifugo")
        return store
    }

    private func open(_ store: MemorySnapshotStore) -> DaifugoModel {
        DaifugoModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 42)
    }

    @Test("手札が空・人数違い・手番が範囲外・順位が範囲外は、落ちずに新規開始し中断データを消す",
          arguments: [
            ("hands", "[]"),
            ("hands", "[[],[],[]]"),
            ("currentPlayer", "9"),
            ("currentPlayer", "-1"),
            ("finishOrder", "[7]"),
            ("passedPlayers", "[4]"),
        ])
    func brokenSnapshotIsDiscarded(key: String, json: String) throws {
        let store = try store(patching: key, to: json)
        let model = open(store)
        #expect(model.phase == .idle)
        #expect(model.hands.count == DaifugoModel.playerCount)
        #expect(store.load(DaifugoSnapshot.self, for: "daifugo") == nil)
    }

    @Test("正常な中断データは捨てない（対照）")
    func validSnapshotIsKept() throws {
        let store = MemorySnapshotStore()
        store.inject(Data(DaifugoSnapshotCompatibilityTests.v116JSON.utf8), for: "daifugo")
        let model = open(store)
        #expect(model.phase == .playing)
        #expect(store.load(DaifugoSnapshot.self, for: "daifugo") != nil)
    }
}
