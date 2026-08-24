import Testing
import Foundation
import Core
@testable import GameSudoku

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    var savedCount = 0
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
        savedCount += 1
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

@MainActor
private func makeModel(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    seed: UInt64 = 2026
) -> (SudokuModel, MemorySnapshotStore) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (SudokuModel(services: services, seed: seed), store)
}

/// 盤を完成させる（正解をそのまま入れていく）。
@MainActor
private func solveAll(_ model: SudokuModel) {
    for index in 0..<81 where model.board[index] == 0 {
        // 同じマスをもう一度タップすると選択が外れるので、選び直しは必要なときだけ。
        if model.selected != index { model.select(index: index) }
        model.enter(digit: model.solution[index])
    }
}

@Suite("数独 Model の進行")
@MainActor
struct SudokuModelProgressTests {

    @Test("最初は出題が無く、新規ゲームで盤が出来る")
    func startsIdle() async {
        let (model, _) = makeModel()
        #expect(model.state == .idle)
        #expect(!model.hasPuzzle)

        await model.newGame(difficulty: .easy)
        #expect(model.state == .playing)
        #expect(model.hasPuzzle)
        #expect(model.difficulty == .easy)
        #expect(model.remainingCount > 0)
        #expect(model.given.filter { $0 }.count == 81 - model.remainingCount)
    }

    @Test("出題のマスには書き込めない")
    func givenCellsAreReadOnly() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let givenIndex = (0..<81).first { model.given[$0] }!
        let before = model.board[givenIndex]

        model.select(index: givenIndex)
        model.enter(digit: before == 9 ? 1 : 9)
        #expect(model.board[givenIndex] == before)
        #expect(!model.canEditSelection)
    }

    @Test("空きマスに数字を入れられ、消せる")
    func writesAndErases() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!

        model.select(index: blank)
        #expect(model.canEditSelection)
        model.enter(digit: model.solution[blank])
        #expect(model.board[blank] == model.solution[blank])

        model.erase()
        #expect(model.board[blank] == 0)
    }

    @Test("間違った数字は errorCells に出る")
    func wrongDigitIsMarked() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        let wrong = (1...9).first { $0 != model.solution[blank] }!

        model.select(index: blank)
        model.enter(digit: wrong)
        #expect(model.errorCells.contains(blank))

        model.enter(digit: model.solution[blank])
        #expect(!model.errorCells.contains(blank))
    }

    @Test("全部埋めるとクリアになり、記録が win で残る")
    func completingWins() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        solveAll(model)

        #expect(model.state == .cleared)
        #expect(model.isFinished)
        #expect(model.remainingCount == 0)
        // クリアしたら中断スナップショットは残さない（「続きから」に出てこない）。
        #expect(!store.exists(for: "sudoku"))
    }

    @Test("諦めると答えが出て、記録は loss として終わる")
    func givingUpRevealsSolution() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        model.giveUp()

        #expect(model.state == .givenUp)
        #expect(model.board == model.solution)
        #expect(!store.exists(for: "sudoku"))
    }

    @Test("終局後は選択も入力も効かない")
    func finishedBoardIsFrozen() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.giveUp()

        model.select(index: blank)
        #expect(model.selected == nil)
        model.enter(digit: 1)
        #expect(model.board == model.solution)
    }
}

@Suite("数独 Model のメモ")
@MainActor
struct SudokuModelNoteTests {

    @Test("メモモードでは数字が確定せずメモが付く")
    func notesToggle() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!

        model.select(index: blank)
        model.toggleNoteMode()
        #expect(model.noteMode)

        model.enter(digit: 4)
        #expect(model.board[blank] == 0)
        #expect(model.hasNote(4, at: blank))

        model.enter(digit: 4)
        #expect(!model.hasNote(4, at: blank), "もう一度押すと外れる")
    }

    @Test("正解を確定すると、同じ行・列・ブロックの同じ数字のメモが消える")
    func correctEntryClearsPeerNotes() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        let digit = model.solution[blank]
        let peer = SudokuEngine.peers(of: blank).first { model.board[$0] == 0 && $0 != blank }!

        model.select(index: peer)
        model.toggleNoteMode()
        model.enter(digit: digit)
        #expect(model.hasNote(digit, at: peer))

        model.toggleNoteMode()
        model.select(index: blank)
        model.enter(digit: digit)
        #expect(!model.hasNote(digit, at: peer), "確定した数字のメモは巻き取られる")
    }

    @Test("間違った数字を入れてもメモは巻き取られない")
    func wrongEntryKeepsPeerNotes() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        let wrong = (1...9).first { $0 != model.solution[blank] }!
        let peer = SudokuEngine.peers(of: blank).first { model.board[$0] == 0 && $0 != blank }!

        model.select(index: peer)
        model.toggleNoteMode()
        model.enter(digit: wrong)
        model.toggleNoteMode()

        model.select(index: blank)
        model.enter(digit: wrong)
        #expect(model.hasNote(wrong, at: peer), "間違いで正しいメモを消してはいけない")
    }
}

@Suite("数独 Model のヒント")
@MainActor
struct SudokuModelHintTests {

    @Test("ヒントは選択マスを正解で埋め、3回で打ち止め")
    func hintsAreLimited() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        #expect(model.remainingHints == SudokuModel.maxHints)

