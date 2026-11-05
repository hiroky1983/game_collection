import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

// MARK: - ルールセット（#2721）

@Suite("ローカルルールの選択（保存・既定）")
struct DaifugoRuleSetTests {
    @Test("既定は従来の採用ルール（8切り・反則上がりあり、しばり・階段・都落ちなし）")
    func standardMatchesLegacy() {
        let rules = DaifugoRuleSet.standard
        #expect(rules.isEightCutEnabled)
        #expect(rules.isFoulFinishEnabled)
        #expect(!rules.isBindEnabled)
        #expect(!rules.isSequenceEnabled)
        #expect(!rules.isDownfallEnabled)
    }

    @Test("しばりだけを書いた旧い保存データも読め、残りは標準の値で補う")
    func decodesLegacyBindOnlyJSON() throws {
        let data = Data(#"{"isBindEnabled":true}"#.utf8)
        let rules = try JSONDecoder().decode(DaifugoRuleSet.self, from: data)
        #expect(rules == DaifugoRuleSet(isBindEnabled: true))
        #expect(rules.isEightCutEnabled)
        #expect(rules.isFoulFinishEnabled)
    }

    @Test("エンコードして読み戻すと全項目が保たれる")
    func roundTrips() throws {
        let rules = DaifugoRuleSet(
            isEightCutEnabled: false, isBindEnabled: true, isSequenceEnabled: true,
            isDownfallEnabled: true, isFoulFinishEnabled: false)
        let back = try JSONDecoder().decode(DaifugoRuleSet.self, from: JSONEncoder().encode(rules))
        #expect(back == rules)
    }
}

// MARK: - 階段（ルール）

@Suite("階段（判定）")
struct DaifugoSequenceRulesTests {
    private let on = DaifugoRuleSet(isSequenceEnabled: true)

    private func valid(_ cards: [DaifugoCard], field: [DaifugoCard] = [], revolution: Bool = false,
                       rules: DaifugoRuleSet? = nil, bind: Set<DaifugoSuit> = []) -> Bool {
        DaifugoRules.isValidPlay(cards, field: field, isRevolution: revolution, bindSuits: bind, ruleSet: rules ?? on)
    }

    @Test("同じスートの連番 3 枚以上は階段になる。順不同でもよい")
    func recognisesSequence() {
        #expect(valid([card(5), card(6), card(7)]))
        #expect(valid([card(7), card(5), card(6)]))
        #expect(valid([card(10), card(11), card(12), card(13)]))
        // 強さの並び（K→A→2）でつながる。
        #expect(valid([card(13), card(1), card(2)]))
    }

    @Test("2 枚・スート混在・飛び番・重複は階段にならない")
    func rejectsNonSequences() {
        #expect(!valid([card(5), card(6)]))
        #expect(!valid([card(5), card(6, .hearts), card(7)]))
        #expect(!valid([card(5), card(6), card(8)]))
        #expect(!valid([card(5), card(5, .hearts), card(6)]))
        // 3 の前に 2 はつながらない（輪にはしない）。
        #expect(!valid([card(2), card(3), card(4)]))
    }

    @Test("ジョーカーは欠けた数の代わりにも端の外側にもなる")
    func jokerFillsSequence() {
        #expect(valid([card(5), card(7), joker()]))
        #expect(valid([card(5), card(6), joker()]))
        #expect(valid([card(5), card(8), joker(0), joker(1)]))
        // 穴が 2 つ以上あるとジョーカー 1 枚では足りない。
        #expect(!valid([card(5), card(9), joker()]))
    }

    @Test("階段なしの局では階段は出せない")
    func offByDefault() {
        #expect(!valid([card(5), card(6), card(7)], rules: .standard))
    }

