import Testing
import Foundation
import Core
@testable import GamePoker
import CoreTestSupport

// 場面と効果音の対応（#2697）。新しいゲームを始めたとき、合成音ではなく本物のカードの「切る」音が鳴る。

@Suite("ポーカー: 切って配る（カードの効果音 #2697）")
@MainActor
struct PokerCardSoundTests {

    @Test("新しいゲームの開始で、カードを切る音が 1 回だけ鳴る")
    func startPlaysShuffle() {
        let feedback = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = PokerModel(services: services)
        feedback.reset()
        model.startGame()
        #expect(feedback.impacts == [.card(.shuffle)])
    }
}
