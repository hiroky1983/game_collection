import Testing
import Foundation
import Core
@testable import GameColorRelay
import CoreTestSupport

// MARK: - 組み立て

@MainActor
private func makeModel(
    seed: UInt64? = 42,
    store: SnapshotStore = MemorySnapshotStore()
) -> (ColorRelayModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    // テストでは CPU の間合いを取らない（待たずに最後まで進める）。
    return (ColorRelayModel(services: services, cpuDelay: .zero, seed: seed), services)
}

/// 人間の手番を単純な方針で自動消化しながら、決着するまで進める。
@MainActor
private func playToFinish(_ model: ColorRelayModel, maxTurns: Int = 3_000) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing, model.isPlayerTurn else { continue }
        if model.isPlayerPenalized {
            model.takePenalty()
        } else if let id = model.playableCardIDs.sorted().first,
                  let card = model.playerHand.first(where: { $0.id == id }) {
            model.toggleSelection(card)
            model.playSelected(color: card.isWild ? ColorRelayRules.dominantColor(in: model.playerHand) : nil)
        } else if model.canDraw {
            model.drawCard()
        } else {
            model.endTurn()
        }
    }
    return model.phase == .result
}

/// 4 人の手札 + 山 + 場の枚数の合計。
@MainActor
private func totalCards(_ model: ColorRelayModel) -> Int {
    model.hands.reduce(0) { $0 + $1.count } + model.drawPile.count + model.discardPile.count
}

/// 手札 1 枚の CPU に、出せない札だけを持たせた相手 3 人（山も出せない札だけ）。人間の操作を検証するための土台。
/// 場は「あかの7」。相手は全員むらさき・きいろの数字札で、山も同じ。
private func quietOpponents() -> (hands: [[RelayCard]], drawPile: [RelayCard]) {
    let hands: [[RelayCard]] = [
        [card(.purple, .number(1)), card(.purple, .number(2))],
        [card(.purple, .number(3)), card(.purple, .number(4))],
        [card(.purple, .number(5)), card(.purple, .number(6))],
    ]
    let pile = [card(.yellow, .number(1)), card(.yellow, .number(2)), card(.yellow, .number(3)),
                card(.yellow, .number(4)), card(.yellow, .number(5)), card(.yellow, .number(6)),
                card(.yellow, .number(8)), card(.yellow, .number(9)), card(.purple, .number(8)), card(.purple, .number(9))]
    return (hands, pile)
}

// MARK: - 配りと開始

@Suite("いろリレーの配り")
@MainActor
struct ColorRelayDealTests {
    @Test("7 枚ずつ配り、場は数字札 1 枚。いまの色は場の札の色。108 枚が失われない")
    func dealsSevenEach() {
        let (model, _) = makeModel()
        model.startGame()
        #expect(model.phase == .playing)
        #expect(model.hands.allSatisfy { $0.count == 7 })
        #expect(model.discardPile.count == 1)
        guard let top = model.topCard else { Issue.record("場が空"); return }
        if case .number = top.kind {} else { Issue.record("場の 1 枚目が数字札でない: \(top)") }
        #expect(model.activeColor == top.color)
        #expect(model.drawPile.count == 108 - 28 - 1)
        #expect(totalCards(model) == 108)
        let ids = model.hands.flatMap { $0 }.map(\.id) + model.drawPile.map(\.id) + model.discardPile.map(\.id)
        #expect(Set(ids).count == 108, "同じ札が 2 か所に無い")
    }

    @Test("場の 1 枚目が特殊札のときは山の底へ戻し、数字札が出るまでめくる")
    func openingSkipsSpecialCards() {
        // 種を変えて何回も配り、毎回数字札で始まることを確かめる（特殊札は 32/108 なので数十回で必ず当たる）。
        for seed in 1...40 {
            let (model, _) = makeModel(seed: UInt64(seed))
            model.startGame()
            guard let top = model.topCard else { Issue.record("場が空"); continue }
            if case .number = top.kind {} else { Issue.record("seed \(seed): \(top)") }
            #expect(totalCards(model) == 108, "seed \(seed)")
        }
    }