    @Test("場が階段のとき、同じ枚数でより強い階段だけが出せる")
    func beatsOnlyStrongerSameLength() {
        let field = [card(5), card(6), card(7)]
        #expect(valid([card(6, .hearts), card(7, .hearts), card(8, .hearts)], field: field))
        #expect(!valid([card(3, .hearts), card(4, .hearts), card(5, .hearts)], field: field))
        // 同じ強さ（スートだけ違う）は出せない。
        #expect(!valid([card(5, .hearts), card(6, .hearts), card(7, .hearts)], field: field))
        // 枚数違いは出せない。
        #expect(!valid([card(6, .hearts), card(7, .hearts), card(8, .hearts), card(9, .hearts)], field: field))
    }

    @Test("階段の場に同じ数字の組は、同じ数字の組の場に階段は出せない")
    func shapesDoNotMix() {
        let run = [card(5), card(6), card(7)]
        let triple = [card(9), card(9, .hearts), card(9, .clubs)]
        #expect(!valid(triple, field: run))
        #expect(!valid([card(10, .hearts), card(11, .hearts), card(12, .hearts)], field: [card(4), card(4, .hearts), card(4, .clubs)]))
        #expect(DaifugoRules.shape(of: run, isRevolution: false, ruleSet: on) == .sequence)
        #expect(DaifugoRules.shape(of: triple, isRevolution: false, ruleSet: on) == .group)
    }

    @Test("革命中は強さが逆になり、低い階段のほうが強い")
    func revolutionReversesSequences() {
        let field = [card(8), card(9), card(10)]
        #expect(valid([card(4, .hearts), card(5, .hearts), card(6, .hearts)], field: field, revolution: true))
        #expect(!valid([card(11, .hearts), card(12, .hearts), card(13, .hearts)], field: field, revolution: true))
    }

    @Test("階段は 4 枚あっても革命にはならない")
    func sequenceIsNotRevolution() {
        #expect(!DaifugoRules.triggersRevolution([card(5), card(6), card(7), card(8)]))
    }

    @Test("しばり中は、そのスートの階段（とジョーカー入り）だけが出せる")
    func bindRestrictsSequences() {
        let field = [card(5), card(6), card(7)]
        #expect(valid([card(8), card(9), card(10)], field: field, bind: [.spades]))
        #expect(!valid([card(8, .hearts), card(9, .hearts), card(10, .hearts)], field: field, bind: [.spades]))
        // 階段は 1 スートなので、続けて出すとしばりが掛かる。
        let rules = DaifugoRuleSet(isBindEnabled: true, isSequenceEnabled: true)
        let bound = DaifugoRules.nextBindSuits(current: [], field: field, played: [card(8), card(9), card(10)], ruleSet: rules)
        #expect(bound == [.spades])
    }

    @Test("理由の文言は形の食い違いと強さ不足を言い分ける")
    func rejectionReasons() {
        let run = [card(5), card(6), card(7)]
        let weak = DaifugoRules.rejectionReason(
            [card(3, .hearts), card(4, .hearts), card(5, .hearts)], field: run, isRevolution: false, ruleSet: on)
        #expect(weak == GameDaifugo.tr("場の階段より強い階段が必要です"))
        let mismatch = DaifugoRules.rejectionReason(
            [card(9), card(9, .hearts), card(9, .clubs)], field: run, isRevolution: false, ruleSet: on)
        #expect(mismatch == GameDaifugo.tr("場は階段です。同じ柄の連番で出してください"))
        let ok = DaifugoRules.rejectionReason(
            [card(8), card(9), card(10)], field: run, isRevolution: false, ruleSet: on)
        #expect(ok == nil)
    }
}

@Suite("階段（CPU の合法手とヒント）")
struct DaifugoSequenceCPUTests {
    private let on = DaifugoRuleSet(isSequenceEnabled: true)

    @Test("合法手に階段が含まれ、すべて isValidPlay を通る")
    func legalPlaysContainSequences() {
        let hand = [card(5), card(6), card(7), card(9), card(9, .hearts)]
        let plays = DaifugoRules.legalPlays(hand: hand, field: [], isRevolution: false, ruleSet: on)
        let run = Set([card(5), card(6), card(7)].map(\.id))
        #expect(plays.contains { Set($0.map(\.id)) == run })
        #expect(plays.allSatisfy { DaifugoRules.isValidPlay($0, field: [], isRevolution: false, ruleSet: on) })
        // 階段なしの局には出てこない。
        let none = DaifugoRules.legalPlays(hand: hand, field: [], isRevolution: false)
        #expect(!none.contains { Set($0.map(\.id)) == run })
    }

