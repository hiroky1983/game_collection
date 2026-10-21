import Testing
import Core
@testable import GameDaifugo
import CoreTestSupport

/// 交換の帯（#2607）。配った直後に「受け取った札・渡した札」を出すための値と読み上げ文。
@Suite("大富豪の交換の帯（#2607）")
@MainActor
struct DaifugoExchangeNoticeTests {

    private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> (DaifugoModel, GameServices) {
        let services = GameServices(snapshots: store, ads: NoopAdService())
        return (DaifugoModel(services: services, cpuDelay: .zero, seed: 42), services)
    }

    /// 1 ゲーム終えて 2 ゲーム目を配った直後のモデル（自分は必ず交換に関わる＝免除なし）。
    private func secondGame(store: SnapshotStore = MemorySnapshotStore()) -> (DaifugoModel, GameServices) {
        let (model, services) = makeModel(store: store)
        model.startGame()
        model.resign()
        model.startGame()
        return (model, services)
    }

    @Test("1 ゲーム目は交換が無いので帯を出さない")
    func firstGameHasNoNotice() {
        let (model, _) = makeModel()
        model.startGame()
        #expect(model.exchangeNotice == nil)
        #expect(model.exchangeNoticeRun == 0)
    }

    @Test("2 ゲーム目は実際に動いた札が帯の中身になる")
    func secondGameShowsActualCards() throws {
        let (model, _) = secondGame()
        let notice = try #require(model.exchangeNotice)
        let received = try #require(model.lastTransfers.first { $0.to == DaifugoModel.humanIndex })
        let gave = try #require(model.lastTransfers.first { $0.from == DaifugoModel.humanIndex })
        #expect(notice.received == received.cards)
        #expect(notice.gave == gave.cards)
        #expect(notice.partner == received.from)
        #expect(model.exchangeNoticeRun == 1)
    }

    @Test("閉じると消える。次のゲームの配りで改めて出る")
    func dismissAndRedeal() {
        let (model, _) = secondGame()
        model.dismissExchangeNotice()
        #expect(model.exchangeNotice == nil)
        model.resign()
        model.startGame()
        #expect(model.exchangeNotice != nil)
        #expect(model.exchangeNoticeRun == 2)
    }

    @Test("免除で自分の交換が起きないゲームでは出さない")
    func waivedGameHasNoNotice() {
        let (model, _) = makeModel()
        model.startGame()
        model.resign()
        #expect(model.waiveExchangeAfterAd(forGame: model.gameNumber))
        model.startGame()
        #expect(model.exchangeNotice == nil)
    }

    @Test("中断から再開した直後は出し直さない")
    func restoreDoesNotShowAgain() async throws {
        let store = MemorySnapshotStore()
        let (model, services) = secondGame(store: store)
        #expect(model.exchangeNotice != nil)
        // 1 手目を着手して中断データを保存させる（配りたての局は保存されない・#240）。
        await model.runCPUTurnsIfNeeded()
        try #require(model.isPlayerTurn)
        model.toggleSelection(try #require(model.playerHand.first))
        model.playSelected()
        try #require(store.exists(for: "daifugo"))

        let reopened = DaifugoModel(services: services, cpuDelay: .zero)
        #expect(reopened.phase == .playing)
        #expect(reopened.exchangeNotice == nil)
        #expect(reopened.exchangeNoticeRun == 0)
    }

    @Test("画面の文は記号、読み上げはスートの読み。受け取り→渡しの順で 2 行")
    func lines() {
        let notice = DaifugoExchangeNotice(
            transfers: [
                DaifugoTransfer(from: 2, to: 0, cards: [DaifugoCard(id: 0, suit: .spades, rank: 1), DaifugoCard(id: 1, suit: .diamonds, rank: 2)]),
                DaifugoTransfer(from: 0, to: 2, cards: [DaifugoCard(id: 2, suit: .clubs, rank: 3), DaifugoCard(id: 3, suit: .hearts, rank: 4)]),
            ], human: 0)
        let shown = notice.map { DaifugoAccessibility.exchangeLines($0, partnerName: "CPU2", spoken: false) }
        #expect(shown == ["CPU2から ♠A ♦2 を受け取りました", "CPU2へ ♣3 ♥4 を渡しました"])
        let spoken = notice.map { DaifugoAccessibility.exchangeLines($0, partnerName: "CPU2", spoken: true) }
        #expect(spoken?.count == 2)
        #expect(spoken?[0].contains("スペードのエース") == true)
        #expect(spoken?[1].contains("クラブの3") == true)
    }

    @Test("自分が関わらない交換だけなら nil")
    func notInvolved() {
        let t = DaifugoTransfer(from: 1, to: 2, cards: [DaifugoCard(id: 0, suit: .spades, rank: 1)])
        #expect(DaifugoExchangeNotice(transfers: [t], human: 0) == nil)
    }
}
