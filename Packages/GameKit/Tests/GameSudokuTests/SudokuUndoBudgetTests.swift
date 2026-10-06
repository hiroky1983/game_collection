import Testing
import Foundation
import Core
@testable import GameSudoku
import CoreTestSupport

/// 「戻す」の回数制（#1855）。ソリティア・フリーセルと同じ `RewardedUndoBudget` を使う。
@Suite("数独: 戻すの回数制（#1855）")
@MainActor
struct SudokuUndoBudgetTests {
    private func makeModel(store: MemorySnapshotStore = MemorySnapshotStore()) -> SudokuModel {
        SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 2026)
    }

    /// 空きマスへ正解を入れてから戻す。`times` 回くり返す。
    private func enterAndUndo(_ model: SudokuModel, times: Int) {
        let blank = (0..<81).first { model.board[$0] == 0 }!
        for _ in 0..<times {
            // 戻すとそのマスが選択されたままになり、同じマスをもう一度タップすると選択が外れる。
            if model.selected != blank { model.select(index: blank) }
            model.enter(digit: model.solution[blank])
            #expect(model.canUndo)
            model.undo()
        }
    }

    @Test("経済は共有の RewardedUndoBudget と同じ値（別の値を持たない）")
    func sharesTheCoreBudget() {
        #expect(SudokuUndoBudget.free == RewardedUndoBudget.free)
        #expect(SudokuUndoBudget.refill == RewardedUndoBudget.refill)
        #expect(makeModel().undosRemaining == RewardedUndoBudget.free)
    }

    @Test("無料の回数だけ戻せて、使い切ると戻せず補充の提案になる")
    func freeUndosThenRefillNeeded() async {
        let model = makeModel()
        await model.newGame(difficulty: .easy)
        enterAndUndo(model, times: SudokuUndoBudget.free)
        #expect(model.undosRemaining == 0)

        let blank = (0..<81).first { model.board[$0] == 0 }!
        if model.selected != blank { model.select(index: blank) }
        model.enter(digit: model.solution[blank])
        #expect(model.canUndo, "戻せる手はある")
        #expect(model.needsUndoRefill)
        model.undo()
        #expect(model.board[blank] == model.solution[blank], "回数が無ければ盤面は動かない")
    }

    @Test("広告で補充すると戻せるようになり、戻せる手数は 1 手のまま")
    func grantRestoresUndos() async {
        let model = makeModel()
        await model.newGame(difficulty: .easy)
        enterAndUndo(model, times: SudokuUndoBudget.free)
        let blanks = (0..<81).filter { model.board[$0] == 0 }
        for index in blanks.prefix(2) {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }
        #expect(model.grantUndos(forGame: model.gameSerial))
        #expect(model.undosRemaining == SudokuUndoBudget.refill)

        model.undo()
        #expect(!model.canUndo, "戻せるのは直前の 1 手だけ")
        #expect(model.undosRemaining == SudokuUndoBudget.refill - 1)
    }

    @Test("広告を見ているあいだに新しい局が始まったら補充しない")
    func grantIgnoredAfterNewGame() async {
        let model = makeModel()
        await model.newGame(difficulty: .easy)
        enterAndUndo(model, times: SudokuUndoBudget.free)
        let game = model.gameSerial
        await model.newGame(difficulty: .easy)
        #expect(model.undosRemaining == SudokuUndoBudget.free)
        #expect(!model.grantUndos(forGame: game))
        #expect(model.undosRemaining == SudokuUndoBudget.free)
    }

    @Test("残り回数は中断データに保存され、復元で戻る")
    func remainingSurvivesRestore() async {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        enterAndUndo(model, times: 1)

        let restored = makeModel(store: store)
        #expect(restored.undosRemaining == SudokuUndoBudget.free - 1)
    }

    @Test("残り回数を持たない旧形式の中断データは無料枠いっぱいで再開する")
    func legacySnapshotStartsFull() throws {
        let data = Data(SudokuSnapshotCompatibilityTests.v116JSON.utf8)
        let snapshot = try JSONDecoder().decode(SudokuSnapshot.self, from: data)
        #expect(snapshot.undosRemaining == nil)

        let store = MemorySnapshotStore()
        store.inject(data, for: "sudoku")
        #expect(makeModel(store: store).undosRemaining == SudokuUndoBudget.free)
    }
}