    @Test("場が階段なら、返せる階段だけが合法手になる")
    func respondsToSequenceField() {
        let hand = [card(8, .hearts), card(9, .hearts), card(10, .hearts), card(12), card(12, .clubs)]
        let field = [card(5), card(6), card(7)]
        let plays = DaifugoRules.legalPlays(hand: hand, field: field, isRevolution: false, ruleSet: on)
        #expect(plays.count == 1)
        #expect(Set(plays[0].map(\.id)) == Set([card(8, .hearts), card(9, .hearts), card(10, .hearts)].map(\.id)))
        let hint = DaifugoRules.playableCardIDs(hand: hand, field: field, isRevolution: false, ruleSet: on)
        #expect(hint == Set([card(8, .hearts), card(9, .hearts), card(10, .hearts)].map(\.id)))
    }

    @Test("ジョーカーで穴を埋めた階段も合法手になり、ジョーカーは出せる札に数える")
    func jokerSequencePlays() {
        let hand = [card(8, .hearts), card(10, .hearts), joker(), card(2, .clubs)]
        let field = [card(5), card(6), card(7)]
        let plays = DaifugoRules.legalPlays(hand: hand, field: field, isRevolution: false, ruleSet: on)
        #expect(plays.contains { Set($0.map(\.id)) == Set([card(8, .hearts), card(10, .hearts), joker()].map(\.id)) })
        let hint = DaifugoRules.playableCardIDs(hand: hand, field: field, isRevolution: false, ruleSet: on)
        #expect(hint.contains(joker().id))
        #expect(!hint.contains(card(2, .clubs).id))
    }

    @Test("CPU は出せる階段があれば階段で出し、出せなければパスする")
    func cpuPlaysSequence() {
        var rng = SplitMix64(seed: 1)
        let hand = [card(4), card(5), card(6), card(13, .hearts)]
        // 親番では弱い札から始まる階段を、単独の弱い札より先に出して枚数を減らす。
        let lead = DaifugoRules.cpuPlay(
            hand: hand, field: [], isRevolution: false, strength: .normal, ruleSet: on, using: &rng)
        #expect(lead.map { Set($0.map(\.id)) } == Set([card(4), card(5), card(6)].map(\.id)))
        let stuck = DaifugoRules.cpuPlay(
            hand: [card(3), card(4), card(9)], field: [card(5), card(6), card(7)], isRevolution: false,
            strength: .normal, ruleSet: on, using: &rng)
        #expect(stuck == nil)
    }

    @Test("場が空のときの合法手に重複が無い")
    func noDuplicatePlays() {
        let hand = [card(5), joker(0), joker(1), card(9, .hearts)]
        let plays = DaifugoRules.legalPlays(hand: hand, field: [], isRevolution: false, ruleSet: on)
        let keys = plays.map { $0.map(\.id).sorted() }
        #expect(Set(keys).count == keys.count)
    }
}

// MARK: - 8切り・反則上がりのオン / オフ

@Suite("8切り・反則上がり（オン / オフ）")
struct DaifugoToggleRulesTests {
    @Test("8切りなしでは 8 を出しても場は流れない")
    func eightCutOff() {
        #expect(DaifugoRules.clearsField([card(8)]))
        #expect(!DaifugoRules.clearsField([card(8)], ruleSet: DaifugoRuleSet(isEightCutEnabled: false)))
    }

    @Test("反則上がりなしでは 2・ジョーカー・8 で上がっても反則にならない")
    func foulOff() {
        let off = DaifugoRuleSet(isFoulFinishEnabled: false)
        #expect(DaifugoRules.isFoulFinish([joker()]))
        #expect(!DaifugoRules.isFoulFinish([joker()], ruleSet: off))
        #expect(!DaifugoRules.isFoulFinish([card(2)], ruleSet: off))
    }

