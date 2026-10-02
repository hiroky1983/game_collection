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

    @Test("開始（ノルマ）: 30 枚が並び、別の 1 枚が場の札。山札 50 枚のうち 31 枚だけ使う。時間は 60 秒でプレイヤーが先手")
    func startDealsTwentyNineAndOpensOne() {
        let (model, _) = makeModel()
        model.startGame(quota: .hard)

        #expect(model.phase == .playing)
        #expect(model.slots.count == 30)
        let ids = model.slots.map(\.card.id) + [model.currentCard?.id ?? ""]
        #expect(Set(ids).count == 31, "盤 30 枚と場の 1 枚は重ならない")
        #expect(Set(ids).isSubset(of: Set(ShiritoriCard.deck.map(\.id))))
        #expect(model.mode == .quota && model.stock.isEmpty, "ノルマは山札を使わない")
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

    @Test("時間切れ: 1 枚も取っていなければ負け")
    func timeUpWithNothingTakenLoses() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], quota: .easy)
        model.tick(60)

        #expect(model.ending == .timeUp)
        #expect(!model.didPlayerWin)
        #expect(model.phase == .result)
        model.tick(5)
        model.select(0)
        #expect(model.slots[0].owner == nil, "決着後は操作できない")
    }

    @Test("CPU が続けられない: ノルマに届いていなくても勝ち（会長決裁 2026-09-21・#1245）")
    func cpuStuckAlwaysWins() async {
        // りんご →(あなた)ごりら →(CPU)らっこ →(あなた)こま →(CPU 詰み)。2 対 1 はどの難易度のノルマ（4 枚以上）にも届かない。
        for quota in ShiritoriQuota.allCases {
            let (model, _) = makeModel()
            model.configureForTesting(opener: apple, board: [gorilla, otter, top], quota: quota)
            model.select(0)
            await model.runCPUTurnIfNeeded()             // らっこ
            #expect(model.cpuCount == 1)
            model.select(2)                              // こま（語尾ま）
            #expect(model.ending == .cpuStuck, "\(quota)")
            #expect(model.playerCount == 2 && model.cpuCount == 1)
            #expect(!model.isQuotaMet, "ノルマは満たしていない局面で確かめる")
            #expect(model.didPlayerWin, "\(quota): 詰ませたら枚数に関係なく勝ち")
            #expect(model.phase == .result)
        }
    }

    @Test("プレイヤーが続けられない: 負け")
    func playerStuckAlwaysLoses() async {
        for quota in ShiritoriQuota.allCases {
            let (model, _) = makeModel()
            // りんご →(あなた)ごりら →(CPU)らっこ → こ から始まる札は無い。
            model.configureForTesting(opener: apple, board: [gorilla, otter], quota: quota)
            model.select(0)
            await model.runCPUTurnIfNeeded()
            #expect(model.ending == .playerStuck, "\(quota)")
            #expect(model.playerCount == 1 && model.cpuCount == 1)
            #expect(!model.didPlayerWin, "\(quota)")
        }
    }

    @Test("時間切れは常に負け: ノルマ未達のまま時間が尽きる（同数でもやさしいで救われない）")
    func timeUpAlwaysLoses() async {
        for quota in ShiritoriQuota.allCases {
            let (model, _) = makeModel()
            model.configureForTesting(opener: apple, board: [gorilla, otter, top], quota: quota)
            model.select(0)
            await model.runCPUTurnIfNeeded()             // らっこ。あなたの番で 1 対 1
            model.tick(100)
            #expect(model.ending == .timeUp, "\(quota)")
            #expect(model.playerCount == 1 && model.cpuCount == 1)
            #expect(!model.didPlayerWin, "\(quota)")
        }
    }

    /// りんご →(あなた)ごりら →(CPU)らっこ →(あなた)こま →(CPU)まくら →(あなた)らくだ →(CPU)だるま →(あなた)まり。
    /// あなたは 4 枚（ごりら・こま・らくだ・まり）、CPU は 3 枚。CPU は盤の並び順で最初に受けられる札を取る。
    private static let quotaChain = [
        ShiritoriCard(.gorilla, "ごりら"), ShiritoriCard(.seaOtter, "らっこ"), ShiritoriCard(.spinningTop, "こま"),
        ShiritoriCard(.pillow, "まくら"), ShiritoriCard(.camel, "らくだ"), ShiritoriCard(.ostrich, "だるま"),
        ShiritoriCard(.ball, "まり"),
    ]

    private func playQuotaChain(_ model: ShiritoriModel) async {
        for playerSlot in [0, 2, 4, 6] where model.phase == .playing {
            model.select(playerSlot)
            await model.runCPUTurnIfNeeded()
        }
    }

    @Test("ノルマの枚数に届いた瞬間に勝ち（時間切れを待たない・#1245）。やさしいは 4 枚目で決着する")
    func reachingTheQuotaWinsImmediately() async {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: Self.quotaChain, quota: .easy)
        await playQuotaChain(model)

        #expect(model.ending == .quotaReached)
        #expect(model.playerCount == 4 && model.cpuCount == 3)
        #expect(model.didPlayerWin)
        #expect(model.timeRemaining > 0, "時間は残っている")
        #expect(model.phase == .result)
        #expect(model.reviewOutcome == .win)
    }

    @Test("同じ 4 枚でも、ふつう（6 枚）ではまだ届かない。決着は CPU の詰みまで持ち越す")
    func fourCardsDoNotReachNormalQuota() async {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: Self.quotaChain, quota: .normal)
        await playQuotaChain(model)

        #expect(model.playerCount == 4)
        #expect(!model.isQuotaMet)
        #expect(model.ending == .cpuStuck, "ノルマ未達でも詰ませて勝つ経路は残る")
    }

    @Test("ノルマに届く札が「ん」で終わるなら、ノルマより「ん」の負けが先")
    func hittingNBeatsReachingTheQuota() async {
        let (model, _) = makeModel()
        // 4 枚目（まり の代わりに まん）が「ん」で終わる。
        var board = Self.quotaChain
        board[6] = ShiritoriCard(.ball, "まん")
        model.configureForTesting(opener: apple, board: board, quota: .easy)
        await playQuotaChain(model)

        #expect(model.ending == .playerHitN)
        #expect(!model.didPlayerWin)
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
        // りんご →(あなた)ごりら →(CPU の手は らーめん だけ)。1 対 1 でノルマ（6 枚）には届かない成績でも、CPU が「ん」を選ばされたら勝ち。
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

    @Test("CPU の手番はまずカーソルが対象へ移り、間を置いてから確定する（#1286）")
    func cpuTurnMovesCursorBeforeClaiming() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ShiritoriModel(services: services, cpuDelay: .zero, cpuCursorDelay: .milliseconds(20), seed: 1)
        model.configureForTesting(opener: apple, board: [gorilla, otter, top, squirrel])
        model.select(0)   // ごりら → CPU は らっこ（index 1）
        #expect(model.cpuCursorSlot == nil, "カーソルはまだ立っていない")

        let task = Task { await model.runCPUTurnIfNeeded() }
        await Task { }.value   // CPU タスクの後ろに積まれるので、走った時点でカーソルは立っている
        #expect(model.cpuCursorSlot == 1, "対象スロットへカーソルが動く")
        #expect(model.slots[1].owner == nil, "カーソルが立った直後はまだ確定していない")

        await task.value
        #expect(model.cpuCursorSlot == nil, "確定したらカーソルは消える")
        #expect(model.slots[1].owner == .cpu)
    }

    @Test("CPU のカーソルは対象より手前の未確定札も左から右へなぞってから止まる（会長指摘 2026-09-23）")
    func cpuCursorSweepsThroughEarlierSlotsBeforeSettling() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ShiritoriModel(
            services: services, cpuDelay: .zero,
            cpuCursorDelay: .milliseconds(200), cpuCursorStepDelay: .milliseconds(10), seed: 1
        )
        // squirrel（りす）は「ら」を受けないので通過するだけ。otter（らっこ）が実際の対象。
        model.configureForTesting(opener: gorilla, board: [squirrel, otter], isPlayerTurn: false)

        let task = Task { await model.runCPUTurnIfNeeded() }
        await Task { }.value
        #expect(model.cpuCursorSlot == 0, "まず手前の未確定札（りす）へカーソルが立つ")
        #expect(model.slots[0].owner == nil, "通過しただけで取られてはいない")

        // 固定回数の Task.yield() は実時間の経過を保証しないため、高速な CI 環境では
        // cpuCursorStepDelay（10ms）の完了前にループが尽きてフレークする
        // （CodeRabbit指摘・PR #1313）。実時間の期限で打ち切るポーリングに変える。
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while model.cpuCursorSlot != 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(model.cpuCursorSlot == 1, "なぞり終えて対象（らっこ）へ移る")
        #expect(model.slots[1].owner == nil, "対象へ着いた直後はまだ確定していない")

        await task.value
        #expect(model.cpuCursorSlot == nil, "確定したらカーソルは消える")
        #expect(model.slots[0].owner == nil, "通過しただけの札は取られない")
        #expect(model.slots[1].owner == .cpu, "対象だけが取られる")
    }

    @Test("演出待ちの間に新しいゲームが始まったら、カーソルも残らない")
    func staleCPUCursorIsClearedByNewGame() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = ShiritoriModel(services: services, cpuDelay: .zero, cpuCursorDelay: .milliseconds(20), seed: 1)
        model.configureForTesting(opener: apple, board: [gorilla, otter])
        model.select(0)
        let pending = Task { await model.runCPUTurnIfNeeded() }
        await Task { }.value
        #expect(model.cpuCursorSlot != nil, "前提: カーソルが立っている")

        model.startGame()   // 待っている間に次のゲームが配られる
        await pending.value
        #expect(model.cpuCursorSlot == nil)
        #expect(model.cpuCount == 0)
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
        var alternateWasPlayed = false
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
                if case .played(_, _, let isAlternate) = model.lastEvent, isAlternate {
                    alternateWasPlayed = true
                }
            }
            #expect(model.phase == .result, "seed \(seed)")
            #expect(model.ending != nil)
            #expect(model.playerCount + model.cpuCount <= 30)
            #expect(model.playerCount >= model.cpuCount, "先手なので同数か 1 枚多い")
        }
        // 残る裏読み「にゃんこ」（#1271 で「ぐらす」「おうぎ」を削除した後）が、実プレイで
        // 一度も選ばれないなら、それも到達不能な裏読みが紛れている兆候。
        #expect(alternateWasPlayed, "100 シードのどのゲームでも裏読みが一度も選ばれなかった")
    }
}

