import Testing
import Foundation
import Core
@testable import GameSolitaire

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

private final class FeedbackSpy: FeedbackService, @unchecked Sendable {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    @MainActor func impact(_ style: FeedbackImpact) { impacts.append(style) }
    @MainActor func notify(_ type: FeedbackNotice) { notices.append(type) }
}

@MainActor
private func makeLog(suite: String) -> PlayLog {
    let name = "asobiba.solitaire.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return PlayLog(defaults: defaults)
}

@MainActor
private func makeServices(
    store: SnapshotStore = MemorySnapshotStore(),
    playLog: PlayLog? = nil
) -> (GameServices, FeedbackSpy) {
    let spy = FeedbackSpy()
    return (
        GameServices(snapshots: store, ads: NoopAdService(), feedback: spy, playLog: playLog),
        spy
    )
}

/// 使い回す固定種（`SolitaireDealer.verifiedSeeds` の先頭。ソルバー検証済み）。
private let fixedSeed = SolitaireDealer.verifiedSeeds[0]

/// ソルバーの勝ち筋を、**View と同じタップ操作に翻訳して**指す。
///
/// 直接 `SolitaireBoard.apply` を呼ばずタップ経路を通すのは、選択 → 置き先という 2 段の
/// 操作そのものを 1 局ぶん通しで検証するため（View を組まずに触れるのはここが唯一の面）。
@MainActor
private func play(_ model: SolitaireModel, _ moves: [SolitaireMove]) {
    for move in moves {
        switch move {
        case .draw:
            model.tapStock()
        case .wasteToFoundation:
            guard let suit = model.board.waste.last?.suit else { continue }
            model.tapWaste()
            model.tapFoundation(suit)
        case .wasteToTableau(let pile):
            model.tapWaste()
            model.tapPile(pile)
        case .tableauToFoundation(let pile):
            guard let suit = model.board.tableau[pile].top?.suit else { continue }
            model.tapPile(pile)
            model.tapFoundation(suit)
        case .tableauToTableau(let from, let index, let to):
            model.tapPile(from, cardIndex: index)
            model.tapPile(to)
        case .placeJoker(let pile):
            model.placeJoker(onPile: pile)
        }
    }
}

// MARK: - 進行

@Suite("ソリティアの進行")
@MainActor
struct SolitaireModelTests {