    @Test("8 が反則の札になるのは 8切りありの局だけ")
    func eightIsFoulOnlyWithEightCut() {
        #expect(DaifugoRules.isFoulFinish([card(8)]))
        #expect(!DaifugoRules.isFoulFinish([card(8)], ruleSet: DaifugoRuleSet(isEightCutEnabled: false)))
        #expect(DaifugoRules.isFoulFinish([card(2)], ruleSet: DaifugoRuleSet(isEightCutEnabled: false)))
    }
}

// MARK: - 都落ち

@Suite("都落ち（順位）")
struct DaifugoDownfallRankingTests {
    @Test("前の大富豪が 1 位でなければ、投了者を除く最下位に落ちる")
    func tycoonFallsToLast() {
        // 上がり順 2, 0, 3, 1。前の大富豪は 0（2 位）。
        let ranking = DaifugoRules.ranking(finishOrder: [2, 0, 3, 1], fouls: [], previousTycoon: 0)
        #expect(ranking == [2, 3, 1, 0])
    }

    @Test("前の大富豪が 1 位なら変わらない / 都落ちなし（nil）でも変わらない")
    func tycoonStaysOnTop() {
        #expect(DaifugoRules.ranking(finishOrder: [0, 2, 3, 1], fouls: [], previousTycoon: 0) == [0, 2, 3, 1])
        #expect(DaifugoRules.ranking(finishOrder: [2, 0, 3, 1], fouls: [], previousTycoon: nil) == [2, 0, 3, 1])
    }

    @Test("前の大富豪が反則上がりで下がったときも、1 位でないので最下位に落ちる")
    func foulingTycoonFalls() {
        // 0 が最初に上がったが反則 → 順位は 2, 3, 1, 0（もともと最下位）。
        let ranking = DaifugoRules.ranking(finishOrder: [0, 2, 3, 1], fouls: [0], previousTycoon: 0)
        #expect(ranking == [2, 3, 1, 0])
    }

    @Test("投了した人は都落ちの対象にならず、いちばん下のまま")
    func resignedStaysBelow() {
        let ranking = DaifugoRules.ranking(finishOrder: [2, 3, 1, 0], fouls: [], resigned: [0], previousTycoon: 0)
        #expect(ranking == [2, 3, 1, 0])
        // 別の人が投了しているとき、落ちた大富豪は投了者の上。
        let other = DaifugoRules.ranking(finishOrder: [2, 0, 3, 1], fouls: [], resigned: [1], previousTycoon: 0)
        #expect(other == [2, 3, 0, 1])
    }
}

// MARK: - Model

@MainActor
private func makeModel(
    store: SnapshotStore = MemorySnapshotStore(), seed: UInt64 = 7
) -> (DaifugoModel, SnapshotStore) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (DaifugoModel(services: services, cpuDelay: .zero, seed: seed), store)
}

@Suite("ローカルルール（進行）")
@MainActor
struct DaifugoLocalRulesModelTests {
    private let others: [[DaifugoCard]] = [[card(4, .clubs), card(12, .clubs)], [card(3, .diamonds), card(13, .clubs)], [card(3, .hearts), card(1, .clubs)]]

