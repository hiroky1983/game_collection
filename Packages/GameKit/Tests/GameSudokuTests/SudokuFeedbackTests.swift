import Testing
import Foundation
import Core
@testable import GameSudoku
import CoreTestSupport

@MainActor
private func makeModel(store: MemorySnapshotStore = MemorySnapshotStore()) -> (SudokuModel, SpyFeedbackService) {
    let spy = SpyFeedbackService()
    let services = GameServices(snapshots: store, ads: NoopAdService(), feedback: spy)
    return (SudokuModel(services: services, seed: 2026), spy)
}

/// 選択を合わせてから数字を入れる（同じマスをもう一度タップすると選択が外れるため）。
@MainActor
private func place(_ model: SudokuModel, _ digit: Int, at index: Int) {
    if model.selected != index { model.select(index: index) }
    model.enter(digit: digit)
}

/// 正解ではない数字。`offset` を 1〜8 で変えると互いに違う誤答になる。
@MainActor
private func wrongDigit(_ model: SudokuModel, at index: Int, offset: Int = 1) -> Int {
    (model.solution[index] - 1 + offset) % SudokuEngine.size + 1
}

/// 行・列・ブロックのどれにも自分以外の空きマスが残っている空きマス（正解を入れても何も揃わない）。
@MainActor
private func cellThatCompletesNothing(_ model: SudokuModel) -> Int? {
    (0..<SudokuEngine.cellCount).first { index in
        model.board[index] == 0 && SudokuEngine.units(of: index).allSatisfy { unit in
            SudokuEngine.cells(ofUnit: unit).filter { model.board[$0] == 0 }.count >= 2
        }
    }
}

/// 空きマスが 2 つ以上ある行の 9 マス（最後の 1 マスで揃う瞬間を作るため）。
@MainActor
private func rowWithSeveralEmptyCells(_ model: SudokuModel) -> [Int]? {
    (0..<SudokuEngine.size)
        .map { SudokuEngine.cells(ofUnit: $0) }
        .first { row in row.filter { model.board[$0] == 0 }.count >= 2 }
}

@Suite("ナンプレの手応え（誤答・揃った瞬間・使い切り #666）")
@MainActor
struct SudokuFeedbackTests {

    @Test("誤答は warning、正答は medium で、触覚の種類が違う")
    func wrongAndCorrectFeelDifferent() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let index = try #require(cellThatCompletesNothing(model))

        model.select(index: index)
        spy.reset()
        model.enter(digit: wrongDigit(model, at: index))
        #expect(spy.notices == [.warning])
        #expect(spy.impacts.isEmpty, "誤答でも impact を鳴らすと正答と区別が付かない")

        // 同じ誤答の入れ直し（ミスには数えない）でも、マスは誤答のままなので正答の手応えを返さない。
        spy.reset()
        model.enter(digit: wrongDigit(model, at: index))
        #expect(spy.notices == [.warning])
        #expect(spy.impacts.isEmpty)