    @Test("開始時はクロンダイクの初期配置で、計時も手数も 0 から始まる")
    func initialBoard() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(model.phase == .playing)
        #expect(model.board.tableau.map(\.faceUp.count) == Array(repeating: 1, count: 7))
        #expect(model.board.tableau.map(\.faceDown.count) == [0, 1, 2, 3, 4, 5, 6])
        #expect(model.board.stock.count == 24)
        #expect(model.moveCount == 0)
        #expect(model.elapsedSeconds == 0)
        #expect(!model.canUndo)
    }

    @Test("札をタップして選び、置き先をタップすると動く")
    func selectThenPlace() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        // 場札から場札へ動かせる組を、盤面から 1 つ見つけて指す。
        var found = false
        outer: for from in 0..<SolitaireBoard.pileCount {
            for to in 0..<SolitaireBoard.pileCount where from != to {
                let move = SolitaireMove.tableauToTableau(from: from, cardIndex: 0, to: to)
                guard model.board.isLegal(move) else { continue }
                let card = model.board.tableau[from].faceUp[0]
                model.tapPile(from, cardIndex: 0)
                #expect(model.selection == .tableau(pile: from, cardIndex: 0))
                model.tapPile(to)
                #expect(model.selection == nil)
                #expect(model.board.tableau[to].top == card)
                #expect(model.moveCount == 1)
                found = true
                break outer
            }
        }
        #expect(found, "初期配置に場札どうしの合法手が 1 つも無い（種の選び直しが要る）")
    }

    @Test("同じ札をもう一度タップすると選択が外れる")
    func tapTwiceDeselects() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tapPile(0, cardIndex: 0)
        #expect(model.selection != nil)
        model.tapPile(0, cardIndex: 0)
        #expect(model.selection == nil)
    }

    @Test("置けない先をタップしても盤面は動かず、拒否として数える")
    func illegalDestinationIsRejected() {
        let (services, spy) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let before = model.board
        // 組札は A からしか始まらないので、A 以外を選んで組札を叩けば必ず拒否される。
        let pile = (0..<SolitaireBoard.pileCount).first { model.board.tableau[$0].top?.rank != 1 }
        let target = try! #require(pile)
        let suit = try! #require(model.board.tableau[target].top?.suit)
        model.tapPile(target, cardIndex: 0)
        model.tapFoundation(suit)
        #expect(model.board == before)
        #expect(model.rejectedTapCount == 1)
        #expect(spy.notices.contains(.warning))
    }

    @Test("無料の回数ぶんは戻せ、配ったばかりの状態まで戻れる")
    func undoRewindsToTheDeal() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let initial = model.board
        for _ in 0..<SolitaireUndoBudget.free { model.tapStock() }
        #expect(model.board != initial)
        #expect(model.canUndo)
        for _ in 0..<SolitaireUndoBudget.free { #expect(model.undo()) }
        #expect(model.board == initial)
        #expect(model.moveCount == 0)
    }

    @Test("山めくりは手数に数えない（数えると1局で数百手になる）")
    func drawsAreNotCountedAsMoves() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        for _ in 0..<10 { model.tapStock() }
        #expect(model.moveCount == 0)
        #expect(model.canUndo, "めくった手そのものは戻せる")
    }

    // MARK: - めくり演出のトリガー（#421）

    @Test("山めくりの直後だけ、捨て札の1枚を裏から返す対象にする")
    func drawMarksTheWasteCardAsFlipping() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(!model.lastMoveWasDraw, "配ったばかりの盤面では返す札が無い")

        model.tapStock()
        #expect(model.lastMoveWasDraw)

        // 捨て札を場に出すと、下から出てくる札は**もともと表**なので返さない。
        // 出せる先が無い配札もあるので、動かせたときだけ見る。
        if let card = model.board.waste.last,
           let pile = (0..<SolitaireBoard.pileCount).first(where: {
               model.board.isLegal(.wasteToTableau(pile: $0))
           }) {
            model.tapWaste()
            model.tapPile(pile)
            #expect(model.board.tableau[pile].top == card)
            #expect(!model.lastMoveWasDraw)
        }

        // 戻したぶんまで返して見せると「新しくめくれた」と読めてしまう。
        model.undo()
        #expect(!model.lastMoveWasDraw)
        #expect(model.revealedCardIDs.isEmpty)
    }

    @Test("伏せ札から出てきた札だけを、裏から返す対象にする")
    func uncoveredCardIsMarkedAsFlipping() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)

        // 表向き 1 枚だけの列を動かすと、その下の伏せ札が 1 枚めくれる。
        var moved = false
        outer: for from in 1..<SolitaireBoard.pileCount {
            for to in 0..<SolitaireBoard.pileCount where to != from {
                let move = SolitaireMove.tableauToTableau(from: from, cardIndex: 0, to: to)
                guard model.board.isLegal(move), !model.board.tableau[from].faceDown.isEmpty else { continue }
                let hidden = model.board.tableau[from].faceDown.last!
                model.tapPile(from, cardIndex: 0)
                model.tapPile(to)
                #expect(model.revealedCardIDs == [hidden.id])
                #expect(model.board.tableau[from].top == hidden)
                moved = true

                // 巻き戻すと対象は消える（戻した札を返して見せない）。
                model.undo()
                #expect(model.revealedCardIDs.isEmpty)
                break outer
            }
        }
        #expect(moved, "この配札では伏せ札がめくれる手が見つからなかった")
    }

    @Test("配り直すと配札の演出の対象に戻り、返す札は残らない")
    func newGameResetsTheFlipTargets() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(model.isFreshDeal)

        model.tapStock()
        #expect(!model.isFreshDeal, "1 手でも指したら配札の演出は出さない")
        #expect(model.lastMoveWasDraw)

        let serial = model.dealSerial
        model.newGame()
        #expect(model.isFreshDeal)
        #expect(!model.lastMoveWasDraw)
        #expect(model.revealedCardIDs.isEmpty)
        // 配り直しの世代が上がらないと、同じ列に残った札のビューが使い回されて
        // その札だけ配札の演出が出ない（CodeRabbit 指摘・PR #433）。
        #expect(model.dealSerial == serial + 1)
    }

    @Test("配り直しの通し番号は、指しても戻しても増えない")
    func dealSerialOnlyChangesOnNewGame() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let serial = model.dealSerial
        for _ in 0..<3 { model.tapStock() }
        #expect(model.dealSerial == serial)
        model.undo()
        #expect(model.dealSerial == serial)
        // 増え続けると、1 手ごとに盤面のビューが丸ごと作り直されて移動の補間が消える。
        model.newGame()
        model.newGame()
        #expect(model.dealSerial == serial + 2)
    }

    @Test("中断から復元した局面では配札の演出を出さない")
    func resumedGameIsNotDealtAgain() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        for _ in 0..<3 { model.tapStock() }

        let (resumedServices, _) = makeServices(store: store)
        let resumed = SolitaireModel(services: resumedServices)
        #expect(!resumed.isFreshDeal)
        #expect(!resumed.lastMoveWasDraw)
        #expect(resumed.revealedCardIDs.isEmpty)
    }

    @Test("ジョーカーは所持していないと置けない（使い切ったあとは拒否される・#406）")
    func jokerNeedsPossession() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        // 初期所持の 1 枚を置き切ってから試す（#397 のジョーカー経済）。
        #expect(model.placeJoker(onPile: 0))
        #expect(!model.hasJoker)

        #expect(model.placeJoker(onPile: 1) == false)
        #expect(model.rejectedTapCount == 1)
    }
}

