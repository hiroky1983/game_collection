import Testing
import Foundation
import Core
@testable import GameFreeCell

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

@Suite("フリーセルのモデル")
@MainActor
struct FreeCellModelTests {

    private func firstSeed() -> UInt64 { FreeCellDealer.verifiedSeeds[0] }

    // MARK: - 操作

    @Test("札をタップして選び、置き先をタップすると動く")
    func tapToMove() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        // 一番上の札を空きセルへ入れる（どの配札でも必ず通る手）。
        model.tapPile(0)
        #expect(model.selection == .tableau(pile: 0, cardIndex: model.board.tableau[0].count - 1))
        let moved = model.board.tableau[0].last
        model.tapCell(0)
        #expect(model.selection == nil)
        #expect(model.board.cells[0] == moved)
        #expect(model.moveCount == 1)
    }

    @Test("同じ札をもう一度タップすると選択が外れる")
    func tapTwiceDeselects() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        model.tapPile(0)
        #expect(model.selection != nil)
        model.tapPile(0)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
    }

    @Test("動かせない並びは選べず、拒否として数える")
    func rejectsUnmovableRun() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        // 6 枚以上ある列の一番下は、まず並びになっていない（なっていたら別の列で試す）。
        guard let pile = model.board.tableau.indices.first(where: {
            !model.board.isOrderedRun(pile: $0, from: 0)
        }) else { return }
        let before = model.rejectedTapCount
        model.tapPile(pile, cardIndex: 0)
        #expect(model.selection == nil)
        #expect(model.rejectedTapCount == before + 1)
    }

    @Test("空のセルを先に触っても何も起きない")
    func tappingEmptyCellWithoutSelectionIsRejected() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        let before = model.rejectedTapCount
        model.tapCell(0)
        #expect(model.selection == nil)
        #expect(model.rejectedTapCount == before + 1)
    }

    @Test("組札は選択中の札のスートと違うところをタップしても送らない")
    func foundationRejectsWrongSuit() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        // A が一番上に来ている列を探す（無ければこのテストは対象外）。
        guard let pile = model.board.tableau.indices.first(where: {
            model.board.tableau[$0].last?.rank == 1
        }) else { return }
        let ace = model.board.tableau[pile].last!
        model.tapPile(pile)
        let wrongSuit = PlayingCardSuit.allCases.first { $0 != ace.suit }!
        model.tapFoundation(wrongSuit)
        #expect(model.board.foundations[wrongSuit.rawValue] == 0)
        #expect(model.moveCount == 0)
        // 正しいスートなら通る。
        model.tapFoundation(ace.suit)
        #expect(model.board.foundations[ace.suit.rawValue] == 1)
    }

    // MARK: - 戻す（#476 と同じ経済）

    @Test("無料の「戻す」は3回まで")
    func undoIsFreeThreeTimes() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        #expect(model.undosRemaining == FreeCellUndoBudget.free)
        // 無料枠より 1 手多く指す（使い切ったあとも「戻せる手はある」状態を作るため）。
        for cell in 0..<FreeCellBoard.cellCount {
            model.tapPile(cell)
            model.tapCell(cell)
        }
        #expect(model.moveCount == FreeCellBoard.cellCount)

        for remaining in stride(from: FreeCellUndoBudget.free - 1, through: 0, by: -1) {
            #expect(model.undo())
            #expect(model.undosRemaining == remaining)
        }
        // 4 回目は戻せない（戻せる手はまだ残っている）。
        #expect(model.canUndo)
        #expect(!model.undo())
        #expect(model.needsUndoRefill)
    }

    @Test("広告の視聴完了で3回ぶん補充する")
    func rewardedRefill() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        for cell in 0..<3 { model.tapPile(cell); model.tapCell(cell) }
        for _ in 0..<FreeCellUndoBudget.free { model.undo() }
        #expect(model.undosRemaining == 0)
        #expect(model.grantUndos(forDeal: model.dealSerial))
        #expect(model.undosRemaining == FreeCellUndoBudget.refill)
    }

    /// 広告のロード〜視聴の間に配り直されたら補充しない（PR #480 の敵対的検証で見つかった型）。
    @Test("広告の視聴中に配り直されたら補充しない")
    func refillIsScopedToTheDeal() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        model.tapPile(0); model.tapCell(0)
        let deal = model.dealSerial
        model.newGame()
        #expect(!model.grantUndos(forDeal: deal))
        #expect(model.undosRemaining == FreeCellUndoBudget.free)
    }

    @Test("戻すと盤面も手数も1手ぶん戻る")
    func undoRestoresTheBoard() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        let before = model.board
        model.tapPile(0); model.tapCell(0)
        #expect(model.board != before)
        #expect(model.undo())
        #expect(model.board == before)
        #expect(model.moveCount == 0)
        #expect(!model.canUndo)
    }

    @Test("配り直すと「戻す」の残りが無料枠に戻る")
    func newGameResetsTheBudget() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        model.tapPile(0); model.tapCell(0)
        model.undo()
        #expect(model.undosRemaining == FreeCellUndoBudget.free - 1)
        model.newGame()
        #expect(model.undosRemaining == FreeCellUndoBudget.free)
        #expect(model.moveCount == 0)
    }

    // MARK: - 中断復元（契約: 種 + 手順）

    @Test("中断データは種と手順で復元される")
    func snapshotRoundTrip() {
        let store = MemorySnapshotStore()
        let services = makeServices(store: store)
        let model = FreeCellModel(services: services, seed: firstSeed())
        for cell in 0..<3 { model.tapPile(cell); model.tapCell(cell) }
        model.undo()
        model.tick()
        // 計時は 30 秒ごとにしか保存し直さないので、画面を離れる経路で書き出してから読み直す。
        model.pauseTimer()

        let restored = FreeCellModel(services: makeServices(store: store))
        #expect(restored.dealNumber == model.dealNumber)
        #expect(restored.board == model.board)
        #expect(restored.moveCount == model.moveCount)
        #expect(restored.elapsedSeconds == model.elapsedSeconds)
        #expect(restored.undosRemaining == model.undosRemaining)
    }

    @Test("配ったばかりの盤面は中断データを残さない")
    func freshDealIsNotPersisted() {
        let store = MemorySnapshotStore()
        _ = FreeCellModel(services: makeServices(store: store), seed: firstSeed())
        #expect(store.isEmpty)
    }

    /// 壊れた中断データは**適用できたところで打ち切る**。読み飛ばすと以降の手順が
    /// 1 手ずつずれた別の盤面になる（#406 申し送り2）。
    @Test("壊れた中断データは適用できたところで打ち切る")
    func brokenSnapshotIsTruncated() throws {
        let store = MemorySnapshotStore()
        let seed = firstSeed()
        // 1 手目は通る手、2 手目は必ず通らない手（範囲外の列）。
        let moves: [FreeCellMove] = [
            .tableauToCell(from: 0, cell: 0),
            .tableauToCell(from: 99, cell: 1),
            .tableauToCell(from: 1, cell: 1),
        ]
        try store.save(FreeCellSnapshot(seed: seed, moves: moves,
                                        elapsedSeconds: 12, undosRemaining: 2), for: "freecell")
        let model = FreeCellModel(services: makeServices(store: store))
        #expect(model.moveCount == 1)
        var expected = FreeCellDealer.deal(seed: seed)
        expected.apply(.tableauToCell(from: 0, cell: 0))
        #expect(model.board == expected)
    }

    @Test("回数の欄が欠けた中断データは無料枠が残っている扱いにする")
    func snapshotWithoutBudgetFallsBackToFree() throws {
        let store = MemorySnapshotStore()
        let seed = firstSeed()
        try store.save(FreeCellSnapshot(seed: seed, moves: [.tableauToCell(from: 0, cell: 0)],
                                        elapsedSeconds: 5, undosRemaining: nil), for: "freecell")
        let model = FreeCellModel(services: makeServices(store: store))
        #expect(model.undosRemaining == FreeCellUndoBudget.free)
    }

    @Test("負の残り回数・経過秒は 0 に丸める")
    func snapshotClampsNegativeValues() throws {
        let store = MemorySnapshotStore()
        try store.save(FreeCellSnapshot(seed: firstSeed(), moves: [.tableauToCell(from: 0, cell: 0)],
                                        elapsedSeconds: -30, undosRemaining: -5), for: "freecell")
        let model = FreeCellModel(services: makeServices(store: store))
        #expect(model.undosRemaining == 0)
        #expect(model.elapsedSeconds == 0)
    }

    // MARK: - 決着

    @Test("勝ち筋を指し切るとクリアになり、中断データが消える")
    func winningClearsTheSnapshot() {
        let store = MemorySnapshotStore()
        let seed = firstSeed()
        let model = FreeCellModel(services: makeServices(store: store), seed: seed)
        guard let solution = FreeCellSolver.solve(FreeCellDealer.deal(seed: seed)).solution else {
            Issue.record("勝ち筋が見つからなかった")
            return
        }
        playFreeCellSolution(model, solution)
        #expect(model.phase == .won)
        #expect(model.board.isWon)
        #expect(store.isEmpty)
        #expect(!model.isCounting)
    }

    @Test("あとは積むだけの局面で「自動で上がる」が出る")
    func autoFinish() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        #expect(!model.canAutoFinish)

        // 4 スートの A〜Q を組札へ積み終え、K だけ場に残っている局面を作る。
        var tableau: [[FreeCellCard]] = Array(repeating: [], count: FreeCellBoard.pileCount)
        for (index, suit) in PlayingCardSuit.allCases.enumerated() {
            tableau[index] = [FreeCellCard(suit, 13)]
        }
        model.replaceBoardForTesting(FreeCellBoard(tableau: tableau, foundations: [12, 12, 12, 12]))
        #expect(model.canAutoFinish)
        #expect(model.autoFinish())
        #expect(model.phase == .won)
    }

    // MARK: - 行き止まり

    @Test("合法手が尽きると告知が出て、閉じると配り直すまで出ない")
    func deadEndPrompt() {
        let model = FreeCellModel(services: makeServices(), seed: firstSeed())
        #expect(!model.showsDeadEndPrompt)

        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        model.replaceBoardForTesting(FreeCellBoard(
            tableau: tableau, cells: PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }))
        #expect(model.isDeadEnd)
        #expect(model.showsDeadEndPrompt)

        model.dismissDeadEndPrompt()
        #expect(model.isDeadEnd)          // 状態そのものは残る（ステータスバーの 😵 のため）
        #expect(!model.showsDeadEndPrompt)

        model.newGame()
        #expect(!model.isDeadEnd)
        #expect(!model.showsDeadEndPrompt)
    }

    // MARK: - 計時

    @Test("計時は 30 秒ごとに中断データを保存し直す")
    func periodicPersist() {
        let store = MemorySnapshotStore()
        let model = FreeCellModel(services: makeServices(store: store), seed: firstSeed())
        model.tapPile(0); model.tapCell(0)
        for _ in 0..<FreeCellModel.persistInterval { model.tick() }
        let restored = FreeCellModel(services: makeServices(store: store))
        #expect(restored.elapsedSeconds == FreeCellModel.persistInterval)
    }

    @Test("画面を離れると計時が止まり、そこまでの経過が保存される")
    func pauseTimerPersists() {
        let store = MemorySnapshotStore()
        let model = FreeCellModel(services: makeServices(store: store), seed: firstSeed())
        model.tapPile(0); model.tapCell(0)
        model.tick()
        model.pauseTimer()
        #expect(!model.isCounting)
        let restored = FreeCellModel(services: makeServices(store: store))
        #expect(restored.elapsedSeconds == 1)
    }
}