    @Test("8切りなしの局では 8 を出しても場が流れず、次の人に手番が移る")
    func eightDoesNotClearWhenOff() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(8, .hearts), card(10)]] + others, field: [card(5)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isEightCutEnabled: false))
        model.toggleSelection(card(8, .hearts))
        model.playSelected()
        #expect(model.field == [card(8, .hearts)])
        #expect(model.currentPlayer == 1)
        #expect(model.ruleNotice == nil)
    }

    @Test("8切りありの局では 8 を出すと場が流れ、一言説明が出る")
    func eightClearsAndAnnounces() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(8, .hearts), card(10)]] + others, field: [card(5)], fieldOwner: 1, currentPlayer: 0)
        model.toggleSelection(card(8, .hearts))
        model.playSelected()
        #expect(model.field.isEmpty)
        #expect(model.ruleNotice?.events == [.eightCut])
        let serial = model.ruleNotice?.serial ?? 0
        model.dismissRuleNotice(serial: serial + 1)
        #expect(model.ruleNotice != nil, "別の番号の閉じる指示では消えない")
        model.dismissRuleNotice(serial: serial)
        #expect(model.ruleNotice == nil)
    }

    @Test("革命と 8切りが同時なら両方の説明が出る。革命が先")
    func revolutionAndEightCut() {
        let (model, _) = makeModel()
        let eights = [card(8), card(8, .hearts), card(8, .diamonds), card(8, .clubs)]
        model.configureForTesting(
            hands: [eights + [card(10)]] + others, field: [], currentPlayer: 0)
        for c in eights { model.toggleSelection(c) }
        model.playSelected()
        #expect(model.ruleNotice?.events == [.revolution, .eightCut])
        #expect(model.isRevolution)
    }

    @Test("しばりが掛かった瞬間に説明が出る")
    func bindAnnounces() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(6), card(9, .hearts)]] + others, field: [card(5)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isBindEnabled: true))
        model.toggleSelection(card(6))
        model.playSelected()
        #expect(model.ruleNotice?.events == [.bind([.spades])])
    }

    @Test("反則上がりの説明が出て、反則上がりなしの局では出ない")
    func foulFinishAnnounces() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[joker()]] + others, field: [card(5)], fieldOwner: 1, currentPlayer: 0)
        model.toggleSelection(joker())
        model.playSelected()
        #expect(model.fouls.contains(0))

        let (off, _) = makeModel()
        off.configureForTesting(
            hands: [[joker(), card(6)]] + others, field: [card(5)], fieldOwner: 1, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isFoulFinishEnabled: false))
        off.toggleSelection(joker())
        off.playSelected()
        #expect(off.ruleNotice == nil)
        #expect(off.fouls.isEmpty)
    }

    @Test("階段を出すと 3 枚が場に出て、手番が進む")
    func playsSequence() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(5), card(6), card(7), card(13, .hearts)]] + others, field: [], currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isSequenceEnabled: true))
        for c in [card(5), card(6), card(7)] { model.toggleSelection(c) }
        #expect(model.canPlaySelection)
        model.playSelected()
        #expect(model.field.count == 3)
        #expect(model.playerHand.count == 1)
        #expect(model.currentPlayer == 1)
    }

    @Test("階段なしの局では同じ選択でも出せず、理由が出る")
    func sequenceRejectedWhenOff() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(5), card(6), card(7), card(13, .hearts)]] + others, field: [], currentPlayer: 0)
        for c in [card(5), card(6), card(7)] { model.toggleSelection(c) }
        #expect(!model.canPlaySelection)
    }

    @Test("都落ち: 前の大富豪が 1 位で上がれなければ最下位に落ち、記録される")
    func downfallAtConclusion() async {
        let (model, _) = makeModel()
        // 前のゲームの大富豪は 1。今回は 0（自分）が先に上がるので、1 は 1 位になれない。
        model.configureForTesting(
            hands: [[card(10)], [card(11), card(4)], [card(3), card(5)], [card(6), card(7)]],
            field: [card(9)], fieldOwner: 3, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isDownfallEnabled: true), lastRanking: [1, 2, 3, 0])
        model.toggleSelection(card(10))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)
        #expect(model.ranking.first == 0)
        #expect(model.downfallPlayer == 1)
        #expect(model.ranking.last == 1)
    }

    @Test("前の大富豪がそのまま 1 位なら都落ちは起きない")
    func tycoonKeepsTop() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(10)], [card(11), card(4)], [card(3), card(5)], [card(6), card(7)]],
            field: [card(9)], fieldOwner: 3, currentPlayer: 0,
            ruleSet: DaifugoRuleSet(isDownfallEnabled: true), lastRanking: [0, 2, 3, 1])
        model.toggleSelection(card(10))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)
        #expect(model.ranking.first == 0)
        #expect(model.downfallPlayer == nil)
    }

    @Test("都落ちなしの局では順位は上がり順のまま")
    func noDownfallWhenOff() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(10)], [card(11), card(4)], [card(3), card(5)], [card(6), card(7)]],
            field: [card(9)], fieldOwner: 3, currentPlayer: 0, lastRanking: [1, 2, 3, 0])
        model.toggleSelection(card(10))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)
        #expect(model.downfallPlayer == nil)
    }

    @Test("中断→再開で全項目のルールが保たれる")
    func snapshotKeepsEveryRule() {
        let (model, store) = makeModel()
        let rules = DaifugoRuleSet(
            isEightCutEnabled: false, isBindEnabled: true, isSequenceEnabled: true,
            isDownfallEnabled: true, isFoulFinishEnabled: false)
        model.configureForTesting(
            hands: [[card(5), card(6)]] + others, field: [card(4)], fieldOwner: 1, currentPlayer: 0, ruleSet: rules)
        let (restored, _) = makeModel(store: store)
        #expect(restored.phase == .playing)
        #expect(restored.ruleSet == rules)
    }

    @Test("開始シートの選択は次のゲームに焼き込まれ、再起動しても引き継ぐ")
    func preferredRulesPersist() {
        let (model, store) = makeModel()
        let rules = DaifugoRuleSet(
            isEightCutEnabled: false, isBindEnabled: true, isSequenceEnabled: true,
            isDownfallEnabled: true, isFoulFinishEnabled: false)
        model.choosePreferredRuleSet(rules)
        model.startGame()
        #expect(model.ruleSet == rules)
        let (reopened, _) = makeModel(store: store)
        #expect(reopened.preferredRuleSet == rules)
    }
}

