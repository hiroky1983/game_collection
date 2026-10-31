import Foundation
import Testing
import Core
import CoreTestSupport
@testable import GameMahjong

/// ハブのタイルに出す進み具合（#3153）。
@Suite("麻雀の中断データの進み具合（#3153）")
@MainActor
struct MahjongResumeProgressTests {
    private func started(store: MemorySnapshotStore, length: MahjongGameLength) -> MahjongModel {
        let model = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 2026
        )
        model.startGame(length: length)
        return model
    }

    /// 保存済みの中断データの局番号だけを書き換える（南場の中断を作るため）。
    private func setRoundNumber(_ number: Int, in store: MemorySnapshotStore, id: String) throws {
        let snap = try #require(store.load(MahjongSnapshot.self, for: id))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any])
        json["roundNumber"] = number
        let data = try JSONSerialization.data(withJSONObject: json)
        try store.save(JSONDecoder().decode(MahjongSnapshot.self, from: data), for: id)
    }

    @Test("東風戦は「東n局」、半荘戦は 5 局目から「南n局」")
    func roundNames() throws {
        let module = MahjongModule()
        let store = MemorySnapshotStore()
        _ = started(store: store, length: .hanchan)
        try setRoundNumber(2, in: store, id: module.id)
        #expect(module.resumeProgress(in: store) == "東2局")
        try setRoundNumber(6, in: store, id: module.id)
        #expect(module.resumeProgress(in: store) == "南2局")

        let tonpuuStore = MemorySnapshotStore()
        _ = started(store: tonpuuStore, length: .tonpuu)
        try setRoundNumber(3, in: tonpuuStore, id: module.id)
        #expect(module.resumeProgress(in: tonpuuStore) == "東3局")
    }

    @Test("一局戦と中断データなしは出さない")
    func singleHandAndEmpty() {
        let module = MahjongModule()
        #expect(module.resumeProgress(in: MemorySnapshotStore()) == nil)
        let store = MemorySnapshotStore()
        _ = started(store: store, length: .singleHand)
        #expect(module.resumeProgress(in: store) == nil)
    }
}