// MARK: - 自動で上がる

@Suite("自動で上がる")
@MainActor
struct SolitaireAutoFinishTests {

    /// 全札が表向きで、あとは組札へ積むだけの盤面。
    private func almostWonBoard() -> SolitaireBoard {
        var piles: [SolitairePile] = []
        for suit in SolitaireSuit.allCases {
            // 13 → 1 の降順に置く。組札へは A から送るので、複数回のパスが要る形になる。
            piles.append(SolitairePile(faceUp: (1...13).reversed().map { SolitaireCard(suit, $0) }))
        }
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        return SolitaireBoard(tableau: piles)
    }

    @Test("組札へ送るだけで勝てる盤面では手順が見つかる")
    func findsPlanWhenOnlyStackingRemains() {
        let plan = try! #require(SolitaireModel.autoFinishPlan(from: almostWonBoard()))
        var board = almostWonBoard()
        // #expect の中で mutating を呼ぶとマクロ展開側で immutable になるため、外で適用する。
        for move in plan {
            let applied = board.apply(move)
            #expect(applied)
        }
        #expect(board.isWon)
        #expect(plan.allSatisfy { $0 != .draw }, "この盤面に山札は無いのでめくる手は出ない")
    }

    @Test("山札に沈んだ札も、めくりだけで届くなら手順に含める")
    func drawsThroughTheStock() {
        var piles: [SolitairePile] = []
        for suit in SolitaireSuit.allCases {
            piles.append(SolitairePile(faceUp: (2...13).reversed().map { SolitaireCard(suit, $0) }))
        }
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        // A 4 枚だけを山札に沈める。
        let aces = SolitaireSuit.allCases.map { SolitaireCard($0, 1) }
        let board = SolitaireBoard(tableau: piles, stock: aces)
        let plan = try! #require(SolitaireModel.autoFinishPlan(from: board))
        #expect(plan.contains(.draw))
        var replayed = board
        for move in plan {
            let applied = replayed.apply(move)
            #expect(applied)
        }
        #expect(replayed.isWon)
    }

