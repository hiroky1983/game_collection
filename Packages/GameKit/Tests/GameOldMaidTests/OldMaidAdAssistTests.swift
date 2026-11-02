import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameOldMaid

private func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
    OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

/// 53 枚の整合を取った局面（手札に出さない札はペアで捨て札に入れる）。
private func scenario(_ hands: [[OldMaidCard]], currentPlayer: Int = 0) -> OldMaidGame {
    let used = Set(hands.flatMap { $0 })
    let rest = OldMaidCard.makeDeck().filter { !used.contains($0) && !$0.isJoker }
    let pairs = (1...13).flatMap { rank -> [[OldMaidCard]] in
        let same = rest.filter { $0.rank == rank }
        return stride(from: 0, to: same.count - 1, by: 2).map { [same[$0], same[$0 + 1]] }
    }
    return OldMaidGame(hands: hands, discardedPairs: pairs, currentPlayer: currentPlayer,
                       aiLevel: CPUStrength.hard.rawValue, tellSeed: 3)
}

/// あなたの番。CPU1 がジョーカーを持っている。
private func jokerScenario() -> OldMaidGame {
    scenario([
        [card(.spades, 2), card(.hearts, 5), card(.clubs, 9), card(.diamonds, 12)],
        [card(.hearts, 2), OldMaidCard.joker, card(.spades, 9), card(.clubs, 7)],
        [card(.clubs, 5), card(.spades, 7), card(.hearts, 11)],
        [card(.diamonds, 11), card(.clubs, 12)],
    ])
}

@MainActor
private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> OldMaidModel {
    let services = GameServices(snapshots: store, ads: NoopAdService(), feedback: SpyFeedbackService())
    return OldMaidModel(services: services, cpuDelay: .zero, seed: 7)
}

@MainActor
private func drawJoker(_ model: OldMaidModel) {
    model.toggleSelection(OldMaidCard.jokerID)
    model.drawSelected()
}

@Suite("ババ抜きの広告の助け（見破る・引き直し・#3251）")
@MainActor
struct OldMaidAdAssistTests {
    @Test("ジョーカーを引くと引き直しの返事待ちになり、CPU は返事まで動かない")
    func redrawOfferHoldsCPU() async {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        let before = model.cpuTurnKey
        drawJoker(model)
        #expect(model.canRedraw)
        #expect(model.cpuTurnKey != before)
        let held = model.game
        await model.runCPUTurnsIfNeeded()
        #expect(model.game == held, "返事待ちのあいだは CPU が引かない")
        #expect(!model.canShuffle, "混ぜると引く前の並びに戻せない")

        let waiting = model.cpuTurnKey
        model.declineRedraw()
        #expect(!model.canRedraw)
        #expect(model.cpuTurnKey != waiting, "断ると CPU の手番を起こす識別子が変わる")
        await model.runCPUTurnsIfNeeded()
        #expect(model.game != held, "断ったらそのまま CPU が進む")
    }

