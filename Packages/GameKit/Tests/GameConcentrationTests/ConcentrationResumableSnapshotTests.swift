import Foundation
import Testing
import Core
import CoreTestSupport
@testable import GameConcentration

/// 一枚もめくっていない盤は「続きから」に出さない（#1847）。
@Suite("神経衰弱の「続きから」判定（#1847）")
@MainActor
struct ConcentrationResumableSnapshotTests {
    @Test("開いただけでは続きではなく、一枚めくると続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ConcentrationModule()
        let model = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(index: 0)
        #expect(module.hasResumableSnapshot(in: store), "一枚めくった盤（対照）")
    }

    @Test("外して伏せ直した盤（全部伏せ・0 対 0）も続きになる。再読み込みしても保たれる（#3337）")
    func mismatchedAndFlippedBackIsResumable() {
        let store = MemorySnapshotStore()
        let module = ConcentrationModule()
        let model = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        let first = 0
        let second = model.cards.indices.first { model.cards[$0].symbol != model.cards[first].symbol }!
        model.tap(index: first)
        model.tap(index: second)
        model.clearMismatch()
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
        let restored = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.hasProgressToLose)
    }

    @Test("手番が進んだ記録の鍵が無い旧い中断データは従来どおり手つかず扱い（#3337）")
    func legacySnapshotWithoutTurnsKeyStaysUntouched() throws {
        let store = MemorySnapshotStore()
        let module = ConcentrationModule()
        let model = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        let data = try #require(store.rawData(for: "concentration"))
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "turnsPlayed")
        store.inject(try JSONSerialization.data(withJSONObject: obj), for: "concentration")
        #expect(module.hasUntouchedSnapshot(in: store))
    }
}
