import Testing
import Foundation
import Core
@testable import GameRoulette
import CoreTestSupport

// MARK: - Helpers

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    feedback: SpyFeedbackService = SpyFeedbackService(),
    playLog: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil
) -> GameServices {
    GameServices(
        snapshots: store,
        ads: NoopAdService(),
        feedback: feedback,
        playLog: playLog,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: ["roulette"]) }
    )
}

@MainActor
private func makePlayLog(_ suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.roulette.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 出目を決め打ちにした「回転中」の中断データを注入して起こす。`spinInterval` が `.zero` なので
/// 復帰した瞬間に精算まで進む（乱数に頼らず勝ち負けの局面を作る手口。ブラックジャック #439 と同型）。
@MainActor
private func makeSettledModel(
    chips: Int,
    bets: [RouletteBet],
    winningNumber: Int,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    hasRevived: Bool? = false,
    feedback: SpyFeedbackService = SpyFeedbackService(),
    playLog: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil
) -> RouletteModel {
    let snapshot = RouletteSnapshot(
        chips: chips, bets: bets, phase: .spinning, winningNumber: winningNumber,
        history: [], hasRevivedThisSession: hasRevived
    )
    try? store.save(snapshot, for: "roulette")
    return RouletteModel(services: makeServices(store: store, feedback: feedback, playLog: playLog, analytics: analytics))
}

// MARK: - Tests

@Suite("ルーレットの賭け（#1318）")
@MainActor
struct RouletteBettingTests {

    @Test("最初は 1000 枚・賭け中・口なし")
    func initialState() {
        let model = RouletteModel()
        #expect(model.chips == 1000)
        #expect(model.chips == RouletteModel.initialChips)
        #expect(model.phase == .betting)
        #expect(model.bets.isEmpty)
        #expect(model.totalBet == 0)
        #expect(model.availableChips == 1000)
        #expect(!model.sessionOver)
        #expect(model.canBet)
        #expect(!model.canSpin, "口が無ければ回せない")
        #expect(RouletteModel.chipOptions.contains(model.selectedChip))
    }

    @Test("選んだ額が 1 口ずつ積まれ、同じ場所は合算して見える")
    func placingBetsAccumulates() {
        let feedback = SpyFeedbackService()
        let model = RouletteModel(services: makeServices(feedback: feedback))
        model.selectedChip = 50
        model.placeBet(.red)
        model.placeBet(.red)
        model.selectedChip = 100
        model.placeBet(.straight(17))

        #expect(model.bets.count == 3)
        #expect(model.amount(on: .red) == 100)
        #expect(model.amount(on: .straight(17)) == 100)
        #expect(model.amount(on: .black) == 0)
        #expect(model.totalBet == 200)
        #expect(model.availableChips == 800)
        #expect(model.chips == 1000, "精算まで残高は減らない")
        #expect(model.canSpin)
        #expect(feedback.impacts.count == 3, "置くたびに触覚")
        #expect(Set(model.bets.map(\.id)).count == 3, "口の ID は重複しない")
    }

    @Test("残高を超える口は置けず、警告の触覚だけ鳴る")
    func cannotBetBeyondChips() {
        let feedback = SpyFeedbackService()
        let model = RouletteModel(services: makeServices(feedback: feedback))
        model.selectedChip = 500
        model.placeBet(.red)
        model.placeBet(.black)
        #expect(model.availableChips == 0)
        model.placeBet(.odd)
        #expect(model.bets.count == 2)
        #expect(model.totalBet == 1000)
        #expect(feedback.notices(of: .warning) == 1)
    }

    @Test("戻すは最後の 1 口だけ外し、全部戻すは空にする")
    func undoAndClear() {
        let model = RouletteModel(services: makeServices())
        model.selectedChip = 10
        model.placeBet(.red)
        model.placeBet(.straight(3))
        model.undoLastBet()
        #expect(model.bets.map(\.kind) == [.red])
        model.placeBet(.dozen(2))
        model.clearBets()
        #expect(model.bets.isEmpty)
        model.undoLastBet()
        #expect(model.bets.isEmpty, "空のときの戻すは何もしない")
    }

    @Test("口を置いた賭け中は中断データに残り、空に戻すと消える")
    func betsArePersistedWhilePlaced() {
        let store = MemorySnapshotStore()
        let model = RouletteModel(services: makeServices(store: store))
        #expect(!store.exists(for: "roulette"))
        model.selectedChip = 50
        model.placeBet(.high)
        #expect(store.exists(for: "roulette"))

        let restored = RouletteModel(services: makeServices(store: store))
        #expect(restored.phase == .betting)
        #expect(restored.bets.map(\.kind) == [.high])
        #expect(restored.amount(on: .high) == 50)
        #expect(restored.chips == 1000)

        restored.undoLastBet()
        #expect(!store.exists(for: "roulette"), "口が無ければ続きは無い")
    }
}

@Suite("ルーレットのスピンと精算（#1318）")
@MainActor
struct RouletteSpinTests {

    @Test("種を固定すれば出目は決定的で、精算は純関数と一致する")
    func spinIsDeterministicWithSeed() {
        let first = RouletteModel(services: makeServices(), seed: 20260924)
        let second = RouletteModel(services: makeServices(), seed: 20260924)
        for model in [first, second] {
            model.selectedChip = 10
            model.placeBet(.red)
            model.placeBet(.straight(0))
            model.spin()
        }
        let number = try! #require(first.winningNumber)
        #expect(second.winningNumber == number)
        #expect(RouletteWheel.numbers.contains(number))
        #expect(first.phase == .result, "待ち時間 0 なら回した瞬間に精算まで進む")
        let expected = rouletteSettlement(bets: first.bets, winningNumber: number)
        #expect(first.lastSettlement == expected)
        #expect(first.chips == 1000 + expected.net)
        #expect(first.history == [number])
        #expect(first.reviewOutcome == (expected.net > 0 ? .win : (expected.net == 0 ? .draw : .loss)))
    }

    @Test("同じ種でも 2 回目のスピンは前と別の出目になりうる（種が進む）")
    func seedAdvancesBetweenSpins() {
        let model = RouletteModel(services: makeServices(), seed: 7)
        var numbers: [Int] = []
        for _ in 0..<12 {
            model.selectedChip = 10
            model.placeBet(.red)
            model.spin()
            numbers.append(model.winningNumber!)
            if model.sessionOver { break }
            model.nextRound()
        }
        #expect(Set(numbers).count > 1, "12 回すべて同じ出目なら種が進んでいない: \(numbers)")
    }

    @Test("勝ちはチップが増えて決着の触覚、負けは減る")
    func settlementUpdatesChipsAndFeedback() {
        let win = SpyFeedbackService()
        let winner = makeSettledModel(chips: 1000, bets: [RouletteBet(id: 0, kind: .straight(17), amount: 10)],
                                      winningNumber: 17, feedback: win)
        #expect(winner.phase == .result)
        #expect(winner.chips == 1350)
        #expect(winner.lastSettlement?.net == 350)
        #expect(win.notices(of: .success) == 1)
        #expect(winner.reviewOutcome == .win)

        let lose = SpyFeedbackService()
        let loser = makeSettledModel(chips: 1000, bets: [RouletteBet(id: 0, kind: .straight(17), amount: 10)],
                                     winningNumber: 18, feedback: lose)
        #expect(loser.chips == 990)
        #expect(lose.notices(of: .error) == 1)
        #expect(loser.reviewOutcome == .loss)

        let push = SpyFeedbackService()
        let hedged = makeSettledModel(
            chips: 1000,
            bets: [RouletteBet(id: 0, kind: .red, amount: 10), RouletteBet(id: 1, kind: .black, amount: 10)],
            winningNumber: 1, feedback: push
        )
        #expect(hedged.chips == 1000)
        #expect(push.notices(of: .warning) == 1)
        #expect(hedged.reviewOutcome == .draw)
    }

    @Test("回転中の中断データは同じ出目で復帰し、精算後は消える")
    func spinningSnapshotResumesWithSameNumber() {
        let store = MemorySnapshotStore()
        let model = makeSettledModel(chips: 500, bets: [RouletteBet(id: 0, kind: .dozen(1), amount: 100)],
                                     winningNumber: 5, store: store)
        #expect(model.winningNumber == 5, "引き直さない")
        #expect(model.chips == 700)
        #expect(!store.exists(for: "roulette"), "精算済みの局は残さない")
    }

    @Test("次のゲームで盤面が空になり、同じ賭けでもう一度なら口が戻る")
    func nextRoundAndRepeat() {
        let model = makeSettledModel(chips: 1000,
                                     bets: [RouletteBet(id: 0, kind: .red, amount: 50), RouletteBet(id: 1, kind: .straight(2), amount: 10)],
                                     winningNumber: 2)
        #expect(model.phase == .result)
        model.repeatLastBets()
        #expect(model.phase == .betting)
        #expect(model.winningNumber == nil)
        #expect(model.lastSettlement == nil)
        #expect(model.bets.map(\.kind) == [.red, .straight(2)])
        #expect(model.bets.map(\.amount) == [50, 10])
        #expect(Set(model.bets.map(\.id)).count == 2)
        #expect(model.history == [2], "出目の履歴は残る")

        model.spin()
        model.nextRound()
        #expect(model.bets.isEmpty)
        #expect(model.phase == .betting)
    }

    @Test("同じ賭けでもう一度は、残高で置ける口だけ置く")
    func repeatSkipsUnaffordableBets() {
        // 赤 300 + 黒 700 で赤が出た → 戻りは 600・残高 600。もう一度で置けるのは赤の 300 だけ。
        let model = makeSettledModel(
            chips: 1000,
            bets: [RouletteBet(id: 0, kind: .red, amount: 300), RouletteBet(id: 1, kind: .black, amount: 700)],
            winningNumber: 1
        )
        #expect(model.chips == 600)
        model.repeatLastBets()
        #expect(model.bets.map(\.kind) == [.red])
        #expect(model.bets.map(\.amount) == [300])
        #expect(model.availableChips == 300)
    }

    @Test("いちばん安い賭けに届かなくなったらセッション終了")
    func sessionEndsWhenChipsFallBelowMinimumBet() {
        let model = makeSettledModel(chips: 10, bets: [RouletteBet(id: 0, kind: .straight(7), amount: 10)],
                                     winningNumber: 8)
        #expect(model.chips == 0)
        #expect(model.sessionOver)
        #expect(!model.canBet)
        #expect(model.canReviveAfterBust)
        model.placeBet(.red)
        #expect(model.bets.count == 1, "終わったセッションでは置けない（精算済みの口だけ残る）")
        model.nextRound()
        #expect(model.phase == .result, "終わったセッションでは次へ進めない")
    }

    @Test("賭ける前に戻した局面で残高が足りなければ、その場で終わり（#656 と同じ）")
    func restoringWithTooFewChipsEndsSession() {
        let store = MemorySnapshotStore()
        // 精算済み（`.result`）の中断データは本来書かないが、万一残っていたら賭ける前に戻して判定する。
        let snapshot = RouletteSnapshot(chips: 5, bets: [], phase: .result, winningNumber: 3, history: [3],
                                        hasRevivedThisSession: false)
        try? store.save(snapshot, for: "roulette")
        let model = RouletteModel(services: makeServices(store: store))
        #expect(model.phase == .betting)
        #expect(model.sessionOver)
        #expect(model.chips == 5, "端数はそのまま見せる")
    }

    @Test("最初からやり直すと 1000 枚・履歴も空")
    func restartSession() {
        let store = MemorySnapshotStore()
        let model = makeSettledModel(chips: 10, bets: [RouletteBet(id: 0, kind: .straight(7), amount: 10)],
                                     winningNumber: 8, store: store)
        #expect(model.sessionOver)
        model.restartSession()
        #expect(model.chips == 1000)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(model.bets.isEmpty)
        #expect(model.history.isEmpty)
        #expect(model.recordResult == nil)
        #expect(!store.exists(for: "roulette"))
    }

    @Test("出目の履歴は新しい順で最大 10 件")
    func historyIsCapped() {
        let model = RouletteModel(services: makeServices(), seed: 3)
        var numbers: [Int] = []
        for _ in 0..<12 {
            model.selectedChip = 10
            model.placeBet(.red)
            model.spin()
            numbers.insert(model.winningNumber!, at: 0)
            if model.sessionOver { break }
            model.nextRound()
        }
        #expect(model.history == Array(numbers.prefix(RouletteModel.historyLimit)))
        #expect(model.history.count <= 10)
    }
}

@Suite("ルーレットの解析・記録（#1318）")
@MainActor
struct RouletteMeasurementTests {

    @Test("1 スピン = game_start 1 回 + game_end 1 回。置いただけでは始まらない")
    func oneSpinIsOnePlay() {
        let spy = SpyAnalyticsService()
        let model = RouletteModel(services: makeServices(analytics: spy), seed: 1)
        model.selectedChip = 10
        model.placeBet(.red)
        #expect(spy.events.isEmpty, "口を置いただけではプレイが始まらない")
        model.spin()
        #expect(spy.starts(of: "roulette") == 1)
        #expect(spy.ends(of: "roulette") == 1)
        model.nextRound()
        model.placeBet(.black)
        model.spin()
        #expect(spy.starts(of: "roulette") == 2)
        #expect(spy.ends(of: "roulette") == 2)
    }

    @Test("精算後のチップが最高記録になる")
    func recordsChipsAsPoints() {
        let (log, defaults, name) = makePlayLog("record")
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeSettledModel(chips: 1000, bets: [RouletteBet(id: 0, kind: .straight(17), amount: 10)],
                                     winningNumber: 17, playLog: log)
        let record = log.record(gameID: "roulette")
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == 1350)
        #expect(record?.bestPoints == model.chips)
        #expect(record?.plays == 1)
        #expect(model.recordResult != nil)
    }

    @Test("旧データ（hasRevivedThisSession の鍵なし）も読める")
    func decodesSnapshotWithoutRevivedKey() throws {
        let store = MemorySnapshotStore()
        let snapshot = RouletteSnapshot(chips: 800, bets: [RouletteBet(id: 0, kind: .low, amount: 100)],
                                        phase: .betting, winningNumber: nil, history: [4, 9], hasRevivedThisSession: nil)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "hasRevivedThisSession")
        store.inject(try JSONSerialization.data(withJSONObject: object), for: "roulette")

        let model = RouletteModel(services: makeServices(store: store))
        #expect(model.chips == 800)
        #expect(model.bets.map(\.kind) == [.low])
        #expect(model.history == [4, 9])
        #expect(!model.sessionOver)
    }
}
