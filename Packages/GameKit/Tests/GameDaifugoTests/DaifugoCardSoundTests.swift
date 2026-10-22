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
