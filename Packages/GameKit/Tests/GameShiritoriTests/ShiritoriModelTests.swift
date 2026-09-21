import Testing
import Foundation
import Core
@testable import GameShiritori
import CoreTestSupport

// MARK: - 支援

@MainActor
private func makeModel(seed: UInt64? = 42) -> (ShiritoriModel, GameServices) {
    let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    return (ShiritoriModel(services: services, cpuDelay: .zero, seed: seed), services)
}

private let apple = ShiritoriCard(.apple, "りんご")            // り → ご
private let gorilla = ShiritoriCard(.gorilla, "ごりら")        // ご → ら
private let otter = ShiritoriCard(.seaOtter, "らっこ")          // ら → こ
private let top = ShiritoriCard(.spinningTop, "こま")           // こ → ま
private let squirrel = ShiritoriCard(.squirrel, "りす")         // り → す
private let trapForPlayer = ShiritoriCard(.pillow, "ごはん")    // ご → ん
private let trapForCPU = ShiritoriCard(.cat, "らーめん")        // ら → ん

// MARK: - 進行

@Suite("カードしりとりの進行")
@MainActor
struct ShiritoriModelTests {

    @Test("開始: 19 枚が並び、残る 1 枚が場の札。時間は 60 秒でプレイヤーが先手")
    func startDealsNineteenAndOpensOne() {
        let (model, _) = makeModel()
        model.startGame(quota: .hard)

        #expect(model.phase == .playing)
        #expect(model.slots.count == 19)
        let ids = model.slots.map(\.card.id) + [model.currentCard?.id ?? ""]
        #expect(Set(ids) == Set(ShiritoriCard.deck.map(\.id)), "山札 20 枚が過不足なく盤と場に分かれる")
        #expect(model.currentReading == model.currentCard?.primaryReading, "最初の場は表読み")
        #expect(model.timeRemaining == 60)
        #expect(model.isPlayerTurn)
        #expect(model.quota == .hard)
        #expect(model.gameNumber == 1)
        #expect(model.playerCount == 0 && model.cpuCount == 0)
    }

    @Test("どの配りでも、プレイヤーの最初の手が 1 つは残っている")
    func everyDealLeavesAFirstMove() {
        for seed in UInt64(0)..<200 {
            let (model, _) = makeModel(seed: seed)
            model.startGame()
            #expect(model.phase == .playing, "seed \(seed)")
            let tail = model.requiredTail
            #expect(tail != nil && tail != "ん")
            #expect(!ShiritoriRules.moves(slots: model.slots, after: tail ?? "ん").isEmpty, "seed \(seed)")
        }
    }

    @Test("同じ種なら同じ配り。次のゲームは種が進んで別の配りになる")
    func seedIsDeterministicAndAdvances() {
        let (a, _) = makeModel(seed: 7)
        let (b, _) = makeModel(seed: 7)
        a.startGame(); b.startGame()
        #expect(a.slots.map(\.card.id) == b.slots.map(\.card.id))
        let first = a.slots.map(\.card.id)
        a.startGame()
        #expect(a.slots.map(\.card.id) != first)
        #expect(a.gameNumber == 2)
    }