    @Test("親はゲームごとに 1 人ずつ回る（1 ゲーム目は人間）")
    func openingPlayerRotates() {
        let (model, _) = makeModel()
        model.startGame()
        #expect(model.currentPlayer == ColorRelayModel.humanIndex)
        #expect(model.gameNumber == 1)
        model.startGame()
        #expect(model.currentPlayer == 1)
        #expect(model.gameNumber == 2)
    }

    @Test("種が同じなら同じ配りになり、次のゲームは別の配りになる")
    func seedIsDeterministic() {
        let (a, _) = makeModel(seed: 99)
        let (b, _) = makeModel(seed: 99)
        a.startGame()
        b.startGame()
        #expect(a.hands == b.hands)
        #expect(a.topCard == b.topCard)
        a.startGame()
        #expect(a.hands != b.hands, "同じ種でも 2 ゲーム目は配りが変わる")
    }
}

// MARK: - 人間の操作

@Suite("いろリレーの進行")
@MainActor
struct ColorRelayPlayTests {
    @Test("同じ色の札を出すと手札から消え、場に乗り、次の人の番になる")
    func playsMatchingCard() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .number(3)), card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        #expect(model.playableCardIDs == [card(.red, .number(3)).id])
        #expect(model.handHint?.unplayable == [card(.green, .number(5)).id])

        model.toggleSelection(card(.red, .number(3)))
        #expect(model.canPlaySelection)
        model.playSelected()

        #expect(model.playerHand == [card(.green, .number(5))])
        #expect(model.topCard == card(.red, .number(3)))
        #expect(model.currentPlayer == 1)
        #expect(!model.isPlayerTurn)
        #expect(model.lastActions[0] == "3")
    }

    @Test("色も数字も違う札は出せず、手札も番も動かない")
    func rejectsMismatch() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(.green, .number(5)))
        #expect(!model.canPlaySelection)
        model.playSelected()
        #expect(model.playerHand.count == 1)
        #expect(model.currentPlayer == 0)
        #expect(model.handHint?.playable.isEmpty == true, "1 枚も出せないときは全札を落とす")
    }

    @Test("同じ札をもう一度タップすると選択が外れ、相手の番では選べない")
    func selectionToggles() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .number(3))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(.red, .number(3)))
        #expect(model.selectedID == card(.red, .number(3)).id)
        model.toggleSelection(card(.red, .number(3)))
        #expect(model.selectedID == nil)

        model.configureForTesting(hands: [[card(.red, .number(3))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile, currentPlayer: 2)
        model.toggleSelection(card(.red, .number(3)))
        #expect(model.selectedID == nil, "相手の番では選べない")
        #expect(model.handHint == nil, "相手の番ではヒントを出さない")
    }

    @Test("とばしは次の人を飛ばす")
    func skipSkipsNext() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .skip), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(.red, .skip))
        model.playSelected()
        #expect(model.currentPlayer == 2)
        #expect(model.lastActions[0] == "とばし！")
    }

    @Test("ぎゃくは回る向きを変え、前の人の番になる")
    func reverseFlipsDirection() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .reverse), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(.red, .reverse))
        model.playSelected()
        #expect(!model.isClockwise)
        #expect(model.currentPlayer == 3)
        #expect(model.nextPlayer(after: 0) == 3)
    }

    @Test("+2 を出すと次の CPU が 2 枚引いて番を飛ばされる")
    func drawTwoPenalizesNext() async {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .drawTwo), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(.red, .drawTwo))
        model.playSelected()
        #expect(model.currentPlayer == 1)
        #expect(model.pendingDraw == 2)

        await model.runCPUTurnsIfNeeded()

        #expect(model.hands[1].count == 4, "CPU1 は 2 枚引く")
        #expect(model.lastActions[1] == "2枚引いた")
        #expect(model.pendingDraw == 0)
        // CPU2・CPU3 は出せず 1 枚ずつ引いて回り、人間の番に戻る。
        #expect(model.hands[2].count == 3)
        #expect(model.hands[3].count == 3)
        #expect(model.isPlayerTurn)
        #expect(totalCards(model) == 19, "2 + 6 + 10 + 1 枚のまま失われない")
    }

    @Test("いろがえは色を選んで出す。色を選ばなければ出ない")
    func wildChoosesColor() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(nil, .wild), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(nil, .wild))
        #expect(model.needsColorChoice)
        model.playSelected()
        #expect(model.playerHand.count == 2, "色を選ばないと出ない")
        #expect(model.currentPlayer == 0)

        model.playSelected(color: .yellow)
        #expect(model.topCard == card(nil, .wild))
        #expect(model.activeColor == .yellow)
        #expect(model.currentPlayer == 1)
        #expect(model.lastActions[0] == "いろがえ → きいろ")
    }

    @Test("いろがえ+4 は色を選び、次の人に 4 枚の引き札を課す")
    func wildDrawFour() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(nil, .wildDrawFour), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(nil, .wildDrawFour))
        model.playSelected(color: .green)
        #expect(model.activeColor == .green)
        #expect(model.currentPlayer == 1)
        #expect(model.pendingDraw == 4)
    }

    @Test("引いた札が出せなければ、そのまま次の人の番になる")
    func drawUnplayableAdvances() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: [card(.purple, .number(2))] + quiet.drawPile)
        // 山は末尾から引く。
        #expect(model.canDraw)
        model.drawCard()
        #expect(model.playerHand.count == 2)
        #expect(model.playerHand.contains(quiet.drawPile.last!))
        #expect(model.currentPlayer == 1)
        #expect(!model.hasDrawnThisTurn, "番が移ったので引いた印は消える")
        #expect(model.lastActions[0] == "1枚引いた")
    }

    @Test("引いた札が出せるなら、その札だけ出せる。出さずに次へ回すこともできる")
    func drawPlayableStays() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        let drawn = card(.red, .number(2))
        model.configureForTesting(hands: [[card(.green, .number(5)), card(.red, .number(9))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile + [drawn])
        model.drawCard()
        #expect(model.isPlayerTurn)
        #expect(model.hasDrawnThisTurn)
        #expect(model.drawnCardID == drawn.id)
        #expect(model.playableCardIDs == [drawn.id], "手札にあった あかの9 は出せなくなる")
        #expect(!model.canDraw, "1 手番に引けるのは 1 回")
        #expect(model.canEndTurn)

        model.toggleSelection(card(.red, .number(9)))
        #expect(!model.canPlaySelection)
        model.toggleSelection(drawn)
        #expect(model.canPlaySelection)
        model.playSelected()
        #expect(model.topCard == drawn)
        #expect(model.currentPlayer == 1)
    }

    @Test("出せる札を持っていても引ける（引いた札が出せなければ番は終わる）")
    func canDrawEvenWithPlayableCard() {
        // 標準的なルールと同じで、出したくない札を温存して引く選択を許す。誤タップの保険は付けない
        // （verifier の指摘を受けて、この挙動を意図として固定する）。
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .number(9))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: [card(.purple, .number(2))])
        #expect(model.canDraw, "出せる あかの9 があっても引ける")
        model.drawCard()
        #expect(model.playerHand.count == 2)
        #expect(model.currentPlayer == 1, "引いた むらさきの2 は出せないので番が終わる")
    }

    @Test("出さずに次へ回すと選択も外れる")
    func endTurnClearsSelection() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(nil, .wild)]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile + [card(.red, .number(2))])
        model.drawCard()
        model.toggleSelection(card(nil, .wild))
        #expect(model.selectedID != nil)
        model.endTurn()
        #expect(model.selectedID == nil, "相手の番に万能札の選択が残ると、次の自分の番に色選択欄から始まってしまう")
    }

    @Test("引いた札を出さずに次へ回せる")
    func endTurnAfterDraw() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile + [card(.red, .number(2))])
        #expect(!model.canEndTurn, "引く前は次へ回せない")
        model.endTurn()
        #expect(model.currentPlayer == 0)
        model.drawCard()
        model.endTurn()
        #expect(model.currentPlayer == 1)
        #expect(model.playerHand.count == 2)
    }

    @Test("山が尽きたら、場の 1 枚を残して捨て札を切り直して引く")
    func refillsDrawPile() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        let below = [card(.purple, .number(9)), card(.yellow, .number(9)), card(.purple, .number(8))]
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: [], discardBelowTop: below)
        #expect(model.discardPile.count == 4)
        let before = totalCards(model)

        model.drawCard()

        #expect(model.playerHand.count == 2, "切り直した山から 1 枚引けている")
        #expect(model.discardPile == [card(.red, .number(7))], "場の札はそのまま残る")
        #expect(model.drawPile.count == 2, "残りの捨て札が山になる")
        #expect(Set(model.drawPile + [model.playerHand[0], model.playerHand[1]]).isSuperset(of: Set(below)),
                "切り直した札はどれも失われていない")
        #expect(totalCards(model) == before)
        #expect(model.currentPlayer == 1, "引いた札は出せないので番が進む")
    }

    @Test("捨て札が場の 1 枚だけで山も空なら引けず、番だけ進む")
    func cannotDrawWhenEverythingIsGone() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: [])
        model.drawCard()
        #expect(model.playerHand.count == 1)
        #expect(model.discardPile.count == 1)
        #expect(model.currentPlayer == 1)
    }

    @Test("手札が尽きたら決着。上がった人が 1 位で、勝敗が記録され、中断データは消える")
    func winsWhenHandEmpties() {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .number(3))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        #expect(store.exists(for: "colorrelay"))
        model.toggleSelection(card(.red, .number(3)))
        model.playSelected()
        #expect(model.phase == .result)
        #expect(model.ranking == [0, 1, 2, 3])
        #expect(model.playerPlace == 0)
        #expect(model.reviewOutcome == .win)
        #expect(model.lastActions[0] == "3 あがり！")
        #expect(!store.exists(for: "colorrelay"), "決着したら中断データは消える")
        #expect(model.handHint == nil)
    }

    @Test("CPU が上がると自分は負け。順位は手札の少ない順")
    func losesWhenCPUEmpties() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.green, .number(1)), card(.green, .number(2)), card(.green, .number(3))],
                [card(.red, .number(1))],
                [card(.green, .number(4)), card(.green, .number(5))],
                [card(.green, .number(6)), card(.green, .number(7)), card(.green, .number(8)), card(.green, .number(9))],
            ],
            top: card(.red, .number(7)), drawPile: [], currentPlayer: 1
        )
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)
        #expect(model.ranking == [1, 2, 0, 3])
        #expect(model.reviewOutcome == .loss)
        #expect(model.playerPlace == 2)
    }

    @Test("種を変えて 12 ゲーム回しても必ず決着し、枚数は失われない")
    func fullGamesFinish() async {
        for seed in 1...12 {
            let (model, _) = makeModel(seed: UInt64(seed))
            model.startGame()
            let finished = await playToFinish(model)
            #expect(finished, "seed \(seed) が決着しなかった")
            #expect(totalCards(model) == 108, "seed \(seed) で枚数が変わった")
            #expect(model.ranking.count == 4)
            #expect(model.hands[model.ranking[0]].isEmpty)
        }
    }
}

