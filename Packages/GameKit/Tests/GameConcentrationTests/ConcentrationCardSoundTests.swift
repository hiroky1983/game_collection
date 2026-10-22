import Testing
import Foundation
import Core
@testable import GameConcentration
import CoreTestSupport

// 場面と効果音の対応（#2697）。札をめくるとき、合成音ではなく本物のカードの「めくる」音が鳴る。

@Suite("神経衰弱（カードの効果音 #2697）")
@MainActor
struct ConcentrationCardSoundTests {

    @Test("1 枚目をめくると「めくる」音が 1 回鳴る")
    func firstFlipPlaysFlip() throws {
        let feedback = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = ConcentrationModel(services: services, autoClearDelay: 40_000_000)
        model.newGame(pairCount: try #require(ConcentrationPairCount.allCases.first),
                      cpuLevel: try #require(ConcentrationCPULevel.allCases.first))
        feedback.reset()
        model.tap(index: 0)
        #expect(feedback.impacts == [.card(.flip)])
    }
}