    @Test("積み替えが要る盤面では手順を返さない（代わりに解いてしまわない）")
    func refusesWhenReorderingIsNeeded() {
        // 伏せ札が残っている = 場札を動かさないと表に出ない。
        var piles = [SolitairePile(faceDown: [SolitaireCard(.spade, 1)], faceUp: [SolitaireCard(.heart, 2)])]
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        #expect(SolitaireModel.autoFinishPlan(from: SolitaireBoard(tableau: piles)) == nil)
    }

    @Test("勝ち済みの盤面には手順を出さない")
    func noPlanWhenAlreadyWon() {
        let won = SolitaireBoard(
            tableau: Array(repeating: SolitairePile(), count: SolitaireBoard.pileCount),
            foundations: [13, 13, 13, 13]
        )
        #expect(won.isWon)
        #expect(SolitaireModel.autoFinishPlan(from: won) == nil)
    }
}

// MARK: - 記録・中断

@Suite("ソリティアの記録と中断")
@MainActor
struct SolitaireRecordTests {

    @Test("勝ち筋を指し切るとクリアになり、タイムと手数が記録されて中断データが消える")
    func clearRecordsTimeAndMoves() {
        let store = MemorySnapshotStore()
        let log = makeLog(suite: "clear")
        let (services, spy) = makeServices(store: store, playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        let solution = try! #require(SolitaireSolver.solve(SolitaireDealer.deal(seed: fixedSeed)).solution)
        model.tick()   // 0 秒クリアにしない（順位表は 0 秒を送らない設計・#289）
        play(model, solution)

        #expect(model.phase == .won)
        #expect(model.board.isWon)
        #expect(spy.notices.contains(.success))
        #expect(!store.exists(for: "solitaire"), "決着した局の中断データは残さない")

        // クリア後も画面には組札と場札が残る。触っても「拒否」の振動・警告音を返さないこと
        // （決着後の操作は無音で無視する規約。`GoModel.tap` と同じ）。
        let rejectsBefore = model.rejectedTapCount
        model.tapFoundation(.spade)
        model.tapPile(0)
        model.tapStock()
        model.tapWaste()
        #expect(model.placeJoker(onPile: 0) == false)
        #expect(model.rejectedTapCount == rejectsBefore, "決着後のタップは拒否として数えない")

        let record = try! #require(log.record(gameID: "solitaire"))
        #expect(record.metric == .shortestTime)
        #expect(record.wins == 1)
        #expect(record.plays == 1)
        #expect(record.bestSeconds == 1)
        #expect(record.fewestMoves == model.moveCount)
    }

    @Test("1手でも指した盤面を捨てると、クリアできなかった局として記録される")
    func abandoningADealCountsAsALoss() {
        let log = makeLog(suite: "abandon")
        let (services, _) = makeServices(playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        model.tapStock()
        model.newGame()

        let record = try! #require(log.record(gameID: "solitaire"))
        #expect(record.plays == 1)
        #expect(record.losses == 1)
        #expect(record.wins == 0)
        #expect(record.bestSeconds == nil, "クリアしていない局のタイムは自己ベストに入れない")
    }

    @Test("配ったばかりの盤面を配り直しても記録しない")
    func redealingUntouchedBoardIsNotRecorded() {
        let log = makeLog(suite: "redeal")
        let (services, _) = makeServices(playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        model.newGame()

        #expect(log.record(gameID: "solitaire") == nil)
    }

    @Test("中断すると種と手順が保存され、復元すると同じ盤面・同じ経過秒に戻る")
    func restoresFromSnapshot() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        for _ in 0..<3 { model.tapStock() }
        for _ in 0..<7 { model.tick() }
        model.tick()   // 保存の間隔に乗せず、直近の手で保存済みの経過秒を確かめる

        #expect(store.exists(for: "solitaire"))
        let restored = SolitaireModel(services: services, seed: 999_999)
        #expect(restored.board == model.board, "種ではなく保存された配札が優先される")
        #expect(restored.canUndo)
    }

    @Test("配ったばかりの盤面は保存しない（ハブに「続きから」を出さない）")
    func untouchedBoardIsNotPersisted() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tick()
        #expect(!store.exists(for: "solitaire"))

        // 1 手指せば保存され、戻して配りたてに戻ると再び消える。
        model.tapStock()
        #expect(store.exists(for: "solitaire"))
        model.undo()
        #expect(!store.exists(for: "solitaire"))
    }

    @Test("計時は30秒ごとに保存し直す（長考のあとの終了でタイムが縮まない・#240）")
    func timerPersistsPeriodically() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tapStock()
        for _ in 0..<SolitaireModel.persistInterval { model.tick() }
        let snapshot = try! #require(store.load(SolitaireSnapshot.self, for: "solitaire"))
        #expect(snapshot.elapsedSeconds == SolitaireModel.persistInterval)
    }

