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
                elapsedSeconds: 0, hintsUsed: 0, difficulty: .easy, hintedCells: [], mistakes: nil
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
                elapsedSeconds: 0, hintsUsed: 0, difficulty: .normal, hintedCells: [], mistakes: nil
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
                elapsedSeconds: 10, hintsUsed: 0, difficulty: .easy, hintedCells: [], mistakes: nil
            ),
            for: "sudoku"
        )

        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.state == .idle)
    }
}

// MARK: - ミス上限と広告コンティニュー（会長指示 2026-08-30・2048 と同型）

@Suite("数独 Model のミス上限とコンティニュー")
@MainActor
struct SudokuMistakeTests {

    /// 空きマスを1つ選び、正解ではない数字を入れる。
    private func enterWrongDigit(_ model: SudokuModel) {
        guard let index = (0..<81).first(where: { !model.given[$0] && model.board[$0] == 0 }) else {
            Issue.record("空きマスが無い")
            return
        }
        if model.selected != index { model.select(index: index) }
        let wrong = (1...9).first { $0 != model.solution[index] }!
        model.enter(digit: wrong)
    }

    @Test("誤答でミスが増え、正解と同じ数字の入れ直しでは増えない")
    func countsOnlyNewWrongEntries() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)

        enterWrongDigit(model)
        #expect(model.mistakes == 1)

        // 同じマスに同じ誤答を入れ直しても無操作なので増えない。
        let index = model.selected!
        let current = model.board[index]
        model.enter(digit: current)
        #expect(model.mistakes == 1, "同じ数字の入れ直しがミスに数えられた")

        // 正解を入れてもミスは増えない。
        model.enter(digit: model.solution[index])
        #expect(model.mistakes == 1)
        #expect(model.state == .playing)
    }

    @Test("ミスが3回で failed になり、入力もヒントも受け付けない")
    func failsAtLimit() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)

        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        #expect(model.state == .failed)
        #expect(model.mistakes == SudokuModel.maxMistakes)
        #expect(model.selected == nil)
        #expect(!model.isFinished, "failed は決着ではない（コンティニューできる）")

        // failed 中は盤を触れない。
        model.select(index: 0)
        #expect(model.selected == nil)
        #expect(!model.canHint(at: 0))
    }

    @Test("コンティニューでミスが0に戻り、続きから遊べる")
    func continueResetsMistakes() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let boardBefore = { (m: SudokuModel) in m.board }

        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        let failedBoard = boardBefore(model)
        model.continueAfterAd()

        #expect(model.state == .playing)
        #expect(model.mistakes == 0)
        #expect(model.board == failedBoard, "盤面はそのまま続きから")

        // playing 中の誤ったコンティニュー呼び出しは無視される。
        model.continueAfterAd()
        #expect(model.state == .playing)
    }

    @Test("failed からも諦められる（負けとして決着）")
    func canGiveUpFromFailed() async {
        let (model, store) = makeModel()
        await model.newGame(difficulty: .easy)

        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        model.giveUp()

        #expect(model.state == .givenUp)
        #expect(model.board == model.solution)
        #expect(!store.exists(for: "sudoku"), "決着したらスナップショットは消える")
    }

    @Test("failed のまま閉じても復元で failed に戻る（ミスも保持）")
    func restoresFailedState() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        #expect(store.exists(for: "sudoku"), "failed でもスナップショットは残る")

        let (restored, _) = makeModel(store: store)
        #expect(restored.state == .failed)
        #expect(restored.mistakes == SudokuModel.maxMistakes)
        #expect(restored.board == model.board)
    }

    @Test("ミス途中の中断復元でミス回数が引き継がれる")
    func restoresMistakeCount() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        enterWrongDigit(model)

        let (restored, _) = makeModel(store: store)
        #expect(restored.state == .playing)
        #expect(restored.mistakes == 1)
    }
}

@Suite("数独 Model のミス回数の復元検証")
@MainActor
struct SudokuMistakeSnapshotValidationTests {