// MARK: - 新規ゲームで失われる進行（#1011）

@Suite("カードしりとり 新規ゲームで失われる進行（#1011）")
@MainActor
struct ShiritoriProgressToLoseTests {

    @Test("開始前は失うものが無く、対局中は失う進行がある")
    func onlyWhilePlaying() {
        let (model, _) = makeModel()
        #expect(!model.hasProgressToLose)
        model.startGame()
        #expect(model.hasProgressToLose)
    }

    @Test("一時停止しても対局中には変わりない（ボタンが pause してから確認を出すため）")
    func pausedStillCounts() {
        let (model, _) = makeModel()
        model.startGame()
        model.pause()
        #expect(model.hasProgressToLose)
    }
}

// MARK: - とことんモード（#1502）

private let kasa = ShiritoriCard(.umbrella, "かさ")            // か → さ
private let aardvark = ShiritoriCard(.deer, "らくだ")          // ら → だ（絵は使い回し。配りの検査には使わない）
private let bamboo = ShiritoriCard(.bamboo, "だちょう")        // だ → う
private let rabbit = ShiritoriCard(.rabbit, "うさぎ")          // う → ぎ
private let guitar = ShiritoriCard(.guitar, "ぎたー")          // ぎ → た
private let drum = ShiritoriCard(.drum, "たいこ")              // た → こ
private let koala = ShiritoriCard(.koala, "こあら")            // こ → ら