    @Test("成立: 札を取り、時間が +10 秒、手番が CPU に移る。使った読みが次の語尾を決める")
    func successClaimsAndPassesTurn() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, top, squirrel])
        model.select(0)

        #expect(model.slots[0].owner == .player)
        #expect(model.currentCard == gorilla)
        #expect(model.requiredTail == "ら")
        #expect(model.timeRemaining == 70)
        #expect(!model.isPlayerTurn)
        #expect(model.lastEvent == .played(by: .player, reading: "ごりら", isAlternate: false))
    }

    @Test("お手つき: 時間が -5 秒。手番も札もそのまま")
    func missCostsFiveSeconds() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, squirrel])
        model.select(1)   // りす は「ご」でも「こ」でも始まらない

        #expect(model.timeRemaining == 55)
        #expect(model.isPlayerTurn)
        #expect(model.slots[1].owner == nil)
        #expect(model.currentCard == apple)
        #expect(model.lastEvent == .miss)
        #expect(model.phase == .playing)
    }

    @Test("お手つきで時間が尽きたら時間切れで終わる")
    func missCanEndTheGame() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, squirrel])
        model.tick(57)
        model.select(1)

        #expect(model.timeRemaining == 0)
        #expect(model.ending == .timeUp)
        #expect(model.phase == .result)
    }

    @Test("裏読みで受けたときは、その裏読みの語尾が次の場になる")
    func alternateReadingSetsTheNextTail() {
        let drum = ShiritoriCard(.drum, "たいこ", "どらむ")
        let start = ShiritoriCard(.pillow, "まくど")      // 語尾「ど」
        let (model, _) = makeModel()
        model.configureForTesting(opener: start, board: [drum, top])
        model.select(0)

        #expect(model.currentReading == "どらむ")
        #expect(model.requiredTail == "む")
        #expect(model.lastEvent == .played(by: .player, reading: "どらむ", isAlternate: true))
    }

    @Test("時間はプレイヤーの手番のあいだだけ減る")
    func clockRunsOnlyOnThePlayersTurn() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], isPlayerTurn: false)
        model.tick(10)
        #expect(model.timeRemaining == 60, "CPU の番では減らない")

        model.configureForTesting(opener: apple, board: [gorilla], isPlayerTurn: true)
        model.tick(10)
        #expect(model.timeRemaining == 50)
        model.tick(-5)
        model.tick(0)
        #expect(model.timeRemaining == 50, "0 以下の経過は無視する")
    }

    @Test("時間切れ: ノルマで勝敗が決まる。1 枚も取っていなければ負け")
    func timeUpWithNothingTakenLoses() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], quota: .easy)
        model.tick(60)

        #expect(model.ending == .timeUp)
        #expect(!model.didPlayerWin, "0 枚はやさしいでも満たさない")
        #expect(model.phase == .result)
        model.tick(5)
        model.select(0)
        #expect(model.slots[0].owner == nil, "決着後は操作できない")
    }

    @Test("CPU が続けられない: 取った割合がノルマを満たせば勝ち（詰ませても足りなければ負け）")
    func cpuStuckJudgedByQuota() async {
        // りんご →(あなた)ごりら →(CPU)らっこ →(あなた)… で こ から始まる札が尽きる形は別に作る。
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, top], quota: .normal)
        model.select(0)                                  // ごりら（語尾ら）に続く札は無い
        #expect(model.ending == .cpuStuck, "CPU の番になる前に、続けられないと分かる")
        #expect(model.playerCount == 1 && model.cpuCount == 0)
        #expect(model.didPlayerWin, "1/1 = 100% はふつうのノルマを超える")
        #expect(model.phase == .result)
    }

    @Test("むずかしいは 2 手目以降で詰ませても勝てない（1 手目で詰ませる必要がある）")
    func hardNeedsAnImmediateKill() async {
        // りんご →(あなた)ごりら →(CPU)らっこ →(あなた)こま →(CPU 詰み)。2 対 1 = 66%。
        for (quota, expectedWin) in [(ShiritoriQuota.easy, true), (.normal, true), (.hard, false)] {
            let (model, _) = makeModel()
            model.configureForTesting(opener: apple, board: [gorilla, otter, top], quota: quota)
            model.select(0)
            await model.runCPUTurnIfNeeded()             // らっこ
            #expect(model.cpuCount == 1)
            model.select(2)                              // こま（語尾ま）
            #expect(model.ending == .cpuStuck, "\(quota)")
            #expect(model.didPlayerWin == expectedWin, "\(quota): 2対1")
        }
    }

    @Test("プレイヤーが続けられない: ノルマで決まる。同数（50%）はふつうでは負け・やさしいでは勝ち")
    func playerStuckJudgedByQuota() async {
        for (quota, expectedWin) in [(ShiritoriQuota.easy, true), (.normal, false)] {
            let (model, _) = makeModel()
            // りんご →(あなた)ごりら →(CPU)らっこ → こ から始まる札は無い。
            model.configureForTesting(opener: apple, board: [gorilla, otter], quota: quota)
            model.select(0)
            await model.runCPUTurnIfNeeded()
            #expect(model.ending == .playerStuck, "\(quota)")
            #expect(model.playerCount == 1 && model.cpuCount == 1)
            #expect(model.didPlayerWin == expectedWin, "\(quota)")
        }
    }

    @Test("「ん」で終わる読みを選んだら、ノルマに関係なくその場で負ける")
    func playerHittingNLosesRegardlessOfQuota() {
        let (model, _) = makeModel()
        // 1 枚も取られていないが、選んだ時点で「ん」なので負け（ノルマ判定より優先）。
        model.configureForTesting(opener: apple, board: [trapForPlayer, gorilla], quota: .easy)
        model.select(0)

        #expect(model.ending == .playerHitN)
        #expect(!model.didPlayerWin)
        #expect(model.phase == .result)
    }

    @Test("CPU が「ん」で終わる読みを選ばされたら、ノルマに関係なく勝つ")
    func cpuHittingNWinsRegardlessOfQuota() async {
        let (model, _) = makeModel()
        // りんご →(あなた)ごりら →(CPU の手は らーめん だけ)。1 対 1 = 50% でふつうなら負けの成績。
        model.configureForTesting(opener: apple, board: [gorilla, trapForCPU], quota: .normal)
        model.select(0)
        await model.runCPUTurnIfNeeded()

        #expect(model.ending == .cpuHitN)
        #expect(model.didPlayerWin)
        #expect(model.reviewOutcome == .win)
    }

    @Test("札が尽きたら CPU が続けられず、そこで終わる")
    func lastCardEndsTheGame() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla])
        model.select(0)
        #expect(model.remainingCount == 0)
        #expect(model.ending == .cpuStuck)
    }

    @Test("CPU の番でプレイヤーは札を取れない")
    func playerCannotActOnCPUTurn() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], isPlayerTurn: false)
        model.select(0)
        #expect(model.slots[0].owner == nil)
        #expect(model.timeRemaining == 60)
        #expect(!model.isSelectable(0))
    }

    @Test("取られた札・範囲外は選べない（お手つきにも数えない）")
    func takenAndOutOfRangeAreIgnored() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, otter, top])
        model.select(0)
        #expect(model.timeRemaining == 70)
        model.select(99)
        model.select(-1)
        #expect(model.timeRemaining == 70)
    }

    @Test("一時停止: 止めている間は時間が減らず、札をタップすると再開する。開始前・決着後は止めない")
    func pauseFreezesTheClockUntilTheNextTap() {
        let (model, _) = makeModel()
        model.pause()
        #expect(!model.isPaused, "開始前は止めるものが無い")

        model.configureForTesting(opener: apple, board: [gorilla, squirrel])
        model.pause()
        model.tick(30)
        #expect(model.isPaused)
        #expect(model.timeRemaining == 60)

        model.select(1)   // お手つきでも再開する（タップした = 遊び始めた）
        #expect(!model.isPaused)
        model.tick(10)
        #expect(model.timeRemaining == 45, "-5 秒のあと 10 秒減る")

        model.pause()
        model.startGame()
        #expect(!model.isPaused, "新しいゲームは止まらずに始まる")
    }

    @Test("CPU の演出待ちがある構成でも 1 手だけ進み、同時に 2 回起動しても二重に指さない")
    func delayedCPUTurnRunsOnce() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ShiritoriModel(services: services, cpuDelay: .milliseconds(20), seed: 1)
        model.configureForTesting(opener: apple, board: [gorilla, otter, top, squirrel])
        model.select(0)   // ごりら → CPU は らっこ
        #expect(!model.isPlayerTurn)
        async let first: Void = model.runCPUTurnIfNeeded()
        async let second: Void = model.runCPUTurnIfNeeded()
        _ = await (first, second)
        #expect(model.cpuCount == 1)
        #expect(model.slots[1].owner == .cpu)
        #expect(model.isPlayerTurn)
    }

    @Test("演出待ちの間に新しいゲームが始まったら、古い CPU の手は指さない")
    func staleCPUTurnDoesNotLandOnANewGame() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ShiritoriModel(services: services, cpuDelay: .milliseconds(50), seed: 1)
        model.configureForTesting(opener: apple, board: [gorilla, otter])
        model.select(0)
        let pending = Task { await model.runCPUTurnIfNeeded() }
        model.startGame()   // 待っている間に次のゲームが配られる（プレイヤーの番）
        await pending.value
        #expect(model.cpuCount == 0)
        #expect(model.isPlayerTurn)
    }

    @Test("実際の山札を最後まで遊びきると、どの種でも必ず決着する（プレイヤーは取れる札の先頭を取る）")
    func fullGamesAlwaysFinish() async {
        for seed in UInt64(0)..<100 {
            let (model, _) = makeModel(seed: seed)
            model.startGame(quota: .normal)
            for _ in 0..<40 where model.phase == .playing {
                if model.isPlayerTurn {
                    let tail = model.requiredTail ?? "ん"
                    guard let move = ShiritoriRules.moves(slots: model.slots, after: tail).first else { break }
                    model.select(move.slot)
                } else {
                    await model.runCPUTurnIfNeeded()
                }
            }
            #expect(model.phase == .result, "seed \(seed)")
            #expect(model.ending != nil)
            #expect(model.playerCount + model.cpuCount <= 19)
            #expect(model.playerCount >= model.cpuCount, "先手なので同数か 1 枚多い")
        }
    }
}