    @Test("ジョーカー以外を引いても引き直しは出ない")
    func noOfferForOrdinaryDraw() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        model.toggleSelection(card(.hearts, 2).id)
        model.drawSelected()
        #expect(!model.canRedraw)
    }

    @Test("引き直すと手札・相手の札・順番が引く前に戻り、そのターンだけジョーカーが見え、次に引くと消える")
    func redrawRestoresAndRevealsForOneTurn() async {
        let model = makeModel()
        let start = jokerScenario()
        model.configureForTesting(start)
        drawJoker(model)
        let turn = try! #require(model.redrawTurn)

        #expect(model.grantRedraw(forTurn: turn, gameNumber: model.gameNumber))
        #expect(model.game == start, "引く前の局面に戻る")
        #expect(model.isPlayerTurn && model.selectedID == nil)
        #expect(!model.canRedraw)
        #expect(model.revealsJoker)
        #expect(model.revealedIsJoker(OldMaidCard.jokerID) == true)
        #expect(model.revealedIsJoker(card(.hearts, 2).id) == nil, "見えるのはジョーカーだけ")

        // もう一度ジョーカーを引いても、1 回の引きにつき 1 回までなので引き直しは出ない。
        drawJoker(model)
        #expect(!model.canRedraw)
        #expect(!model.revealsJoker, "引いたら見えなくなる")
    }

    @Test("引き直したあと別の札を引くと、ジョーカーの表示は消える")
    func revealEndsAfterNextDraw() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        drawJoker(model)
        #expect(model.grantRedraw(forTurn: model.redrawTurn!, gameNumber: model.gameNumber))
        model.toggleSelection(card(.spades, 9).id)
        model.drawSelected()
        #expect(!model.revealsJoker)
        #expect(model.revealedIsJoker(OldMaidCard.jokerID) == nil)
    }

    @Test("広告のあいだに局面が変わっていたら引き直さない")
    func staleRedrawIsRejected() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        drawJoker(model)
        let turn = model.redrawTurn!
        #expect(!model.grantRedraw(forTurn: turn + 1, gameNumber: model.gameNumber))
        #expect(!model.grantRedraw(forTurn: turn, gameNumber: model.gameNumber + 1))
        model.declineRedraw()
        #expect(!model.grantRedraw(forTurn: turn, gameNumber: model.gameNumber), "断ったあとは戻せない")
    }

    @Test("見破る: 札がジョーカーかどうかを確実に教え、引くと消える")
    func peekRevealsAndClears() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        let turn = model.game!.turnSerial
        #expect(!model.canPeek, "札に指をかけていないと使えない")
        model.toggleSelection(OldMaidCard.jokerID)
        #expect(model.canPeek)
        #expect(model.grantPeek(forTurn: turn, cardID: OldMaidCard.jokerID, gameNumber: model.gameNumber))
        #expect(model.revealedIsJoker(OldMaidCard.jokerID) == true)
        #expect(!model.canPeek, "正体が見えている札には使えない")

        let safe = card(.hearts, 2).id
        model.toggleSelection(safe)
        #expect(model.canPeek)
        #expect(model.grantPeek(forTurn: turn, cardID: safe, gameNumber: model.gameNumber))
        #expect(model.revealedIsJoker(safe) == false)

        model.drawSelected()
        #expect(model.peekedIDs.isEmpty, "次のターンには持ち越さない")
    }

    @Test("見破る: 広告のあいだに番が進んでいたら見せない")
    func stalePeekIsRejected() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        let turn = model.game!.turnSerial
        #expect(!model.grantPeek(forTurn: turn + 1, cardID: OldMaidCard.jokerID, gameNumber: model.gameNumber))
        #expect(!model.grantPeek(forTurn: turn, cardID: 999, gameNumber: model.gameNumber), "相手の手札にない札")
    }

    @Test("中断して戻しても、見えているジョーカーと見破った札は保たれる")
    func assistsSurviveResume() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.configureForTesting(jokerScenario())
        drawJoker(model)
        #expect(model.grantRedraw(forTurn: model.redrawTurn!, gameNumber: model.gameNumber))
        let resumed = makeModel(store: store)
        #expect(resumed.revealsJoker)
        #expect(resumed.revealedIsJoker(OldMaidCard.jokerID) == true)

        let other = MemorySnapshotStore()
        let peeker = makeModel(store: other)
        peeker.configureForTesting(jokerScenario())
        peeker.toggleSelection(OldMaidCard.jokerID)
        #expect(peeker.grantPeek(forTurn: 0, cardID: OldMaidCard.jokerID, gameNumber: peeker.gameNumber))
        #expect(makeModel(store: other).peekedIDs == [OldMaidCard.jokerID])
    }

    @Test("使った局も通常どおり記録に入る（勝敗は引き直しの有無で変わらない）")
    func recordsAsUsual() {
        let model = makeModel()
        model.configureForTesting(jokerScenario())
        drawJoker(model)
        #expect(model.grantRedraw(forTurn: model.redrawTurn!, gameNumber: model.gameNumber))
        #expect(model.phase == .playing)
        #expect(model.recordScore.metric == .winLoss)
    }

    @Test("画面は見破る・引き直しを、局ガード・提示の計測つきの共通部品で結線している")
    func viewWiring() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameOldMaid"))
        #expect(code.contains("peekRescue.request(") && code.contains("purpose: .peek"))
        #expect(code.contains("redrawRescue.request(") && code.contains("purpose: .redraw"))
        #expect(code.contains(".rewardOffer(redrawRescue, for: .redraw, isPresented: model.canRedraw"))
        #expect(code.components(separatedBy: "guardedBy: .checkedByGrant").count - 1 == 2)
    }
}