    @Test("画面を離れると計時が止まり、直前までの経過秒が保存される（#375）")
    func pauseTimerStopsAndPersists() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tapStock()
        // 保存の間隔（30秒）に乗らない中途半端な経過秒で離脱する。実時間で待つとフレークするので
        // 計時は `tick()` を直接回して進める。
        for _ in 0..<5 { model.tick() }

        model.pauseTimer()

        let snapshot = try! #require(store.load(SolitaireSnapshot.self, for: "solitaire"))
        #expect(snapshot.elapsedSeconds == 5, "直近の保存から先の計時が失われない")
        #expect(model.elapsedSeconds == 5, "画面に戻ったときの経過秒も失われない")

        // 画面に戻れば計時が動き、また離れると止まる。
        model.resumeTimerIfNeeded()
        #expect(model.isCounting)
        model.pauseTimer()
        #expect(!model.isCounting, "画面を離れたら計時の Task は残らない")
    }
}

// MARK: - 「戻す」の回数制（#476）

/// 回数制が無かった版の中断データ（`undosRemaining` を持たない）。
private struct PreUndoBudgetSnapshot: Codable {
    let seed: UInt64
    let moves: [SolitaireMove]
    let elapsedSeconds: Int
    let jokerGrants: Int
}

@Suite("ソリティアの「戻す」の回数制")
@MainActor
struct SolitaireUndoBudgetTests {

    /// 山めくりだけで手順を積む（配札に依存せず、必ず戻せる手を作れる）。
    private func stack(_ model: SolitaireModel, moves count: Int) {
        for _ in 0..<count { model.tapStock() }
    }

