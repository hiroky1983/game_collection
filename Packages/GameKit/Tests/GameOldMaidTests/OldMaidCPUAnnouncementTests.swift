import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOldMaid

/// CPU が引いたときの読み上げ（#3424）。
@MainActor
@Suite("ババ抜き: CPU の動きの読み上げ")
struct OldMaidCPUAnnouncementTests {
    private func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
        OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
    }

    @Test("あなたの札を引かれたときは札の名前まで、CPU 同士は枚数だけ読む")
    func text() {
        let mine = OldMaidTransfer(from: 0, to: 2, card: card(.hearts, 5), paired: false)
        #expect(OldMaidAccessibility.cpuDrawAnnouncement(mine, drawerAction: .drewKept)
                == "CPU2があなたの\(OldMaidAccessibility.cardName(card(.hearts, 5)))を引きました")
        let other = OldMaidTransfer(from: 3, to: 1, card: card(.hearts, 5), paired: false)
        let text = OldMaidAccessibility.cpuDrawAnnouncement(other, drawerAction: .drewKept)
        #expect(text == "CPU1がCPU3から1枚引きました")
        #expect(!text.contains(OldMaidAccessibility.cardName(card(.hearts, 5))))   // 見えない札の名前は漏らさない
    }

    @Test("ペアができたら捨てたペアを添える")
    func pairAdded() {
        let transfer = OldMaidTransfer(from: 3, to: 1, card: card(.hearts, 5), paired: true)
        let text = OldMaidAccessibility.cpuDrawAnnouncement(transfer, drawerAction: .drewPair(rank: 5))
        #expect(text.hasPrefix("CPU1がCPU3から1枚引きました。"))
        #expect(text.hasSuffix(OldMaidAccessibility.actionText(.drewPair(rank: 5))))
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameOldMaid.tr("%1$@が%2$@から1枚引きました", "CPU1", "CPU3", language: .english) == "CPU1 drew a card from CPU3")
    }

    @Test("あなたが引いても控えは進まず、CPU が引くと進む")
    func eventAfterCPUDraw() async throws {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = OldMaidModel(services: services, cpuDelay: .zero, seed: 3)
        model.startGame()
        try #require(model.isPlayerTurn)
        let target = try #require(model.humanTarget)
        let cardID = try #require(model.game?.hands[target].first?.id)
        model.toggleSelection(cardID)
        model.drawSelected()
        model.declineRedraw()   // ジョーカーを引いて引き直しの返事待ちになっていても進める
        #expect(model.cpuEvent == nil)
        await model.runCPUTurnsIfNeeded()
        let event = try #require(model.cpuEvent)
        #expect(event.serial >= 1)
        #expect(event.text.hasPrefix("CPU"))
    }
}
