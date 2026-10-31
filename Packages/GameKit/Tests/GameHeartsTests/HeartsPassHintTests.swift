import Testing
import Foundation
import Core
import CoreEngine
@testable import GameHearts
import CoreTestSupport

@MainActor
private func makeModel(seed: UInt64? = 42, store: SnapshotStore = MemorySnapshotStore()) -> HeartsModel {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: seed)
}

private func card(_ suit: HeartsSuit, _ rank: Int) -> HeartsCard {
    HeartsCard.makeDeck().first { $0.suit == suit && $0.rank == rank }!
}

@Suite("ハーツ: 渡す場面のヒント（#3003）")
@MainActor
struct HeartsPassHintTests {
    @Test("おすすめの 3 枚は手札の中から、毎回同じ札が選ばれる")
    func recommendationIsThreeCardsFromHand() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            var deck = HeartsCard.makeDeck()
            deck.shuffle(using: &rng)
            let hand = Array(deck.prefix(13))
            let picked = HeartsCPU.recommendedPass(hand: hand)
            #expect(picked.count == 3)
            #expect(Set(picked.map(\.id)).count == 3)
            #expect(picked.allSatisfy { hand.contains($0) })
            #expect(picked == HeartsCPU.recommendedPass(hand: hand))
        }
    }

    @Test("スペードのクイーンを低いスペードで守れないなら、クイーンと高いハートを渡す")
    func recommendationPassesDangerousCards() {
        let hand = [card(.spade, 12), card(.spade, 3), card(.heart, 14), card(.heart, 13),
                    card(.club, 2), card(.club, 5), card(.club, 9), card(.club, 11),
                    card(.diamond, 3), card(.diamond, 6), card(.diamond, 8), card(.diamond, 10), card(.diamond, 12)]
        let picked = Set(HeartsCPU.recommendedPass(hand: hand).map(\.id))
        #expect(picked.contains(card(.spade, 12).id))
        #expect(picked.contains(card(.heart, 14).id))
    }

    @Test("無料 3 回までは広告なしで光らせ、光った札が hint(for:) に出る")
    func freeHintHighlightsCards() {
        let model = makeModel()
        model.startMatch()
        #expect(model.canUseHint)
        #expect(!model.needsAdForHint)
        model.requestHint()
        #expect(model.passHints.used == 1)
        #expect(model.passHintIDs == Set(HeartsCPU.recommendedPass(hand: model.playerHand).map(\.id)))
        let lit = model.playerHand.filter { model.hint(for: $0, playable: []) == .recommendedPass }
        #expect(lit.count == 3)
        // 選択は勝手に変えない。
        #expect(model.passSelection.isEmpty)
        // 同じ手では 2 回目を使わせない。
        #expect(!model.canUseHint)
        model.requestHint()
        #expect(model.passHints.used == 1)
    }

    @Test("渡し終えると印は消え、次の手の渡す場面でまた使える")
    func hintClearsAfterPass() {
        let model = makeModel()
        model.startMatch()
        model.requestHint()
        for c in model.playerHand.prefix(3) { model.togglePass(c) }
        model.confirmPass()
        #expect(model.passHintIDs.isEmpty)
        #expect(!model.canUseHint)   // 出す場面では使えない
        #expect(model.hint(for: model.playerHand[0], playable: Set(model.playableCardIDs)) != .recommendedPass)
    }

    @Test("無料を使い切ると広告が要り、広告の 1 回は手が変わっていれば入らない")
    func adRefillAndStaleTurn() throws {
        let store = MemorySnapshotStore()
        try store.save(passingSnapshot(hintsUsed: BoardHintBudget.perGame), for: HeartsModel.gameID)
        let model = makeModel(store: store)
        #expect(model.phase == .passing)
        #expect(model.needsAdForHint)
        #expect(model.canUseHint)
        model.requestHint()                       // 広告なしでは入らない
        #expect(model.passHints.used == BoardHintBudget.perGame)
        #expect(model.passHintIDs.isEmpty)
        #expect(!model.grantAdHint(forTurn: model.turnSerial - 1))
        #expect(model.passHints.used == BoardHintBudget.perGame)
        #expect(model.grantAdHint(forTurn: model.turnSerial))
        #expect(model.passHints.used == BoardHintBudget.perGame + 1)
        #expect(!model.passHintIDs.isEmpty)
    }

    @Test("無料も広告も使い切ると押せない")
    func exhausted() throws {
        let store = MemorySnapshotStore()
        try store.save(passingSnapshot(hintsUsed: BoardHintBudget.total), for: HeartsModel.gameID)
        let model = makeModel(store: store)
        #expect(!model.canUseHint)
        #expect(!model.grantAdHint(forTurn: model.turnSerial))
    }

    @Test("ヒントを使った対局は順位表の対象から外れ、新しい対局で回数が戻る")
    func leaderboardAndReset() {
        let model = makeModel()
        model.startMatch()
        #expect(model.recordScore.isLeaderboardEligible)
        model.requestHint()
        #expect(!model.recordScore.isLeaderboardEligible)
        model.startMatch()
        #expect(model.passHints.used == 0)
        #expect(model.recordScore.isLeaderboardEligible)
    }

    @Test("使った回数は中断データに持ち回り、鍵の無い古い中断データは未使用として読む")
    func hintsUsedPersists() throws {
        let store = MemorySnapshotStore()
        try store.save(passingSnapshot(hintsUsed: 1), for: HeartsModel.gameID)
        let model = makeModel(store: store)
        #expect(model.passHints.used == 1)
        model.requestHint()
        #expect(model.passHints.used == 2)
        let restored = makeModel(store: store)
        #expect(restored.phase == .passing)
        #expect(restored.passHints.used == 2)
        // 光らせた 3 枚も持ち回り、戻したあとにもう 1 回使わせない（#3140）。
        #expect(restored.passHintIDs == model.passHintIDs)
        #expect(restored.passHintIDs.count == 3)
        #expect(!restored.canUseHint)
        restored.requestHint()
        #expect(restored.passHints.used == 2)

        let legacy = MemorySnapshotStore()
        try legacy.save(passingSnapshot(hintsUsed: nil), for: HeartsModel.gameID)
        #expect(makeModel(store: legacy).passHints.used == 0)
        #expect(makeModel(store: legacy).passHintIDs.isEmpty)

        // 手札に無い札を指す壊れた印は捨て、回数だけ戻す。
        let broken = MemorySnapshotStore()
        try broken.save(passingSnapshot(hintsUsed: 1, passHintIDs: [900, 901, 902]), for: HeartsModel.gameID)
        let brokenModel = makeModel(store: broken)
        #expect(brokenModel.passHintIDs.isEmpty)
        #expect(brokenModel.passHints.used == 1)
    }
}

/// 2 手目の渡す場面の中断データ（52 枚を 13 枚ずつ）。
private func passingSnapshot(hintsUsed: Int?, passHintIDs: [Int]? = nil) -> HeartsSnapshot {
    let deck = HeartsCard.makeDeck()
    let hands = (0..<4).map { Array(deck[($0 * 13)..<(($0 + 1) * 13)]) }
    return HeartsSnapshot(
        phase: .passing, hands: hands, currentTrick: [], currentPlayer: 0, heartsBroken: false, trickNumber: 0,
        takenPoints: [0, 0, 0, 0], totals: [10, 10, 3, 3], handNumber: 2, playedIDs: [], lastTrick: [],
        lastTrickWinner: nil, receivedIDs: [], aiLevel: 1, turnSerial: 5, hintsUsed: hintsUsed, passHintIDs: passHintIDs
    )
}
