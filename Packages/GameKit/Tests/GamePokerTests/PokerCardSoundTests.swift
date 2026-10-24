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

    @Test("「交換しない」では配る音を鳴らさず、1 枚でも替えたときだけ鳴る")
    func dealSoundOnlyWhenExchanged() {
        let feedback = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = PokerModel(services: services)
        model.startGame()
        feedback.reset()
        model.confirmExchange()
        #expect(!feedback.impacts.contains(.card(.deal)))
        #expect(feedback.impacts == [.light], "押せた手応えは .light 1 回（#2540）")

        // 同じ保存先だと前の局の中断データを復元してしまうので、別の組で始める。
        let feedback2 = SpyFeedbackService()
        let model2 = PokerModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback2))
        model2.startGame()
        model2.toggleCardSelection(model2.playerHand[0])
        feedback2.reset()
        model2.confirmExchange()
        #expect(feedback2.impacts.contains(.card(.deal)))
    }
}