    private func snapshot(mistakes: Int?) -> SudokuSnapshot {
        // 有効な完成盤から1マスだけ空けた「プレイ途中」の形。
        let solution = [
            5,3,4,6,7,8,9,1,2, 6,7,2,1,9,5,3,4,8, 1,9,8,3,4,2,5,6,7,
            8,5,9,7,6,1,4,2,3, 4,2,6,8,5,3,7,9,1, 7,1,3,9,2,4,8,5,6,
            9,6,1,5,3,7,2,8,4, 2,8,7,4,1,9,6,3,5, 3,4,5,2,8,6,9,1,7,
        ]
        var board = solution
        board[0] = 0
        var given = [Bool](repeating: true, count: 81)
        given[0] = false
        return SudokuSnapshot(
            board: board, given: given, solution: solution,
            notes: [Int](repeating: 0, count: 81),
            elapsedSeconds: 1, hintsUsed: 0, difficulty: .easy,
            hintedCells: [], mistakes: mistakes
        )
    }

    // arguments は nonisolated に評価されるため @MainActor の maxMistakes を参照できない。
    // 4 = maxMistakes(3) + 1 のリテラル。
    @Test("範囲外のミス回数を含む中断データは捨てる", arguments: [-1, 4])
    func rejectsOutOfRangeMistakes(value: Int) throws {
        let store = MemorySnapshotStore()
        try store.save(snapshot(mistakes: value), for: "sudoku")
        let (model, _) = makeModel(store: store)
        #expect(model.state == .idle, "壊れた中断データを信じて復元してしまった")
        #expect(!store.exists(for: "sudoku"))
    }

    @Test("mistakes 無し（旧形式）はミス0として復元できる")
    func acceptsLegacySnapshot() throws {
        let store = MemorySnapshotStore()
        try store.save(snapshot(mistakes: nil), for: "sudoku")
        let (model, _) = makeModel(store: store)
        #expect(model.state == .playing)
        #expect(model.mistakes == 0)
    }
}

// MARK: - 元に戻す（#353）

@Suite("元に戻す")
@MainActor
struct SudokuUndoTests {

    /// そのマスに入れると必ず誤答になる数字。
    @MainActor
    private func wrongDigit(for index: Int, in model: SudokuModel) -> Int {
        (1...9).first { $0 != model.solution[index] }!
    }