@Suite("カードしりとり とことんモード（#1502）")
@MainActor
struct ShiritoriEndlessTests {

    @Test("配り: 盤 30 枚・場 1 枚・山札 19 枚が重ならず全 50 枚。ノルマは山札を使わない")
    func dealSplitsFiftyCards() {
        for seed in UInt64(0)..<100 {
            let (model, _) = makeModel(seed: seed)
            model.startGame(mode: .endless)
            let ids = model.slots.map(\.card.id) + [model.currentCard?.id ?? ""] + model.stock.map(\.id)
            #expect(model.slots.count == 30 && model.stock.count == 19, "seed \(seed)")
            #expect(Set(ids) == Set(ShiritoriCard.deck.map(\.id)) && ids.count == 50, "seed \(seed)")
            #expect(model.stockCount == 19)
        }
    }

    @Test("最初の盤面では絶対に詰まない: どちらのモードでも、多数の種でプレイヤーの 1 手目が盤にある")
    func firstMoveAlwaysExistsInBothModes() {
        for mode in ShiritoriMode.allCases {
            for seed in UInt64(0)..<500 {
                let (model, _) = makeModel(seed: seed)
                model.startGame(mode: mode)
                #expect(model.phase == .playing, "\(mode) seed \(seed)")
                let tail = model.requiredTail
                #expect(tail != nil && tail != "ん", "\(mode) seed \(seed)")
                #expect(!ShiritoriRules.moves(slots: model.slots, after: tail ?? "ん").isEmpty, "\(mode) seed \(seed)")
            }
        }
    }