        spy.reset()
        model.enter(digit: model.solution[index])
        #expect(spy.impacts == [.medium])
        #expect(spy.notices.isEmpty)
    }

    @Test("3回目のミスは error だけを鳴らす（warning と重ねない）")
    func thirdMistakeOnlyErrors() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let index = try #require(cellThatCompletesNothing(model))

        model.select(index: index)
        model.enter(digit: wrongDigit(model, at: index, offset: 1))
        model.enter(digit: wrongDigit(model, at: index, offset: 2))
        spy.reset()
        #expect(model.mistakeShakes == [index: 2])
        model.enter(digit: wrongDigit(model, at: index, offset: 3))
        #expect(model.state == .failed)
        #expect(spy.notices == [.error])
        #expect(spy.impacts.isEmpty)
        #expect(model.mistakeShakes == [index: 2], "失敗の表示の下でマスを揺らさない")
    }

    @Test("誤答はそのマスの揺れの回数だけを進め、同じ誤答の入れ直しや正答では進めない")
    func mistakeShakesCountOnlyNewWrongEntries() async throws {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let index = try #require(cellThatCompletesNothing(model))
        let wrong = wrongDigit(model, at: index)

        model.select(index: index)
        model.enter(digit: wrong)
        #expect(model.mistakeShakes == [index: 1])
        model.enter(digit: wrong)
        #expect(model.mistakeShakes == [index: 1], "同じ数字の入れ直しはミスに数えないので揺らさない")
        #expect(model.mistakes == 1)
        model.enter(digit: model.solution[index])
        #expect(model.mistakeShakes == [index: 1])

        await model.newGame(difficulty: .easy)
        #expect(model.mistakeShakes.isEmpty, "新しい局に前の局の揺れを持ち越さない")
    }

    @Test("行が揃った瞬間にその 9 マスが光り、触覚は light になる")
    func completingRowFlashesItsCells() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        #expect(model.unitFlash == nil, "出題の数字だけで揃っているユニットは光らせない")
        let row = try #require(rowWithSeveralEmptyCells(model))
        let empties = row.filter { model.board[$0] == 0 }

        for index in empties.dropLast() { place(model, model.solution[index], at: index) }
        #expect(model.unitFlash?.cells.isSuperset(of: row) != true, "揃う前に行が光っている")

        let last = try #require(empties.last)
        if model.selected != last { model.select(index: last) }
        spy.reset()
        model.enter(digit: model.solution[last])
        #expect(model.state == .playing)
        #expect(model.unitFlash?.cells.isSuperset(of: row) == true)
        #expect(spy.impacts == [.light])
        #expect(spy.notices.isEmpty)
    }

    @Test("一度光ったユニットは、消して入れ直しても光らない")
    func flashesOnlyOnce() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let row = try #require(rowWithSeveralEmptyCells(model))
        let empties = row.filter { model.board[$0] == 0 }
        for index in empties { place(model, model.solution[index], at: index) }
        let flash = try #require(model.unitFlash)

        let index = empties[0]
        if model.selected != index { model.select(index: index) }
        model.erase()
        spy.reset()
        model.enter(digit: model.solution[index])
        #expect(model.unitFlash == flash)
        #expect(spy.impacts == [.medium])
    }

    @Test("中断から復元した時点で揃っているユニットは、入れ直しても光らない")
    func restoredCompletedUnitsDoNotFlashAgain() async throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.newGame(difficulty: .easy)
        let row = try #require(rowWithSeveralEmptyCells(model))
        let empties = row.filter { model.board[$0] == 0 }
        for index in empties { place(model, model.solution[index], at: index) }
        #expect(model.unitFlash != nil)
        model.pauseTimer()

        let (restored, spy) = makeModel(store: store)
        #expect(restored.state == .playing)
        #expect(restored.unitFlash == nil)
        let index = empties[0]
        restored.select(index: index)
        restored.erase()
        spy.reset()
        restored.enter(digit: restored.solution[index])
        #expect(restored.unitFlash == nil)
        #expect(spy.impacts == [.medium])
    }

    @Test("ヒントで揃ったときも光る")
    func hintCompletingRowFlashes() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let row = try #require(rowWithSeveralEmptyCells(model))
        let empties = row.filter { model.board[$0] == 0 }
        for index in empties.dropLast() { place(model, model.solution[index], at: index) }

        spy.reset()
        #expect(model.applyHint(at: try #require(empties.last)))
        #expect(model.unitFlash?.cells.isSuperset(of: row) == true)
        #expect(spy.impacts == [.light])
    }

    @Test("盤が完成する手ではユニットを光らせず、クリアの合図に任せる")
    func finalMoveDoesNotFlash() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let empties = (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 }
        for index in empties.dropLast() { place(model, model.solution[index], at: index) }
        let flashBefore = model.unitFlash

        let last = try #require(empties.last)
        if model.selected != last { model.select(index: last) }
        spy.reset()
        model.enter(digit: model.solution[last])
        #expect(model.state == .cleared)
        #expect(model.unitFlash == flashBefore)
        #expect(spy.impacts == [.medium])
        #expect(spy.notices == [.success])
    }

    @Test("揃ったマスの光は、光っている時間とフェードを合わせて 0.25 秒に収まる")
    func unitFlashLastsQuarterSecond() {
        let total = SudokuMetrics.unitFlashHoldDuration + SudokuMetrics.unitFlashFadeDuration
        #expect(abs(total - 0.25) < 1e-9, "合計 \(total) 秒")
        #expect(SudokuMetrics.unitFlashHoldDuration > 0, "光る前に消え始めると目に入らない")
    }

    @Test("数字を 9 個とも正解で埋めると、その数字は使い切りになる")
    func digitExhaustedAfterAllNinePlaced() async throws {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let emptyCount = { (digit: Int) in
            (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 && model.solution[$0] == digit }.count
        }
        let digit = try #require((1...SudokuEngine.size).max { emptyCount($0) < emptyCount($1) })
        try #require(emptyCount(digit) > 0)
        #expect(!model.isDigitExhausted(digit))

        for index in (0..<SudokuEngine.cellCount) where model.board[index] == 0 && model.solution[index] == digit {
            place(model, digit, at: index)
        }
        #expect(model.isDigitExhausted(digit))
    }

    @Test("誤答の同じ数字は使い切りに数えず、消せば戻り、9 個目の正解で初めて使い切りになる（#813）")
    func wrongEntryDoesNotExhaustDigit() async throws {
        let (model, _) = makeModel()
        await model.newGame(difficulty: .easy)
        let emptyCount = { (digit: Int) in
            (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 && model.solution[$0] == digit }.count
        }
        let digit = try #require((1...SudokuEngine.size).max { emptyCount($0) < emptyCount($1) })
        let targets = (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 && model.solution[$0] == digit }
        let last = try #require(targets.last)
        for index in targets.dropLast() { place(model, digit, at: index) }
        #expect(!model.isDigitExhausted(digit))

        // 正解 8 個＋別のマスに誤答 1 個で、盤上のこの数字は 9 個になる。
        let wrongCell = try #require((0..<SudokuEngine.cellCount).first {
            model.board[$0] == 0 && model.solution[$0] != digit
        })
        place(model, digit, at: wrongCell)
        #expect(model.state == .playing)
        #expect(model.board.filter { $0 == digit }.count == SudokuEngine.size)
        #expect(!model.isDigitExhausted(digit))

        model.erase()
        #expect(model.board[wrongCell] == 0)
        #expect(!model.isDigitExhausted(digit))

        place(model, digit, at: last)
        #expect(model.isDigitExhausted(digit))
    }
}

@Suite("数独のユニット（行・列・ブロックの通し番号 #666）")
struct SudokuUnitTests {

    @Test("27 ユニットはどれも 9 マスで、各マスはちょうど 3 つのユニットに属する")
    func unitsPartitionBoard() {
        var membership = [Int](repeating: 0, count: SudokuEngine.cellCount)
        for unit in 0..<SudokuEngine.unitCount {
            let cells = SudokuEngine.cells(ofUnit: unit)
            #expect(Set(cells).count == SudokuEngine.size, "ユニット \(unit) が 9 マスでない")
            for cell in cells {
                membership[cell] += 1
                #expect(SudokuEngine.units(of: cell).contains(unit), "マス \(cell) からユニット \(unit) を引けない")
            }
        }
        #expect(membership.allSatisfy { $0 == 3 })
    }

    @Test("マスが属するユニットの和集合は、自分を除けば peers と一致する")
    func unitsMatchPeers() {
        for index in 0..<SudokuEngine.cellCount {
            var union = Set(SudokuEngine.units(of: index).flatMap { SudokuEngine.cells(ofUnit: $0) })
            union.remove(index)
            #expect(union == SudokuEngine.peers(of: index), "マス \(index)")
        }
    }
}