    @Test("誤答を取り消すと盤とミス回数が戻る。続けては取り消せない（深さ1）")
    func undoRestoresMistake() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: blank)
        model.enter(digit: wrongDigit(for: blank, in: model))
        #expect(model.mistakes == 1)
        #expect(model.canUndo)

        model.undo()
        #expect(model.board[blank] == 0)
        #expect(model.mistakes == 0)
        #expect(!model.canUndo, "深さ1: 直前の1手しか持たない")
    }

    @Test("取り消せるのは直前の1手だけ（1つ前の手は残る）")
    func undoOnlyRevertsLastMove() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        let first = blanks[0], second = blanks[1]

        model.select(index: first)
        model.enter(digit: model.solution[first])
        model.select(index: second)
        model.enter(digit: model.solution[second])

        model.undo()
        #expect(model.board[second] == 0, "直前の手は取り消される")
        #expect(model.board[first] == model.solution[first], "1つ前の手は残る")
        #expect(!model.canUndo)
    }

    @Test("ヒントで埋めたマスは取り消しの対象にならない")
    func hintIsNotUndoable() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        #expect(model.applyHint(at: blank))
        #expect(!model.canUndo, "ヒントは undo の履歴に載らない（広告の対価を取り消させない）")
        model.undo()
        #expect(model.board[blank] == model.solution[blank], "undo してもヒントは消えない")
    }

    @Test("メモの付け外しも取り消せる")
    func undoRestoresNotes() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.toggleNoteMode()
        model.select(index: blank)
        model.enter(digit: 5)
        #expect(model.hasNote(5, at: blank))

        model.undo()
        #expect(!model.hasNote(5, at: blank))
    }

    @Test("正解入力で巻き添えになった同じ行・列・ブロックのメモも戻る")
    func undoRestoresPeerNotes() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        // 空きマス A と、その同行・列・ブロックにある別の空きマス B を選ぶ。
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        let a = blanks.first { i in SudokuEngine.peers(of: i).contains { model.board[$0] == 0 } }!
        let b = SudokuEngine.peers(of: a).first { model.board[$0] == 0 }!
        let digit = model.solution[a]

        model.toggleNoteMode()
        model.select(index: b)
        model.enter(digit: digit)      // B に digit のメモ
        model.toggleNoteMode()
        model.select(index: a)
        model.enter(digit: digit)      // A に正解を確定 → B のメモが巻き添えで消える
        #expect(!model.hasNote(digit, at: b))

        model.undo()
        #expect(model.board[a] == 0)
        #expect(model.hasNote(digit, at: b), "巻き添えで消えたメモも戻る")
    }

    @Test("3回目のミスは取り消せない（広告コンティニューの仕様を素通りさせない）")
    func thirdMistakeIsNotUndoable() async {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        for i in 0..<3 {
            model.select(index: blanks[i])
            model.enter(digit: wrongDigit(for: blanks[i], in: model))
        }
        #expect(model.state == .failed)
        #expect(!model.canUndo)

        model.continueAfterAd()
        #expect(model.mistakes == 0)
        #expect(!model.canUndo, "コンティニュー後に古い履歴でミスが巻き戻らない")
        model.undo()
        #expect(model.mistakes == 0)
    }

    @Test("ヒントを使うと手前の履歴も消える（ヒントが消したメモを undo で復活させない）")
    func hintDropsEarlierHistory() async throws {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)

        // 互いに同行・列・ブロックの空きマス3つ（a に入力・b にヒント・c が両方のメモを持つ）。
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        var found: (a: Int, b: Int, c: Int)?
        outer: for a in blanks {
            let peersOfA = SudokuEngine.peers(of: a)
            for b in blanks where b != a && peersOfA.contains(b) {
                let peersOfB = SudokuEngine.peers(of: b)
                for c in blanks where c != a && c != b
                    && peersOfA.contains(c) && peersOfB.contains(c) {
                    found = (a, b, c)
                    break outer
                }
            }
        }
        let (a, b, c) = try #require(found)

        // c に「a の正解」と「b の正解」の2つをメモしておく。
        model.toggleNoteMode()
        model.select(index: c)
        model.enter(digit: model.solution[a])
        model.enter(digit: model.solution[b])
        model.toggleNoteMode()
        #expect(model.hasNote(model.solution[a], at: c))
        #expect(model.hasNote(model.solution[b], at: c))

        // 1. a に正解を確定 → c の「a の正解」のメモが巻き添えで消え、履歴に控えられる
        model.select(index: a)
        model.enter(digit: model.solution[a])
        #expect(model.canUndo)

        // 2. b にヒント → c の「b の正解」のメモも消える
        #expect(model.applyHint(at: b))
        #expect(!model.hasNote(model.solution[b], at: c))

        // 3. 「元に戻す」— 手順1の履歴が残っていると、手順2でヒントが消したメモまで戻る
        #expect(!model.canUndo, "ヒントの後に手前の履歴が残っている")
        model.undo()
        #expect(!model.hasNote(model.solution[b], at: c),
                "ヒントが消したメモが undo で復活している（広告の対価が巻き戻る）")
        #expect(model.board[a] == model.solution[a], "ヒントの後の undo で手前の入力まで戻っている")
    }

    @Test("中断・再開をまたぐと取り消せない（履歴は保存しない）")
    func undoDoesNotSurviveRestore() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: blank)
        model.enter(digit: model.solution[blank])
        #expect(model.canUndo)

        let (restored, _) = makeModel(store: store)
        #expect(restored.state == .playing)
        #expect(!restored.canUndo)
    }
}