    @Test("配りに詰み専用の札が無い: 場と盤（とことんは山札も）のどの読みの語尾も、ほかの札で受けられる")
    func dealHasNoDeadEnd() {
        for mode in ShiritoriMode.allCases {
            for seed in UInt64(0)..<200 {
                let (model, _) = makeModel(seed: seed)
                model.startGame(mode: mode)
                let opener = model.currentCard.map { [$0] } ?? []
                let cards = model.slots.map(\.card) + model.stock
                // 開場札は場に出ているので、受け手は盤と山札の札。
                let pool = cards
                for card in pool {
                    let others = pool.filter { $0.id != card.id }.map { ShiritoriSlot(card: $0) }
                    for reading in card.readings {
                        guard !ShiritoriRules.endsWithN(reading), let tail = ShiritoriKana.tail(of: reading) else { continue }
                        #expect(!ShiritoriRules.moves(slots: others, after: tail).isEmpty,
                                "\(mode) seed \(seed): \(card.id) の \(reading) に後続がない（場: \(opener.first?.id.description ?? "")）")
                    }
                }
            }
        }
    }

    @Test("取ると空いた場所へ山札の先頭が補充され、山札は 1 枚減る。取った枚数は数え続ける")
    func claimRefillsFromStock() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [otter, top])
        model.select(0)

        #expect(model.slots[0].card == otter && model.slots[0].owner == nil, "同じ場所に山札の先頭が出る")
        #expect(model.slots[1].card == kasa)
        #expect(model.stock == [top])
        #expect(model.currentCard == gorilla)
        #expect(model.playerCount == 1 && model.cpuCount == 0)
        #expect(model.phase == .playing && !model.isPlayerTurn, "補充された札で CPU は続けられる")
    }

    /// #1659: とことんは CPU が盤の左から取り進めるので、山札に後続が残っているのにプレイヤーが詰んで負けになる
    /// 局が約半数あった（測定: ランダムに打つ人で 47%）。
    @Test("CPU が取った直後にプレイヤーの続けられる札が盤に無いとき、山札から続けられる札を先に補充する")
    func refillPicksFollowerWhenPlayerWouldBeStuck() async {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [top, otter], isPlayerTurn: false)
        await model.runCPUTurnIfNeeded()   // CPU が ごりら（ら）を取る。盤に残る かさ では ら を受けられない

        #expect(model.slots[0].card == otter, "山札の先頭（こま）ではなく、ら を受けられる らっこ が出る")
        #expect(model.stock == [top])
        #expect(model.phase == .playing && model.isPlayerTurn, "詰みにならず、プレイヤーの番になる")
    }

    @Test("盤にプレイヤーの続けられる札があるなら、山札は先頭から補充する（順序を崩さない）")
    func refillKeepsOrderWhenPlayerCanContinue() async {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, otter], mode: .endless, stock: [top, kasa], isPlayerTurn: false)
        await model.runCPUTurnIfNeeded()   // CPU が ごりら を取る。盤の らっこ で続けられる

        #expect(model.slots[0].card == top)
        #expect(model.stock == [kasa])
    }

    @Test("プレイヤーが取った直後は、CPU が詰む補充でも山札の先頭のまま（CPU を詰ませて勝つ道を残す）")
    func refillAfterPlayerClaimIsNotRescued() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [top, otter])
        model.select(0)

        #expect(model.slots[0].card == top)
        #expect(model.ending == .cpuStuck && model.didPlayerWin)
    }

    @Test("山札が尽きたら補充されず、取られた札が盤に残る")
    func noRefillWhenStockIsEmpty() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [])
        model.select(0)

        #expect(model.slots[0].card == gorilla && model.slots[0].owner == .player)
        #expect(model.ending == .cpuStuck && model.didPlayerWin, "受けられる札が盤に無い（かさ ← ら）ので CPU は詰み")
    }

    @Test("補充で続けられるようになった手は詰みではない（補充してから詰みを見る）")
    func refillIsSeenBeforeStuckCheck() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [otter])
        model.select(0)
        #expect(model.ending == nil, "ごりら → 補充された らっこ で CPU は続けられる")
    }

    @Test("パーフェクト: 盤と山札の最後の 1 枚をプレイヤーが取ったら勝ち。時間は成立ぶん増える")
    func playerTakesLastCardIsPerfect() {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], mode: .endless, stock: [])
        model.select(0)

        #expect(model.phase == .result && model.ending == .perfect)
        #expect(model.didPlayerWin)
        #expect(model.reviewOutcome == .win)
        #expect(model.playerCount == 1)
    }

    @Test("パーフェクト: CPU が最後の 1 枚を取っても、札が全部なくなればプレイヤーの勝ち")
    func cpuTakesLastCardIsStillPerfect() async {
        let (model, _) = makeModel()
        model.configureForTesting(opener: apple, board: [gorilla], mode: .endless, stock: [], isPlayerTurn: false)
        await model.runCPUTurnIfNeeded()

        #expect(model.ending == .perfect && model.didPlayerWin)
        #expect(model.cpuCount == 1)
    }

    @Test("ノルマは無い: ノルマの枚数を取っても終わらず、続けられる限り続く")
    func quotaDoesNotApply() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            opener: apple, board: [gorilla, otter, koala, ShiritoriCard(.camel, "らくだ"), bamboo, rabbit, guitar, drum],
            quota: .easy, mode: .endless, stock: []
        )
        // あなた: ごりら → CPU: らっこ → あなた: こあら → CPU: らくだ → あなた: だちょう → CPU: うさぎ → あなた: ぎたー（4 枚目）
        for pick in [0, 2, 4] {
            model.select(pick)
            await model.runCPUTurnIfNeeded()
        }
        model.select(6)

        #expect(model.playerCount == 4 && model.quota == .easy)
        #expect(!model.isQuotaMet)
        #expect(model.ending == nil && model.phase == .playing, "ノルマ 4 枚に届いても終わらない")
    }

    @Test("負け筋は従来どおり: 続けられない・時間切れ・「ん」")
    func lossesAndTimeUp() {
        // 続けられない（CPU の番でプレイヤーが受けられる札が盤にも山札にも無い）
        let (stuck, _) = makeModel()
        stuck.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [], isPlayerTurn: true)
        stuck.select(1)   // かさ ← り はお手つき
        #expect(stuck.lastEvent == .miss && stuck.phase == .playing)

        let (timeUp, _) = makeModel()
        timeUp.configureForTesting(opener: apple, board: [gorilla, kasa], mode: .endless, stock: [otter])
        timeUp.tick(ShiritoriTime.initial)
        #expect(timeUp.ending == .timeUp && !timeUp.didPlayerWin, "とことんでも時間切れは負け")

        let (n, _) = makeModel()
        n.configureForTesting(opener: apple, board: [trapForPlayer, gorilla], mode: .endless, stock: [otter])
        n.select(0)
        #expect(n.ending == .playerHitN && !n.didPlayerWin)
    }

    @Test("モードは局に焼き込まれる: 次の startGame で mode を渡さなければ前の局のモードのまま")
    func modeIsBakedIntoTheGame() {
        let (model, _) = makeModel()
        model.startGame(mode: .endless)
        #expect(model.mode == .endless)
        model.startGame()
        #expect(model.mode == .endless, "省略したら直前の選択を引き継ぐ（開始シートの初期値と同じ）")
        model.startGame(mode: .quota)
        #expect(model.mode == .quota && model.stock.isEmpty)
    }

    @Test("とことんの実プレイ: どの種でも必ず決着し、取った枚数は 49 枚を超えない")
    func fullEndlessGamesAlwaysFinish() async {
        for seed in UInt64(0)..<40 {
            let (model, _) = makeModel(seed: seed)
            model.startGame(mode: .endless)
            for _ in 0..<120 where model.phase == .playing {
                if model.isPlayerTurn {
                    let tail = model.requiredTail ?? "ん"
                    guard let move = ShiritoriRules.moves(slots: model.slots, after: tail).first else { break }
                    model.select(move.slot)
                } else {
                    await model.runCPUTurnIfNeeded()
                }
            }
            #expect(model.phase == .result, "seed \(seed)")
            #expect(model.playerCount + model.cpuCount <= 49)
        }
    }

    @Test("結果の文言: パーフェクトと、とことんの時間切れにノルマの話を出さない")
    func presentation() {
        #expect(ShiritoriPresentation.resultTitle(ending: .perfect, didWin: true, mode: .endless).contains("パーフェクト"))
        #expect(!ShiritoriPresentation.resultTitle(ending: .timeUp, didWin: false, mode: .endless).contains("ノルマ"))
        #expect(ShiritoriPresentation.resultTitle(ending: .timeUp, didWin: false).contains("ノルマ"), "従来の文言は変えない")
        let detail = ShiritoriPresentation.resultDetail(player: 5, cpu: 4, quota: .normal, ending: .timeUp, mode: .endless)
        #expect(!detail.contains("ノルマ"))
    }
}

