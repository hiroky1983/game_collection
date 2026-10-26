import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

// MARK: - ルール層（#2605 しばり）

@Suite("しばり（ルール）")
struct DaifugoBindRulesTests {
    private let on = DaifugoRuleSet(isBindEnabled: true)

    @Test("同じスートが2回続くとしばりが掛かる。スートが違えば掛からない")
    func triggersOnSameSuitTwice() {
        let bound = DaifugoRules.nextBindSuits(current: [], field: [card(5, .spades)], played: [card(6, .spades)], ruleSet: on)
        #expect(bound == [.spades])
        let free = DaifugoRules.nextBindSuits(current: [], field: [card(5, .spades)], played: [card(6, .hearts)], ruleSet: on)
        #expect(free.isEmpty)
    }

    @Test("場が空（親の最初の1手）ではしばりは掛からない")
    func leadDoesNotBind() {
        let result = DaifugoRules.nextBindSuits(current: [], field: [], played: [card(5, .spades)], ruleSet: on)
        #expect(result.isEmpty)
    }

    @Test("ペアは出した組のスートの集合が一致したときだけ掛かる")
    func pairNeedsSameSuitSet() {
        let field = [card(5, .spades), card(5, .hearts)]
        let same = DaifugoRules.nextBindSuits(current: [], field: field, played: [card(6, .spades), card(6, .hearts)], ruleSet: on)
        #expect(same == [.spades, .hearts])
        let other = DaifugoRules.nextBindSuits(current: [], field: field, played: [card(6, .spades), card(6, .clubs)], ruleSet: on)
        #expect(other.isEmpty)
    }

    @Test("ジョーカーだけの組はしばりを作りも解きもしない")
    func jokerNeitherCreatesNorBreaks() {
        let none = DaifugoRules.nextBindSuits(current: [], field: [card(5, .spades)], played: [joker()], ruleSet: on)
        #expect(none.isEmpty)
        let kept = DaifugoRules.nextBindSuits(current: [.spades], field: [card(5, .spades)], played: [joker()], ruleSet: on)
        #expect(kept == [.spades])
    }

    @Test("オフのときは何があってもしばりは掛からない")
    func disabledNeverBinds() {
        let result = DaifugoRules.nextBindSuits(
            current: [], field: [card(5, .spades)], played: [card(6, .spades)], ruleSet: .standard
        )
        #expect(result.isEmpty)
    }

    @Test("しばり中は別のスートが出せず、ジョーカーは出せる。理由が返る")
    func bindRestrictsPlays() {
        let field = [card(5, .spades)]
        let bind: Set<DaifugoSuit> = [.spades]
        #expect(DaifugoRules.isValidPlay([card(9, .spades)], field: field, isRevolution: false, bindSuits: bind))
        #expect(!DaifugoRules.isValidPlay([card(9, .hearts)], field: field, isRevolution: false, bindSuits: bind))
        #expect(DaifugoRules.isValidPlay([joker()], field: field, isRevolution: false, bindSuits: bind))
        // しばりなしなら出せる（オフのときは今と同じ）。
        #expect(DaifugoRules.isValidPlay([card(9, .hearts)], field: field, isRevolution: false))
        #expect(DaifugoRules.rejectionReason([card(9, .hearts)], field: field, isRevolution: false, bindSuits: bind) != nil)
        #expect(DaifugoRules.rejectionReason([card(9, .spades)], field: field, isRevolution: false, bindSuits: bind) == nil)
    }

    @Test("革命中もしばりは同じように効く")
    func bindWorksInRevolution() {
        let field = [card(9, .spades)]
        let bind: Set<DaifugoSuit> = [.spades]
        #expect(DaifugoRules.isValidPlay([card(4, .spades)], field: field, isRevolution: true, bindSuits: bind))
        #expect(!DaifugoRules.isValidPlay([card(4, .hearts)], field: field, isRevolution: true, bindSuits: bind))
    }

    @Test("ヒントと CPU の候補もしばりに従う")
    func hintAndCPUFollowBind() {
        let hand = [card(7, .hearts), card(9, .spades), card(11, .clubs)]
        let field = [card(5, .spades)]
        let bind: Set<DaifugoSuit> = [.spades]
        let playable = DaifugoRules.playableCardIDs(hand: hand, field: field, isRevolution: false, bindSuits: bind)
        #expect(playable == [card(9, .spades).id])
        let plays = DaifugoRules.legalPlays(hand: hand, field: field, isRevolution: false, bindSuits: bind)
        #expect(plays == [[card(9, .spades)]])
        // 弱い 7♥ ではなく、しばりに合う 9♠ を選ぶ。
        #expect(DaifugoRules.greedyPlay(hand: hand, field: field, isRevolution: false, bindSuits: bind) == [card(9, .spades)])
        // 出せる札が無ければ nil（パス）。
        let stuck = DaifugoRules.greedyPlay(hand: [card(7, .hearts)], field: field, isRevolution: false, bindSuits: bind)
        #expect(stuck == nil)
    }

