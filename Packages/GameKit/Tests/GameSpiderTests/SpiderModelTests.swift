import Testing
import Foundation
import Core
@testable import GameSpider

/// 中断データの保存先。書いた中身をそのまま読み返せる最小の実装。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        storage[gameID] = try JSONEncoder().encode(snapshot)
    }

    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = storage[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(for gameID: String) { storage.removeValue(forKey: gameID) }

    func exists(for gameID: String) -> Bool { storage[gameID] != nil }

    var isEmpty: Bool { storage.isEmpty }
}

@MainActor
private func makeServices(store: SnapshotStore = MemorySnapshotStore()) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

@MainActor
private func card(_ suit: SpiderSuit, _ rank: Int, id: Int) -> SpiderCard {
    SpiderCard(id: id, suit: suit, rank: rank)
}

@Suite("スパイダーのモデル")
@MainActor
struct SpiderModelTests {

    private func firstSeed(_ suits: SpiderSuitCount = .one) -> UInt64 { SpiderDealer.verifiedSeeds(for: suits)[0] }

    /// どの配札でも必ず通る 1 手（合法手の先頭）をタップ操作で指す。
    private func playFirstLegalMove(_ model: SpiderModel) -> SpiderMove? {
        guard let move = model.board.legalMoves.first(where: { if case .move = $0 { return true } else { return false } }),
              case .move(let from, let cardIndex, let to) = move else { return nil }
        model.tapPile(from, cardIndex: cardIndex)
        model.tapPile(to)
        return move
    }

    // MARK: - 操作