// MARK: - 広告で時間を延長（#1717）

@Suite("カードしりとり: 時間切れから広告で続ける（#1717）")
@MainActor
struct ShiritoriTimeExtensionTests {
    private func makeLoggedModel(_ suite: String) -> (ShiritoriModel, PlayLog) {
        let name = "asobiba.shiritori.tests.extend.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = ShiritoriModel(services: services, cpuDelay: .zero, seed: 1)
        model.configureForTesting(opener: apple, board: [gorilla, squirrel, otter])
        return (model, log)
    }

    private func plays(_ log: PlayLog) -> Int { log.record(gameID: "shiritori")?.plays ?? 0 }

    @Test("時間切れの結果では負けをまだ記録せず、続ける選択肢が出る")
    func timeUpHoldsTheRecord() {
        let (model, log) = makeLoggedModel("hold")
        model.tick(ShiritoriTime.initial)

        #expect(model.phase == .result && model.ending == .timeUp && !model.didPlayerWin)
        #expect(model.canExtendTime)
        #expect(plays(log) == 0)
        #expect(model.recordResult == nil)
    }

    @Test("続けると 30 秒が足され、同じ局がプレイヤーの手番で再開する。勝敗は記録されない")
    func extendResumesWithoutRecording() {
        let (model, log) = makeLoggedModel("extend")
        model.tick(ShiritoriTime.initial)
        #expect(model.extendTimeAfterAd(forGame: model.gameNumber))

        #expect(model.phase == .playing && model.ending == nil && model.isPlayerTurn)
        #expect(model.timeRemaining == 30)
        #expect(model.currentCard == apple, "盤面は保たれる")
        #expect(!model.canExtendTime, "1 局 1 回")
        #expect(plays(log) == 0)

        model.select(0)   // 続きを遊べる（取れば +10 秒）
        #expect(model.timeRemaining == 40)
    }