    @Test("配った時点で無料の回数を持っている")
    func startsWithFreeBudget() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(model.undosRemaining == SolitaireUndoBudget.free)
        #expect(!model.needsUndoRefill, "戻せる手が無いうちは広告を提案しない")
    }

    @Test("無料の回数を使い切ると、次の「戻す」は広告の提案になり、視聴完了で補充される")
    func exhaustsThenRefills() {
        let (services, spy) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        stack(model, moves: SolitaireUndoBudget.free + 1)

        for remaining in stride(from: SolitaireUndoBudget.free, to: 0, by: -1) {
            #expect(model.undosRemaining == remaining)
            #expect(model.undo())
        }
        #expect(model.undosRemaining == 0)

        // 4 回目。戻せる手は残っているので、押した先は広告の提案（View がアラートを出す）。
        let board = model.board
        #expect(model.canUndo)
        #expect(model.needsUndoRefill)
        #expect(!model.undo(), "残り 0 のまま黙って戻さない")
        #expect(model.board == board)
        #expect(model.undosRemaining == 0)
        #expect(spy.notices.contains(.warning), "拒否として扱う")

        // 視聴完了後の補充。
        #expect(model.grantUndos(forDeal: model.dealSerial))
        #expect(model.undosRemaining == SolitaireUndoBudget.refill)
        #expect(!model.needsUndoRefill)
        #expect(model.undo())
    }

    @Test("広告を見なければ補充されない（補充は視聴完了後の grantUndos だけが行う）")
    func nothingRefillsWithoutTheReward() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        stack(model, moves: SolitaireUndoBudget.free + 2)
        for _ in 0..<SolitaireUndoBudget.free { #expect(model.undo()) }

        // View は `showRewardedAd()` が true を返したときだけ `grantUndos()` を呼ぶ。
        // 視聴をやめた（false）経路ではこの関数が呼ばれないので、押し直しても 0 のまま。
        for _ in 0..<3 {
            #expect(!model.undo())
            #expect(model.undosRemaining == 0)
        }
    }

    @Test("残り回数は中断データに残り、再開しても増えも減りもしない")
    func budgetSurvivesSuspend() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        stack(model, moves: SolitaireUndoBudget.free + 1)
        #expect(model.undo())
        #expect(model.undo())
        let expected = SolitaireUndoBudget.free - 2

        let snapshot = try! #require(store.load(SolitaireSnapshot.self, for: "solitaire"))
        #expect(snapshot.undosRemaining == expected)

        let resumed = SolitaireModel(services: services, seed: 999_999)
        #expect(resumed.undosRemaining == expected)
        #expect(resumed.board == model.board)

        // 補充したぶんも持ち越す（広告を見た事実が再起動で消えない）。
        #expect(resumed.grantUndos(forDeal: resumed.dealSerial))
        let after = SolitaireModel(services: services, seed: 999_999)
        #expect(after.undosRemaining == expected + SolitaireUndoBudget.refill)
    }

    @Test("回数制が無かった版の中断データは、無料枠が丸ごと残っている扱いで読む")
    func legacySnapshotGetsTheFullBudget() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        try! store.save(
            PreUndoBudgetSnapshot(seed: fixedSeed, moves: [.draw, .draw], elapsedSeconds: 12, jokerGrants: 1),
            for: "solitaire"
        )
        let model = SolitaireModel(services: services, seed: 999_999)
        #expect(model.undosRemaining == SolitaireUndoBudget.free)
        #expect(model.elapsedSeconds == 12, "同じ中断データから復元できている")
    }

    @Test("配り直すと無料の回数に戻る")
    func newGameResetsTheBudget() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        stack(model, moves: SolitaireUndoBudget.free)
        for _ in 0..<SolitaireUndoBudget.free { #expect(model.undo()) }
        #expect(model.undosRemaining == 0)

        model.newGame()
        #expect(model.undosRemaining == SolitaireUndoBudget.free)
    }

    @Test("広告を見ているあいだに配り直されたら、その補充は新しい局に乗らない")
    func refillIsDroppedWhenTheDealChanged() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        stack(model, moves: SolitaireUndoBudget.free)
        for _ in 0..<SolitaireUndoBudget.free { #expect(model.undo()) }

        // View が広告を出す前に控える値。この間に配り直しが起きうる（救済の告知の
        // 「新しい配札にする」・ツールバーの「新規ゲーム」の両方が入口になる）。
        let deal = model.dealSerial
        model.newGame()

        // 足してしまうと配り直した局が「無料3 + 補充3 = 6」から始まり、仕様1 が破れる。
        #expect(!model.grantUndos(forDeal: deal))
        #expect(model.undosRemaining == SolitaireUndoBudget.free)

        // 同じ局に対する補充なら通る（ガードが常に false を返しているのではない）。
        #expect(model.grantUndos(forDeal: model.dealSerial))
        #expect(model.undosRemaining == SolitaireUndoBudget.free + SolitaireUndoBudget.refill)
    }

    @Test("ジョーカーを置いた手を戻すのも消費は1回（#476 仕様5）")
    func undoingAJokerCostsOne() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(model.placeJoker(onPile: 0))
        #expect(!model.hasJoker)

        #expect(model.undo())
        #expect(model.undosRemaining == SolitaireUndoBudget.free - 1)
        #expect(model.hasJoker, "巻き戻せば所持に返る（#397 吟味2）")
    }

    @Test("決着したあとは補充しても使い道が無いので受け付けない")
    func grantIsRejectedAfterTheGameEnds() {
        let store = MemorySnapshotStore()
        let log = makeLog(suite: "undo-budget")
        let (services, _) = makeServices(store: store, playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let solution = try! #require(SolitaireSolver.solve(SolitaireDealer.deal(seed: fixedSeed)).solution)
        play(model, solution)

        #expect(model.phase == .won)
        #expect(!model.grantUndos(forDeal: model.dealSerial))
    }

    @Test("読み上げ文は残り回数と、使い切ったあとの補充手段を伝える")
    func accessibilityReadsTheBudget() {
        #expect(SolitaireAccessibility.undoButtonLabel(remaining: 2) == "1手戻す、残り2回")
        #expect(SolitaireAccessibility.undoButtonLabel(remaining: 0) == "1手戻す、残りなし")
        #expect(SolitaireAccessibility.undoButtonHint(canUndo: false, remaining: 3)
                == "まだ戻せる手がありません")
        #expect(SolitaireAccessibility.undoButtonHint(canUndo: true, remaining: 0)
                .contains("広告を見ると\(SolitaireUndoBudget.refill)回"))
        #expect(SolitaireAccessibility.undoButtonHint(canUndo: true, remaining: 1)
                .contains("\(SolitaireUndoBudget.free)回まで"))
    }
}