// MARK: - 引き札と免除

@Suite("いろリレーの引き札と免除")
@MainActor
struct ColorRelayPenaltyTests {
    @Test("引き札を課された自分の番は、札を出せず引くこともできず、引いて番を飛ばされる")
    func takePenalty() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5)), card(.green, .drawTwo)]] + quiet.hands,
                                  top: card(.green, .drawTwo, nth: 1), drawPile: quiet.drawPile, pendingDraw: 2)
        #expect(model.isPlayerPenalized)
        #expect(!model.canDraw)
        #expect(model.playableCardIDs.isEmpty, "受けた引き札は重ねられない（積み重ね無し）")
        #expect(model.handHint == nil)
        model.toggleSelection(card(.green, .drawTwo))
        #expect(model.selectedID == nil)

        model.takePenalty()
        #expect(model.playerHand.count == 4)
        #expect(model.pendingDraw == 0)
        #expect(model.currentPlayer == 1)
        #expect(model.lastActions[0] == "2枚引いた")
    }

    @Test("広告を見終えたら引かずに済み、番は飛ばされる。1 ゲームに 1 回だけ")
    func waivePenalty() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(nil, .wildDrawFour), drawPile: quiet.drawPile, activeColor: .red, pendingDraw: 4)
        #expect(model.canWaivePenalty)
        let turn = model.turnSerial

        #expect(model.waivePenaltyAfterAd(forTurn: turn))
        #expect(model.playerHand.count == 1, "引かずに済む")
        #expect(model.pendingDraw == 0)
        #expect(model.currentPlayer == 1, "番は飛ばされる")
        #expect(model.isPenaltyWaived)
        #expect(model.lastActions[0] == "引き札を免除")

        // 同じゲームでもう一度課されても、免除は使えない。
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.green, .drawTwo), drawPile: quiet.drawPile,
                                  pendingDraw: 2, isPenaltyWaived: true)
        #expect(model.isPlayerPenalized)
        #expect(!model.canWaivePenalty, "1 ゲーム 1 回")
        #expect(!model.waivePenaltyAfterAd(forTurn: model.turnSerial))
        #expect(model.pendingDraw == 2)

        // 次のゲームでは使える。
        model.startGame()
        #expect(!model.isPenaltyWaived)
    }

    @Test("広告のあいだに番が進んでいたら免除しない（局ガード）")
    func staleTurnIsRejected() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.green, .drawTwo), drawPile: quiet.drawPile, pendingDraw: 2)
        let turn = model.turnSerial
        model.takePenalty()   // 広告のあいだに引いてしまった
        #expect(!model.waivePenaltyAfterAd(forTurn: turn))
        #expect(!model.isPenaltyWaived)
    }

    @Test("引き札を課されていないときは免除できない")
    func noPenaltyNoWaiver() {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        #expect(!model.canWaivePenalty)
        #expect(!model.waivePenaltyAfterAd(forTurn: model.turnSerial))
        #expect(model.currentPlayer == 0)
    }

    @Test("CPU は課された引き札を引いて番を飛ばされる（いろがえ+4）")
    func cpuTakesPenalty() async {
        let (model, _) = makeModel()
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(nil, .wildDrawFour), card(.red, .number(1))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        model.toggleSelection(card(nil, .wildDrawFour))
        model.playSelected(color: .green)
        await model.runCPUTurnsIfNeeded()
        #expect(model.hands[1].count == 6, "CPU1 は 4 枚引く")
        #expect(model.lastActions[1] == "4枚引いた")
        #expect(model.isPlayerTurn)
    }
}

