import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

// 場面と効果音の対応（#2697）。新しいゲームを始めたとき、合成音ではなく本物のカードの「切る」音が鳴る。

@Suite("大富豪: 切って配る（カードの効果音 #2697）")
@MainActor
struct DaifugoCardSoundTests {

    @Test("新しいゲームの開始で、カードを切る音が 1 回だけ鳴る")
    func startPlaysShuffle() {
        let feedback = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 42)
        feedback.reset()
        model.startGame()
        #expect(feedback.impacts == [.card(.shuffle)])
    }
}

// 革命・8切りの瞬間の合図と手応え（#2713）。

@Suite("大富豪: 革命・8切りの演出の合図（#2713）")
@MainActor
struct DaifugoFieldImpactTests {

    private func make(_ spy: SpyFeedbackService) -> DaifugoModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        return DaifugoModel(services: services, cpuDelay: .zero, seed: 42)
    }

    @Test("開始直後は合図が無い")
    func noImpactAtStart() {
        let model = make(SpyFeedbackService())
        model.startGame()
        #expect(model.fieldImpact == nil)
    }

    @Test("対局を最後まで進めると合図が出て、自分が起こしたときだけ強い手応えが鳴り、CPU の着手では触覚が増えない")
    func impactSerialCountsRevolutionAndEight() async {
        let spy = SpyFeedbackService()
        let model = make(spy)
        model.startGame()
        var seen: [FieldImpact] = []
        for _ in 0..<500 where model.phase == .playing {
            let before = spy.impacts.count
            await model.runCPUTurnsIfNeeded()
            #expect(spy.impacts.count == before, "CPU の着手は無音")
            if let impact = model.fieldImpact, seen.last != impact { seen.append(impact) }
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if let play = DaifugoRules.greedyPlay(
                hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
            ) {
                for card in play { model.toggleSelection(card) }
                let hits = DaifugoRules.clearsField(play) || DaifugoRules.triggersRevolution(play)
                let mediums = spy.impacts.filter { $0 == .medium }.count
                model.playSelected()
                let after = spy.impacts.filter { $0 == .medium }.count
                #expect((after - mediums) == (hits ? 1 : 0), "自分が起こしたときだけ強い手応え")
                if hits { #expect(model.fieldImpact?.byHuman == true) }
                if let impact = model.fieldImpact, seen.last != impact { seen.append(impact) }
            } else {
                model.pass()
            }
        }
        #expect(!seen.isEmpty, "1 ゲームの間に革命か 8切りが一度は起きる")
        // CPU が続けて打つ間は観測できない合図もあるので、連番は増える一方であることだけを見る。
        #expect(seen.map(\.serial) == seen.map(\.serial).sorted(), "連番は増える一方")
    }
}