    @Test("しばりのスートでペアを作るときはジョーカーが足りない分を埋める")
    func jokerFillsBoundPair() {
        let field = [card(5, .spades), card(5, .hearts)]
        let bind: Set<DaifugoSuit> = [.spades, .hearts]
        let hand = [card(9, .spades), card(9, .clubs), joker()]
        let plays = DaifugoRules.legalPlays(hand: hand, field: field, isRevolution: false, bindSuits: bind)
        #expect(plays.contains { Set($0.map(\.id)) == [card(9, .spades).id, joker().id] })
        #expect(!plays.contains { $0.contains(card(9, .clubs)) })
    }
}

// MARK: - Model（#2605 しばり）

@Suite("しばり（進行・保存）")
@MainActor
struct DaifugoBindModelTests {
    private func make(store: SnapshotStore = MemorySnapshotStore()) -> (DaifugoModel, SnapshotStore) {
        let services = GameServices(snapshots: store, ads: NoopAdService())
        return (DaifugoModel(services: services, cpuDelay: .zero, seed: 1), store)
    }

    private let hands: [[DaifugoCard]] = [
        [card(6, .spades), card(9, .hearts), card(10, .spades)],
        [card(4, .clubs), card(12, .clubs)],
        [card(3, .diamonds), card(13, .clubs)],
        [card(3, .hearts), card(1, .clubs)],
    ]

    @Test("同じスートが続いたらしばりが掛かり、場が流れたら解ける")
    func bindsThenReleasesOnClear() {
        let (model, _) = make()
        model.configureForTesting(
            hands: hands, field: [card(5, .spades)], fieldOwner: 1,
            currentPlayer: 0, ruleSet: DaifugoRuleSet(isBindEnabled: true)
        )
        model.toggleSelection(card(6, .spades))
        model.playSelected()
        #expect(model.bindSuits == [.spades])
        #expect(model.field == [card(6, .spades)])
    }

    @Test("8切りで場が流れるとしばりも解ける")
    func eightCutReleasesBind() {
        let (model, _) = make()
        model.configureForTesting(
            hands: [[card(8, .spades), card(9, .hearts)], [card(4, .clubs)], [card(3, .diamonds)], [card(3, .hearts)]],
            field: [card(5, .spades)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isBindEnabled: true), bindSuits: [.spades]
        )
        model.toggleSelection(card(8, .spades))
        model.playSelected()
        #expect(model.field.isEmpty)
        #expect(model.bindSuits.isEmpty)
    }

    @Test("しばり中は別スートを選んでも出せない")
    func cannotPlayOtherSuitWhileBound() {
        let (model, _) = make()
        model.configureForTesting(
            hands: hands, field: [card(5, .spades)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isBindEnabled: true), bindSuits: [.spades]
        )
        model.toggleSelection(card(9, .hearts))
        #expect(!model.canPlaySelection)
        model.clearSelection()
        model.toggleSelection(card(10, .spades))
        #expect(model.canPlaySelection)
    }

    @Test("オフの局ではしばりは掛からない")
    func offNeverBinds() {
        let (model, _) = make()
        model.configureForTesting(hands: hands, field: [card(5, .spades)], fieldOwner: 1, currentPlayer: 0)
        model.toggleSelection(card(6, .spades))
        model.playSelected()
        #expect(model.bindSuits.isEmpty)
    }

    @Test("中断→再開でルールとしばりが保たれる")
    func snapshotKeepsRuleAndBind() {
        let (model, store) = make()
        model.configureForTesting(
            hands: hands, field: [card(5, .spades)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isBindEnabled: true), bindSuits: [.spades]
        )
        let (restored, _) = make(store: store)
        #expect(restored.phase == .playing)
        #expect(restored.ruleSet.isBindEnabled)
        #expect(restored.bindSuits == [.spades])
    }

    @Test("選んだルールは次のゲームに焼き込まれ、再起動しても引き継がれる")
    func preferredRuleSetIsBakedAndPersisted() {
        let (model, store) = make()
        #expect(!model.preferredRuleSet.isBindEnabled, "既定はオフ")
        model.choosePreferredRuleSet(DaifugoRuleSet(isBindEnabled: true))
        model.startGame()
        #expect(model.ruleSet.isBindEnabled)
        // 対局中に選び直しても、今の局は変わらない（1 局 = 1 RuleSet）。
        model.choosePreferredRuleSet(.standard)
        #expect(model.ruleSet.isBindEnabled)

        let (reopened, _) = make(store: store)
        #expect(!reopened.preferredRuleSet.isBindEnabled)
        model.choosePreferredRuleSet(DaifugoRuleSet(isBindEnabled: true))
        let (again, _) = make(store: store)
        #expect(again.preferredRuleSet.isBindEnabled)
    }
}