// MARK: - 自己対局（すべての組み合わせで最後まで打ち切れる）

@Suite("ローカルルールの全組み合わせで CPU が最後まで打ち切れる")
@MainActor
struct DaifugoSelfPlayTests {
    private static let allRuleSets: [DaifugoRuleSet] = (0..<32).map { bits in
        DaifugoRuleSet(
            isEightCutEnabled: bits & 1 != 0, isBindEnabled: bits & 2 != 0, isSequenceEnabled: bits & 4 != 0,
            isDownfallEnabled: bits & 8 != 0, isFoulFinishEnabled: bits & 16 != 0)
    }

    @Test("32 通りのルール × 3 つの強さ × 2 ゲームが決着し、4 人に順位が付く",
          arguments: [1, 5, 99] as [UInt64])
    func finishesInEveryCombination(seed: UInt64) async {
        for rules in Self.allRuleSets {
            let (model, _) = makeModel(seed: seed)
            model.choosePreferredRuleSet(rules)
            for (game, level) in [CPUStrength.normal, .hard].enumerated() {
                model.startGame(aiLevel: level.rawValue)
                #expect(model.ruleSet == rules)
                var turns = 0
                while model.phase == .playing, turns < 600 {
                    turns += 1
                    await model.runCPUTurnsIfNeeded()
                    guard model.phase == .playing, model.isPlayerTurn else { continue }
                    if let play = DaifugoRules.greedyPlay(
                        hand: model.playerHand, field: model.field, isRevolution: model.isRevolution,
                        bindSuits: model.bindSuits, ruleSet: model.ruleSet
                    ) {
                        for card in play { model.toggleSelection(card) }
                        model.playSelected()
                        #expect(model.selected.isEmpty, "合法手のはずが出せなかった: \(rules) game \(game)")
                    } else {
                        model.pass()
                    }
                }
                #expect(model.phase == .result, "決着しなかった: \(rules) seed \(seed) game \(game)")
                #expect(Set(model.ranking) == Set(0..<4), "順位が揃っていない: \(rules)")
                if !rules.isDownfallEnabled { #expect(model.downfallPlayer == nil) }
                if !rules.isFoulFinishEnabled { #expect(model.fouls.isEmpty) }
            }
        }
    }
}