        var used = 0
        for index in 0..<81 where model.board[index] == 0 && used < SudokuModel.maxHints {
            model.select(index: index)
            #expect(model.canHint)
            #expect(model.applyHint(at: index))
            #expect(model.board[index] == model.solution[index])
            #expect(model.hintedCells.contains(index))
            used += 1
        }
        #expect(model.hintsUsed == SudokuModel.maxHints)
        #expect(model.remainingHints == 0)

        let nextBlank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: nextBlank)
        #expect(!model.canHint, "上限に達したら要求できない")
        #expect(!model.applyHint(at: nextBlank))
        #expect(model.board[nextBlank] == 0)
    }

    @Test("既に正解が入っているマスにはヒントを使えない（広告だけ見せて何も起きないのを防ぐ）")
    func cannotHintAlreadyCorrectCell() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: blank)
        model.enter(digit: model.solution[blank])
        #expect(!model.canHint)

        let given = (0..<81).first { model.given[$0] }!
        model.select(index: given)
        #expect(!model.canHint)
    }

    @Test("広告を見ている間に対象マスが埋まってしまったら、ヒントは不発になり回数も減らない")
    func hintTargetCanGoStale() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let target = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: target)
        #expect(model.canHint(at: target))

        // 広告の視聴中に（View 側ではロックしているが、念のため Model 単体でも）
        // そのマスが自力で埋まったとする。
        model.enter(digit: model.solution[target])

        #expect(!model.canHint(at: target))
        #expect(!model.applyHint(at: target), "入れられなかったことが呼び出し側に伝わる")
        #expect(model.hintsUsed == 0, "不発のときは回数を消費しない")
    }

    @Test("ヒントは選択が動いても、要求した時点のマスに入る")
    func hintGoesToTheRequestedCell() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        let target = blanks[0]
        let other = blanks[1]
        model.select(index: target)
        model.select(index: other)   // 広告の最中に選択が動いた想定

        #expect(model.applyHint(at: target))
        #expect(model.board[target] == model.solution[target])
        #expect(model.board[other] == 0, "選択が動いた先には入らない")
    }
}

@Suite("数独 Model の新規ゲームの再入")
@MainActor
struct SudokuModelNewGameTests {

    @Test("生成中の新規ゲーム要求は弾かれる（2本目の生成が走らない）")
    func newGameIsNotReentrant() async {
        let (model, _) = makeModel()
        async let first: Void = model.newGame(difficulty: .hard)

        // 1 本目が `.generating` に入るまで進める（実時間では待たない）。
        for _ in 0..<100 where !model.isGenerating { await Task.yield() }
        #expect(model.isGenerating)

        // 2 本目。弾かれるので**生成を始めずに即座に返る**。
        await model.newGame(difficulty: .easy)
        #expect(model.isGenerating, "弾かれたので、まだ 1 本目が生成中のまま")

        await first
        #expect(model.state == .playing)
        #expect(model.difficulty == .hard, "先に入った方の盤が残る")
        #expect(model.board.count == 81)
    }
}

@Suite("数独 Model の中断と復元")
@MainActor
struct SudokuModelSnapshotTests {

    @Test("解きかけを保存し、同じ状態で復元できる")
    func restoresInProgressBoard() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .hard)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: blank)
        model.enter(digit: model.solution[blank])
        model.toggleNoteMode()
        let other = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: other)
        model.enter(digit: 7)

        #expect(store.exists(for: "sudoku"))

        let restored = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.state == .playing)
        #expect(restored.board == model.board)
        #expect(restored.solution == model.solution)
        #expect(restored.given == model.given)
        #expect(restored.difficulty == .hard)
        #expect(restored.hasNote(7, at: other))
    }

    @Test("長さの合わないスナップショットは捨てて新規から始める")
    func brokenSnapshotIsDiscarded() throws {
        let store = MemorySnapshotStore()
        // 盤が 81 マス無い。信じると View の添字で即クラッシュする。
        try store.save(
            SudokuSnapshot(
                board: [1, 2, 3], given: [true], solution: [1], notes: [0],
                elapsedSeconds: 0, hintsUsed: 0, difficulty: .easy, hintedCells: []
            ),
            for: "sudoku"
        )

        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.state == .idle)
        #expect(model.board.count == 81)
        #expect(!store.exists(for: "sudoku"), "壊れた保存は消しておく")
    }

    @Test("出題のマスが正解と食い違うスナップショットも捨てる")
    func inconsistentSnapshotIsDiscarded() throws {
        let store = MemorySnapshotStore()
        var board = [Int](repeating: 1, count: 81)
        let solution = [Int](repeating: 2, count: 81)
        board[0] = 3
        var given = [Bool](repeating: false, count: 81)
        given[0] = true   // 出題なのに正解(2)と違う 3 が入っている
        try store.save(
            SudokuSnapshot(
                board: board, given: given, solution: solution,
                notes: [Int](repeating: 0, count: 81),
                elapsedSeconds: 0, hintsUsed: 0, difficulty: .normal, hintedCells: []
            ),
            for: "sudoku"
        )

        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.state == .idle)
    }

    @Test("完成済みのスナップショットは「プレイ中」として復元しない")
    func completedSnapshotIsDiscarded() throws {
        let store = MemorySnapshotStore()
        let solution = [Int](repeating: 4, count: 81)
        try store.save(
            SudokuSnapshot(
                board: solution, given: [Bool](repeating: true, count: 81), solution: solution,
                notes: [Int](repeating: 0, count: 81),
                elapsedSeconds: 10, hintsUsed: 0, difficulty: .easy, hintedCells: []
            ),
            for: "sudoku"
        )

        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.state == .idle)
    }
}