// MARK: - 永続化

@Suite("いろリレーの中断データ")
@MainActor
struct ColorRelaySnapshotTests {
    @Test("配ったばかりの局は保存しない。1 手進んだら保存され、開き直すと同じ局面に戻る")
    func roundTrip() {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        model.startGame()
        #expect(!store.exists(for: "colorrelay"), "配っただけでは「続きから」を付けない（#240）")

        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.red, .number(3)), card(nil, .wild)]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile, isClockwise: false)
        model.toggleSelection(card(nil, .wild))
        model.playSelected(color: .purple)
        #expect(store.exists(for: "colorrelay"))

        let restored = ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
        #expect(restored.phase == .playing)
        #expect(restored.hands == model.hands)
        #expect(restored.topCard == card(nil, .wild))
        #expect(restored.activeColor == .purple)
        #expect(restored.currentPlayer == model.currentPlayer)
        #expect(restored.isClockwise == false)
        #expect(restored.drawPile == model.drawPile)
        #expect(restored.gameNumber == model.gameNumber)
        #expect(restored.turnSerial == model.turnSerial)
        #expect(restored.lastActions == model.lastActions)
        #expect(restored.pendingDraw == 0)
    }

    @Test("引き札と引いた札の印も復元される")
    func restoresPenaltyAndDrawn() {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile + [card(.red, .number(2))])
        model.drawCard()
        let restored = ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
        #expect(restored.hasDrawnThisTurn)
        #expect(restored.drawnCardID == card(.red, .number(2)).id)
        #expect(restored.playableCardIDs == [card(.red, .number(2)).id])

        let (penalized, _) = makeModel(store: store)
        penalized.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                      top: card(.green, .drawTwo), drawPile: quiet.drawPile, pendingDraw: 2)
        #expect(penalized.waivePenaltyAfterAd(forTurn: penalized.turnSerial))
        let restored2 = ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
        #expect(restored2.isPenaltyWaived, "免除を使ったことは開き直しても残る")
    }

    @Test("壊れた中断データは無視して開始前の状態になる")
    func ignoresBrokenSnapshot() {
        let store = MemorySnapshotStore()
        store.inject(Data("{\"hands\":[]}".utf8), for: "colorrelay")
        let (model, _) = makeModel(store: store)
        #expect(model.phase == .idle)

        // 形は正しいが値が範囲外（手番の番号・引き札の枚数）のデータも無視する。
        // 通してしまうと `hands[currentPlayer]` や `for _ in 0..<pendingDraw` で落ちる。
        let (valid, _) = makeModel(store: store)
        let quiet = quietOpponents()
        valid.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile)
        let raw = try? #require(store.rawData(for: "colorrelay"))
        var json = (try? JSONSerialization.jsonObject(with: raw ?? Data())) as? [String: Any] ?? [:]
        json["currentPlayer"] = 9
        store.inject(try! JSONSerialization.data(withJSONObject: json), for: "colorrelay")
        #expect(ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero).phase == .idle)
        json["currentPlayer"] = 0
        json["pendingDraw"] = -1
        store.inject(try! JSONSerialization.data(withJSONObject: json), for: "colorrelay")
        #expect(ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero).phase == .idle)
        json["pendingDraw"] = 0
        store.inject(try! JSONSerialization.data(withJSONObject: json), for: "colorrelay")
        #expect(ColorRelayModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero).phase == .playing,
                "値を戻せば復元できる（検証そのものが機能している）")
    }

    @Test("山の切り直し直後に配った直後と同じ枚数になっても、対局中の中断データは消えない")
    func refillDoesNotLookLikeUntouchedDeal() {
        // 手札の合計 27 + 場 81 で山が尽き、1 枚引くと「手札 28・場 1・山 79」= 配った直後と同じ枚数になる
        // （CodeRabbit 指摘・PR #1339）。枚数で判定していると中断データが消える。
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        let deck = RelayCard.makeDeck()
        // CPU 3 人は 7 枚ずつ（あかの札）、人間は 6 枚（みどりの札）で合計 27 枚。場はいろがえで色は あか
        // （人間の手札に出せる札が無い）。捨て札はその下に 80 枚、山は空。
        let cpuHands: [[RelayCard]] = [Array(deck[0..<7]), Array(deck[7..<14]), Array(deck[14..<21])]
        let human = Array(deck[25..<31])
        let top = card(nil, .wild)
        let used = Set(cpuHands.flatMap { $0 } + human + [top])
        let below = deck.filter { !used.contains($0) }
        #expect(below.count == 80)
        model.configureForTesting(hands: [human] + cpuHands, top: top, drawPile: [],
                                  discardBelowTop: below, activeColor: .red)
        #expect(store.exists(for: "colorrelay"))
        #expect(model.playableCardIDs.isEmpty)
        model.drawCard()
        #expect(model.hands.reduce(0) { $0 + $1.count } == 28, "配った直後と同じ枚数になる")
        #expect(model.discardPile.count == 1)
        #expect(model.drawPile.count == 79)
        #expect(store.exists(for: "colorrelay"), "対局中なのに配った直後と誤認して中断データを消した")
    }
}