// MARK: - 寸法

@Suite("ソリティアの盤面寸法")
struct SolitaireMetricsTests {

    @Test("どの画面幅でも 7 列が収まる", arguments: [320.0, 375.0, 393.0, 430.0, 744.0, 1024.0])
    func sevenColumnsFit(width: Double) {
        let available = CGFloat(width)
        let card = SolitaireMetrics.cardWidth(availableWidth: available)
        let total = card * CGFloat(SolitaireBoard.pileCount)
            + SolitaireMetrics.columnGap * CGFloat(SolitaireBoard.pileCount - 1)
        // 上限に張り付く広い画面だけは余る（間延びさせないための頭打ち）。それ以外ははみ出さない。
        #expect(total <= available || card == SolitaireMetrics.maxCardWidth)
        #expect(card >= SolitaireMetrics.minCardWidth)
    }

    @Test("列の高さは伏せ札と表向き札の段差ぶんだけ伸びる")
    func pileHeightGrows() {
        let height = SolitaireMetrics.cardHeight(width: 46)
        let one = SolitaireMetrics.pileHeight(faceDownCount: 0, faceUpCount: 1, cardHeight: height)
        let stacked = SolitaireMetrics.pileHeight(faceDownCount: 6, faceUpCount: 4, cardHeight: height)
        #expect(one == height)
        #expect(stacked > one)
        #expect(stacked == height
                + 6 * SolitaireMetrics.faceDownStep(cardHeight: height)
                + 3 * SolitaireMetrics.faceUpStep(cardHeight: height))
    }
}

// MARK: - 遊び方シート

@Suite("ソリティアのルールシート")
struct SolitaireRuleSheetTests {

    @Test("クロンダイクの要点（空列は K・山札の循環・戻すの回数制）が抜けていない")
    func coversTheEssentials() {
        let text = SolitaireRuleSheet.rules.map { $0.0 + $0.1 }.joined()
        #expect(text.contains("K だけ"))
        #expect(text.contains("捨て札が山札に戻ります"))
        // 回数制（#476）。無料の回数と、使い切ったあとの補充手段の両方を書く。
        #expect(text.contains("1局につき\(SolitaireUndoBudget.free)回まで無料"))
        #expect(text.contains("広告を見ると\(SolitaireUndoBudget.refill)回ぶん補充"))
        #expect(text.contains("クリアできることを確かめて"))
    }
}
