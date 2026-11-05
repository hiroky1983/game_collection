import Foundation
import Testing
import Core
import CoreTestSupport
@testable import GameHanafuda

/// ハブのタイルに出す進み具合（#3153）。
@Suite("花札の中断データの進み具合（#3153）")
@MainActor
struct HanafudaResumeProgressTests {
    private func setRound(_ round: Int, in store: MemorySnapshotStore) throws {
        let snap = try #require(store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any])
        json["round"] = round
        let data = try JSONSerialization.data(withJSONObject: json)
        try store.save(JSONDecoder().decode(HanafudaSnapshot.self, from: data), for: HanafudaModel.gameID)
    }

    @Test("「n / 全局数局」、延長した局は「延長戦」、中断データなしは出さない")
    func roundOfTotal() throws {
        let module = HanafudaModule()
        #expect(module.resumeProgress(in: MemorySnapshotStore()) == nil)

        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.startMatch(options: HanafudaOptions())
        let rounds = model.options.rounds
        #expect(module.resumeProgress(in: store) == "1 / \(rounds)局")
        try setRound(3, in: store)
        #expect(module.resumeProgress(in: store) == "3 / \(rounds)局")
        try setRound(rounds + 1, in: store)
        #expect(module.resumeProgress(in: store) == "延長戦")
    }
}
