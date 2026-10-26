import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport

// 場面と効果音の対応（#2697）。配る・引くとき、合成音ではなく本物のカードの「配る」音が鳴る。

@Suite("ブラックジャック（カードの効果音 #2697）")
@MainActor
struct BlackjackCardSoundTests {

    @Test("最初に配る音と、ヒットで 1 枚引く音は、どちらも「配る」")
    func dealAndHitPlayDeal() throws {
        // ナチュラルで即決着する種を避けて、プレイヤーの番になる種を探す。
        for seed in UInt64(1)...40 {
            let feedback = SpyFeedbackService()
            let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
            let model = BlackjackModel(services: services, seed: seed)
            feedback.reset()
            model.deal()
            guard model.phase == .playerTurn else { continue }
            #expect(feedback.impacts == [.card(.deal)])
            feedback.reset()
            model.hit()
            if model.phase == .playerTurn { #expect(feedback.impacts == [.card(.deal)]) }
            return
        }
        Issue.record("プレイヤーの番になる種が見つからない")
    }
}