/// ソルバーの勝ち筋を、**View と同じタップ操作に翻訳して**指す。
///
/// 直接 `FreeCellBoard.apply` を呼ばずタップ経路を通すのは、選択 → 置き先という 2 段の
/// 操作そのものを 1 局ぶん通しで検証するため（View を組まずに触れるのはここが唯一の面）。
/// ソリティアの `SolitaireModelTests` と同じ方針。
@MainActor
private func playFreeCellSolution(_ model: FreeCellModel, _ solution: [FreeCellMove]) {
    for move in solution {
        switch move {
        case .tableauToCell(let from, let cell):
            model.tapPile(from)
            model.tapCell(cell)
        case .tableauToFoundation(let pile):
            guard let suit = model.board.tableau[pile].last?.suit else { return }
            model.tapPile(pile)
            model.tapFoundation(suit)
        case .tableauToTableau(let from, let cardIndex, let to):
            model.tapPile(from, cardIndex: cardIndex)
            model.tapPile(to)
        case .cellToTableau(let cell, let to):
            model.tapCell(cell)
            model.tapPile(to)
        case .cellToFoundation(let cell):
            guard let suit = model.board.cells[cell]?.suit else { return }
            model.tapCell(cell)
            model.tapFoundation(suit)
        }
    }
}