// MARK: - CPU 進行のキャンセル

@Suite("いろリレーの CPU 進行のキャンセル")
@MainActor
struct ColorRelayCancelTests {
    /// `ColorRelayView` は `.task { await model.runCPUTurnsIfNeeded() }` で CPU を回しており、画面を離れると
    /// キャンセルされる。ループが `Task.isCancelled` を見ていないと残りの手番が遅延ゼロで走り抜ける（#287）。
    @Test("キャンセルされたら遅延を飛ばして打ち続けない")
    func cancelledLoopDoesNotFastForward() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ColorRelayModel(services: services, cpuDelay: .seconds(60), seed: 42)
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile, currentPlayer: 1)
        let before = model.currentPlayer
        let handsBefore = model.hands.map(\.count)
        let task = Task { await model.runCPUTurnsIfNeeded() }
        task.cancel()
        await task.value
        #expect(model.currentPlayer == before, "キャンセル済みのタスクが cpuDelay を無視して手番を進めた")
        #expect(model.hands.map(\.count) == handsBefore)
    }

    /// sleep に入ってからキャンセルされた場合も、sleep の直後の判定で止まる（#817 の変異で赤くなる側）。
    @Test("sleep に入った後にキャンセルされても手番を進めない")
    func cancelledDuringSleepDoesNotAdvance() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ColorRelayModel(services: services, cpuDelay: .seconds(60), seed: 42)
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile, currentPlayer: 1)
        let before = model.currentPlayer
        let task = Task { await model.runCPUTurnsIfNeeded() }
        // 本体を sleep まで走らせてからキャンセルする。
        var gate = 0
        while !model.isRunningCPUTurns, gate < 1_000 {
            gate += 1
            await Task.yield()
        }
        try? #require(model.isRunningCPUTurns, "先行タスクが開始しなかった")
        task.cancel()
        await task.value
        #expect(model.currentPlayer == before, "sleep 後のキャンセル判定を通らずに手番を進めた")
    }

    /// 先行タスクが走者を握ったまま suspend している間に新タスクが走ると、走者不在で手番が止まる（#311 と同じレース）。
    @Test("差し替え後の新タスクが先行タスクの終了を待って引き継ぐ（走者不在で止まらない）")
    func replacementTaskTakesOver() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ColorRelayModel(services: services, cpuDelay: .milliseconds(30), seed: 42)
        let quiet = quietOpponents()
        model.configureForTesting(hands: [[card(.green, .number(5))]] + quiet.hands,
                                  top: card(.red, .number(7)), drawPile: quiet.drawPile, currentPlayer: 1)
        let taskA = Task { await model.runCPUTurnsIfNeeded() }
        var gate = 0
        while !model.isRunningCPUTurns, gate < 1_000 {
            gate += 1
            await Task.yield()
        }
        try? #require(model.isRunningCPUTurns, "先行タスクが開始しなかった")
        let taskB = Task { await model.runCPUTurnsIfNeeded() }
        taskA.cancel()
        await taskA.value
        await taskB.value
        #expect(model.phase != .playing || model.currentPlayer == ColorRelayModel.humanIndex,
                "走者不在で CPU の手番が止まった")
    }
}