    @Test("続けたあとの 2 度目の時間切れは、その場で負けを 1 回だけ記録する")
    func secondTimeUpRecordsOnce() {
        let (model, log) = makeLoggedModel("second")
        model.tick(ShiritoriTime.initial)
        #expect(model.extendTimeAfterAd(forGame: model.gameNumber))
        model.tick(30)

        #expect(model.phase == .result && model.ending == .timeUp)
        #expect(!model.canExtendTime)
        #expect(plays(log) == 1)
        model.commitTimeUpLoss()
        #expect(plays(log) == 1, "冪等")
    }

    @Test("続けない（commit）と負けが 1 回だけ記録され、続ける導線は消える")
    func declineRecordsOnce() {
        let (model, log) = makeLoggedModel("decline")
        model.tick(ShiritoriTime.initial)
        model.commitTimeUpLoss()
        model.commitTimeUpLoss()

        #expect(plays(log) == 1)
        #expect(model.recordResult != nil)
        #expect(!model.canExtendTime)
        #expect(!model.extendTimeAfterAd(forGame: model.gameNumber), "記録した後は延長できない")
    }

    @Test("「もう一度」で始め直すと、保留していた負けを先に記録する。次の局ではまた延長できる")
    func restartCommitsPendingLoss() {
        let (model, log) = makeLoggedModel("restart")
        model.tick(ShiritoriTime.initial)
        model.startGame()

        #expect(plays(log) == 1)
        #expect(model.phase == .playing && !model.hasExtendedTime)
        model.tick(ShiritoriTime.initial)
        #expect(model.canExtendTime, "新しい局では権利が戻る")
    }

    @Test("広告を見ているあいだに局が入れ替わったら延長しない（局ガード）")
    func staleSerialIsRejected() {
        let (model, _) = makeLoggedModel("stale")
        model.tick(ShiritoriTime.initial)
        let serial = model.gameNumber
        model.startGame()
        model.tick(ShiritoriTime.initial)

        #expect(!model.extendTimeAfterAd(forGame: serial))
        #expect(model.phase == .result)
    }

    @Test("時間切れ以外の決着（勝ち・「ん」の負け）には延長を出さず、その場で記録する")
    func onlyTimeUpIsExtendable() {
        let (win, winLog) = makeLoggedModel("win")
        win.configureForTesting(opener: apple, board: [gorilla])   // 取ると CPU が続けられない
        win.select(0)
        #expect(win.ending == .cpuStuck && !win.canExtendTime)
        #expect(plays(winLog) == 1)

        let (hitN, hitNLog) = makeLoggedModel("hitN")
        hitN.configureForTesting(opener: apple, board: [trapForPlayer])
        hitN.select(0)
        #expect(hitN.ending == .playerHitN && !hitN.canExtendTime)
        #expect(plays(hitNLog) == 1)
    }
}