    @Test("札をタップして選び、置き先をタップすると動く")
    func tapToMove() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        let before = model.board
        guard let move = playFirstLegalMove(model), case .move(let from, let cardIndex, let to) = move else {
            Issue.record("最初の局面に合法手が無い")
            return
        }
        var expected = before
        expected.apply(.move(from: from, cardIndex: cardIndex, to: to))
        #expect(model.board == expected)
        #expect(model.selection == nil)
        #expect(model.moveCount == 1)
    }

    @Test("同じ札をもう一度タップすると選択が外れる")
    func tapTwiceDeselects() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        model.tapPile(0)
        #expect(model.selection == SpiderSelection(pile: 0, cardIndex: model.board.piles[0].cards.count - 1))
        model.tapPile(0)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
    }

    @Test("伏せ札は選べず、拒否として数える")
    func rejectsFaceDownCard() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        let before = model.rejectedTapCount
        model.tapPile(0, cardIndex: 0)
        #expect(model.selection == nil)
        #expect(model.rejectedTapCount == before + 1)
    }

    @Test("置けない列をタップすると拒否され、選択は解除される")
    func rejectsIllegalDestination() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        // 一番上どうしでランクが 1 つ大きくない組を探す。
        guard let (from, to) = pairThatCannotMove(model.board) else { return }
        model.tapPile(from)
        let before = model.rejectedTapCount
        model.tapPile(to)
        #expect(model.rejectedTapCount == before + 1)
        #expect(model.moveCount == 0)
    }

    private func pairThatCannotMove(_ board: SpiderBoard) -> (Int, Int)? {
        for from in board.piles.indices {
            for to in board.piles.indices where from != to {
                if !board.isLegal(.move(from: from, cardIndex: board.piles[from].cards.count - 1, to: to)) {
                    return (from, to)
                }
            }
        }
        return nil
    }

    @Test("山札をタップすると各列に 1 枚ずつ配られ、手数に数える")
    func tapStockDeals() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        let counts = model.board.piles.map { $0.cards.count }
        model.tapStock()
        #expect(model.board.dealsRemaining == 4)
        #expect(model.board.piles.map { $0.cards.count } == counts.map { $0 + 1 })
        #expect(model.moveCount == 1)
        #expect(model.lastDealtCardIDs.count == 10, "配った札は演出のために控える")
        // 次の 1 手で控えは消える。
        _ = playFirstLegalMove(model)
        #expect(model.lastDealtCardIDs.isEmpty)
    }

    @Test("空いた列があると配れず、その理由の回数が増える")
    func dealBlockedByEmptyPile() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        var piles = (0..<10).map { SpiderPile(cards: [card(.spade, 5, id: $0)]) }
        piles[2] = SpiderPile(cards: [])
        model.replaceBoardForTesting(SpiderBoard(
            piles: piles, stock: [(0..<10).map { card(.spade, 9, id: 20 + $0) }]))
        let blocked = model.dealBlockedCount
        let rejected = model.rejectedTapCount
        model.tapStock()
        #expect(model.dealBlockedCount == blocked + 1)
        #expect(model.rejectedTapCount == rejected + 1)
        #expect(model.board.dealsRemaining == 1)
    }

    // MARK: - 戻す（#476 と同じ経済）

    @Test("無料の「戻す」は 3 回まで")
    func undoIsFreeThreeTimes() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        #expect(model.undosRemaining == SpiderUndoBudget.free)
        // 無料枠より 1 手多く指す（配りは常に指せる）。
        for _ in 0...SpiderUndoBudget.free { model.tapStock() }
        #expect(model.moveCount == SpiderUndoBudget.free + 1)

        for remaining in stride(from: SpiderUndoBudget.free - 1, through: 0, by: -1) {
            #expect(model.undo())
            #expect(model.undosRemaining == remaining)
        }
        #expect(model.canUndo)
        #expect(!model.undo())
        #expect(model.needsUndoRefill)
    }

    @Test("広告の視聴完了で 3 回ぶん補充する")
    func rewardedRefill() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        for _ in 0..<3 { model.tapStock() }
        for _ in 0..<SpiderUndoBudget.free { model.undo() }
        #expect(model.undosRemaining == 0)
        #expect(model.grantUndos(forDeal: model.dealSerial))
        #expect(model.undosRemaining == SpiderUndoBudget.refill)
    }

    @Test("広告の視聴中に配り直されたら補充しない")
    func refillIsScopedToTheDeal() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        model.tapStock()
        let deal = model.dealSerial
        model.newGame()
        #expect(!model.grantUndos(forDeal: deal))
        #expect(model.undosRemaining == SpiderUndoBudget.free)
    }

    @Test("戻すと盤面も手数も 1 手ぶん戻る")
    func undoRestoresTheBoard() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        let before = model.board
        model.tapStock()
        #expect(model.board != before)
        #expect(model.undo())
        #expect(model.board == before)
        #expect(model.moveCount == 0)
        #expect(!model.canUndo)
    }

    // MARK: - ルールの焼き込み（1局=1RuleSet）

    @Test("配り直しでスート数を変えられ、省略すると今のルールのまま")
    func newGameBakesRules() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        #expect(model.rules == .standard)
        model.newGame(rules: SpiderRuleSet(suitCount: .four))
        #expect(model.rules.suitCount == .four)
        #expect(Set(model.board.piles.flatMap(\.cards).map(\.suit)).count == 4)
        model.newGame()
        #expect(model.rules.suitCount == .four)
        #expect(SpiderDealer.verifiedSeeds(for: .four).contains(model.dealNumber))
    }

    @Test("記録はスート数ごとの区分で残り、順位表の対応表と一致する")
    func recordVariantsMatchLeaderboards() {
        for suits in SpiderSuitCount.allCases {
            let score = GameScore(metric: .shortestTime, seconds: 10, variant: suits.recordVariant)
            let id = GameCenterLeaderboard.score(gameID: "spider", outcome: .win, score: score)?.leaderboardID
            #expect(id != nil, "\(suits) の区分キー \(suits.recordVariant) が順位表に対応していない")
        }
        let ids = SpiderSuitCount.allCases.compactMap {
            GameCenterLeaderboard.score(
                gameID: "spider", outcome: .win,
                score: GameScore(metric: .shortestTime, seconds: 10, variant: $0.recordVariant)
            )?.leaderboardID
        }
        #expect(Set(ids).count == 3, "3 難度は別々の表に送る")
    }

    // MARK: - 中断復元（契約: 種 + スート数 + 手順）

    @Test("中断データは種・スート数・手順で復元される")
    func snapshotRoundTrip() {
        let store = MemorySnapshotStore()
        let services = makeServices(store: store)
        let model = SpiderModel(services: services, seed: firstSeed(.two), rules: SpiderRuleSet(suitCount: .two))
        model.tapStock()
        _ = playFirstLegalMove(model)
        model.tapStock()
        model.undo()
        model.tick()
        model.pauseTimer()

        let restored = SpiderModel(services: makeServices(store: store))
        #expect(restored.rules.suitCount == .two)
        #expect(restored.dealNumber == model.dealNumber)
        #expect(restored.board == model.board)
        #expect(restored.moveCount == model.moveCount)
        #expect(restored.elapsedSeconds == model.elapsedSeconds)
        #expect(restored.undosRemaining == model.undosRemaining)
    }

    @Test("配ったばかりの盤面は中断データを残さない")
    func freshDealIsNotPersisted() {
        let store = MemorySnapshotStore()
        _ = SpiderModel(services: makeServices(store: store), seed: firstSeed())
        #expect(store.isEmpty)
    }

    @Test("壊れた中断データは適用できたところで打ち切る")
    func brokenSnapshotIsTruncated() throws {
        let store = MemorySnapshotStore()
        let seed = firstSeed()
        let moves: [SpiderMove] = [.deal, .move(from: 99, cardIndex: 0, to: 1), .deal]
        try store.save(SpiderSnapshot(seed: seed, suitCount: 1, moves: moves,
                                      elapsedSeconds: 12, undosRemaining: 2), for: "spider")
        let model = SpiderModel(services: makeServices(store: store))
        #expect(model.moveCount == 1)
        var expected = SpiderDealer.deal(seed: seed, suits: .one)
        expected.apply(.deal)
        #expect(model.board == expected)
    }

    @Test("スート数が読めない中断データは捨てて新しく配る")
    func snapshotWithUnknownSuitCountIsIgnored() throws {
        let store = MemorySnapshotStore()
        try store.save(SpiderSnapshot(seed: 7, suitCount: 3, moves: [.deal],
                                      elapsedSeconds: 12, undosRemaining: 2), for: "spider")
        let model = SpiderModel(services: makeServices(store: store))
        #expect(model.moveCount == 0)
        #expect(model.rules == .standard)
    }

    @Test("回数の欄が欠けた中断データは無料枠が残っている扱いにし、負の値は 0 に丸める")
    func snapshotFallbacks() throws {
        let store = MemorySnapshotStore()
        try store.save(SpiderSnapshot(seed: firstSeed(), suitCount: 1, moves: [.deal],
                                      elapsedSeconds: 5, undosRemaining: nil), for: "spider")
        #expect(SpiderModel(services: makeServices(store: store)).undosRemaining == SpiderUndoBudget.free)

        try store.save(SpiderSnapshot(seed: firstSeed(), suitCount: 1, moves: [.deal],
                                      elapsedSeconds: -30, undosRemaining: -5), for: "spider")
        let model = SpiderModel(services: makeServices(store: store))
        #expect(model.undosRemaining == 0)
        #expect(model.elapsedSeconds == 0)
    }

    // MARK: - 決着

    @Test("勝ち筋を指し切るとクリアになり、中断データが消える")
    func winningClearsTheSnapshot() {
        let store = MemorySnapshotStore()
        let seed = firstSeed()
        let model = SpiderModel(services: makeServices(store: store), seed: seed)
        guard let solution = SpiderSolver.solve(
            SpiderDealer.deal(seed: seed, suits: .one),
            maxStates: SpiderSolver.defaultMaxStates(for: .one)).solution else {
            Issue.record("勝ち筋が見つからなかった")
            return
        }
        playSpiderSolution(model, solution)
        #expect(model.phase == .won)
        #expect(model.board.isWon)
        #expect(store.isEmpty)
        #expect(!model.isCounting)
    }

    @Test("組が完成すると場から消え、8 組でクリアになる")
    func completingSequences() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        var piles = (0..<10).map { SpiderPile(cards: [card(.spade, 5, id: $0)]) }
        piles[0] = SpiderPile(cards: (2...13).reversed().enumerated().map { card(.spade, $1, id: 40 + $0) })
        piles[1] = SpiderPile(cards: [card(.spade, 1, id: 60)])
        model.replaceBoardForTesting(SpiderBoard(piles: piles, completed: Array(repeating: .spade, count: 7)))
        model.tapPile(1)
        model.tapPile(0)
        #expect(model.board.completed.count == 8)
        #expect(model.phase == .won)
    }

    // MARK: - 行き止まり

    @Test("合法手が尽きると告知が出て、閉じると配り直すまで出ない")
    func deadEndPrompt() {
        let model = SpiderModel(services: makeServices(), seed: firstSeed())
        #expect(!model.showsDeadEndPrompt)
        let kings = (0..<10).map { SpiderPile(cards: [card(.spade, 13, id: $0)]) }
        model.replaceBoardForTesting(SpiderBoard(piles: kings))
        #expect(model.isDeadEnd)
        #expect(model.showsDeadEndPrompt)

        model.dismissDeadEndPrompt()
        #expect(model.isDeadEnd)
        #expect(!model.showsDeadEndPrompt)

        model.newGame()
        #expect(!model.isDeadEnd)
        #expect(!model.showsDeadEndPrompt)
    }

    // MARK: - 計時

    @Test("計時は 30 秒ごとに中断データを保存し直す")
    func periodicPersist() {
        let store = MemorySnapshotStore()
        let model = SpiderModel(services: makeServices(store: store), seed: firstSeed())
        model.tapStock()
        for _ in 0..<SpiderModel.persistInterval { model.tick() }
        let restored = SpiderModel(services: makeServices(store: store))
        #expect(restored.elapsedSeconds == SpiderModel.persistInterval)
    }

    @Test("画面を離れると計時が止まり、そこまでの経過が保存される")
    func pauseTimerPersists() {
        let store = MemorySnapshotStore()
        let model = SpiderModel(services: makeServices(store: store), seed: firstSeed())
        model.tapStock()
        model.tick()
        model.pauseTimer()
        #expect(!model.isCounting)
        let restored = SpiderModel(services: makeServices(store: store))
        #expect(restored.elapsedSeconds == 1)
    }
}

/// ソルバーの勝ち筋を、**View と同じタップ操作に翻訳して**指す（フリーセルと同じ方針）。
@MainActor
func playSpiderSolution(_ model: SpiderModel, _ solution: [SpiderMove]) {
    for move in solution {
        switch move {
        case .move(let from, let cardIndex, let to):
            model.tapPile(from, cardIndex: cardIndex)
            model.tapPile(to)
        case .deal:
            model.tapStock()
        }
    }
}
