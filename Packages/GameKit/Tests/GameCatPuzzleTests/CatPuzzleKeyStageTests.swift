import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 「鍵を持った猫」の面（#3235）。9×9 までは 10 面ごと、10×10 以上は 20 面ごと（#3259）。
@Suite("おじさんちのねこさがしの鍵の面")
@MainActor
struct CatPuzzleKeyStageTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.key.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeServices(store: MemorySnapshotStore = MemorySnapshotStore()) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService())
    }

    /// 鍵の面（10 面目）の盤を直接与えて始める。
    private func keyModel(store: MemorySnapshotStore = MemorySnapshotStore(), stage: Int = 10) -> CatPuzzleModel {
        let puzzle = CatPuzzleStage(stage).makePuzzle()
        return CatPuzzleModel(services: makeServices(store: store), puzzle: puzzle, size: CatPuzzleStage(stage).size,
                              stage: stage, stageDefaults: makeDefaults("m\(stage)"))
    }

    /// 鍵の部屋の外で、答えでない・答えのマスを 1 つずつ返す。
    private func outsideCell(_ model: CatPuzzleModel) -> Int {
        let room = model.keyRoom!
        return model.puzzle.rooms.indices.first { model.puzzle.rooms[$0] != room }!
    }

    // MARK: - 出る面と問題

    @Test("鍵の面は 9×9 までは 10 面ごと（10〜70）、10×10 以上（71 面〜）は 20 面ごと（80・100・120…）")
    func keyStageNumbers() {
        for number in [10, 20, 30, 50, 60, 70, 80, 100, 120, 140, 160, 500, 520] { #expect(CatPuzzleStage(number).isKey, "\(number)") }
        for number in [1, 9, 11, 45, 46, 69, 71, 79, 81, 90, 99, 110, 130, 150, 170, 510] { #expect(!CatPuzzleStage(number).isKey, "\(number)") }
    }

    @Test("鍵の面までの数: 70 面までは 10 面ごと、71 面からは 20 面ごとの次の鍵の面に向かって数える")
    func stagesToKey() {
        #expect(CatPuzzleStage(69).progress.toKey == 0 && CatPuzzleStage(70).progress.isKey)
        #expect(CatPuzzleStage(71).progress.toKey == 8 && !CatPuzzleStage(71).progress.isKey)
        #expect(CatPuzzleStage(79).progress.toKey == 0)
        #expect(CatPuzzleStage(80).progress.isKey && CatPuzzleStage(80).progress.toKey == 0)
        #expect(CatPuzzleStage(81).progress.toKey == 18)
        #expect(CatPuzzleStage(90).progress.toKey == 9)
        #expect(CatPuzzleStage(99).progress.toKey == 0)
    }

    @Test("10×10 以上の鍵の面は段 3 まで（12×12 は段 4 まで可）・入り組みは前半と同じ。後半の鍵の面でも下げる")
    func wideKeyStagesAreEasier() {
        #expect(CatPuzzleStage(80).tiers == 1...3 && CatPuzzleStage(80).winding == 1)
        #expect(CatPuzzleStage(100).tiers == 1...3 && CatPuzzleStage(100).winding == 1, "10×10 の後半（本来は段 4・入り組み 2）")
        #expect(CatPuzzleStage(120).tiers == 1...3 && CatPuzzleStage(120).winding == 1)
        #expect(CatPuzzleStage(140).tiers == 1...3 && CatPuzzleStage(140).winding == 1, "11×11 の後半")
        #expect(CatPuzzleStage(160).tiers == 1...4 && CatPuzzleStage(160).winding == 1, "12×12 の後半")
        #expect(CatPuzzleStage(90).tiers == 4...4 && CatPuzzleStage(90).winding == 2, "鍵の面でない後半の面は今まで通り")
        #expect(CatPuzzleStage(60).tiers == 1...4, "9×9 までの鍵の面は変えない")
    }

    @Test("鍵の面の問題は、鍵の猫が盤に何も置かなくても論理だけで決まり、それは答えのマス（10・20・30・40 面）")
    func keyStagePuzzlesHaveKeyCat() {
        for number in [10, 20, 30, 40] {
            let puzzle = CatPuzzleStage(number).makePuzzle()
            let key = CatPuzzleSolver.keyCat(puzzle)
            #expect(key != nil, "\(number) 面")
            if let key { #expect(puzzle.solutionCells.contains(key), "\(number) 面の鍵の猫は答えのマス") }
            #expect(CatPuzzleSolver.rate(puzzle, maxTier: 4).solved)
        }
    }

    @Test("同じ番号なら同じ鍵の面の問題になる（種はステージ番号から決まる）")
    func keyStageIsDeterministic() {
        #expect(CatPuzzleStage(20).generatePuzzle() == CatPuzzleStage(20).generatePuzzle())
    }

    @Test("同梱の問題（50〜1,000 面）の鍵の面は、すべて鍵の猫が決まり、段が範囲内")
    func bankedKeyStagesHaveKeyCat() {
        for number in stride(from: 50, through: 1000, by: 10) where CatPuzzleStage(number).isKey {
            let puzzle = CatPuzzleStageBank.puzzle(for: number)
            #expect(puzzle != nil, "\(number) 面")
            guard let puzzle else { continue }
            let key = CatPuzzleSolver.keyCat(puzzle)
            #expect(key != nil, "\(number) 面")
            if let key { #expect(puzzle.solutionCells.contains(key), "\(number) 面") }
            let tier = CatPuzzleSolver.rate(puzzle, maxTier: 4).tier
            #expect(CatPuzzleStage(number).tiers.contains(tier), "\(number) 面の段 \(tier)")
        }
    }

    @Test("解き手の鍵の猫は、どんな問題でも答えのマス（当て推量をしない）")
    func keyCatIsAlwaysAnswerCell() {
        var generator = SplitMix64(seed: 3235)
        for _ in 0..<60 {
            let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
            if let key = CatPuzzleSolver.keyCat(puzzle) { #expect(puzzle.solutionCells.contains(key)) }
        }
    }

    @Test("鍵の猫が決まらない問題もある（条件が素通しではない）")
    func someGeneratedPuzzlesHaveNoKeyCat() {
        var generator = SplitMix64(seed: 3235)
        let keys = (0..<60).map { _ in CatPuzzleSolver.keyCat(CatPuzzleLogic.generate(size: .easy, using: &generator)) }
        #expect(keys.contains { $0 == nil })
        #expect(keys.contains { $0 != nil })
    }

    // MARK: - 鍵が閉じている間の操作

    @Test("鍵の面は鍵が閉じて始まり、鍵の部屋の外には × も猫も置けない（触ると案内のきっかけが増える）")
    func lockedBlocksOutside() {
        let model = keyModel()
        #expect(model.isKeyLocked)
        #expect(model.keyCat != nil && model.keyRoom != nil)
        let outside = outsideCell(model)
        #expect(model.isLockedOut(cell: outside))
        #expect(!model.toggleCross(cell: outside))
        #expect(model.marks[outside] == .empty)
        model.findCat(cell: outside)
        #expect(model.marks[outside] == .empty)
        #expect(model.mistakes == 0, "触れないマスはミスにならない")
        #expect(model.lockedTouches == 2)
        model.beginCrossDrag(cell: outside)
        model.dragCross(to: outside)
        model.endCrossDrag()
        #expect(model.marks[outside] == .empty)
        #expect(model.lockedTouches == 3, "スライドの案内は 1 回")
    }

    @Test("鍵の部屋の中は × を付け外しでき、猫を探せる（間違えればミス）")
    func insideKeyRoomIsOpen() {
        let model = keyModel()
        let room = model.keyRoom!
        let key = model.keyCat!
        let wrong = model.puzzle.cells(inRoom: room).first { $0 != key }
        if let wrong {
            #expect(model.toggleCross(cell: wrong))
            #expect(model.marks[wrong] == .cross)
            #expect(model.toggleCross(cell: wrong))
            #expect(model.marks[wrong] == .empty)
            model.findCat(cell: wrong)
            #expect(model.mistakes == 1)
            #expect(model.isKeyLocked)
        }
        #expect(model.lockedTouches == 0)
    }

    @Test("鍵の猫を見つけたら制限が外れ、鍵が開いた回数が増える。外の部屋にも印を付けられる")
    func findingKeyCatUnlocks() {
        let model = keyModel()
        model.findCat(cell: model.keyCat!)
        #expect(model.marks[model.keyCat!] == .cat)
        #expect(!model.isKeyLocked)
        #expect(model.keyOpenings == 1)
        let outside = outsideCell(model)
        #expect(!model.isLockedOut(cell: outside))
        #expect(model.toggleCross(cell: outside))
        #expect(model.marks[outside] == .cross)
        #expect(model.lockedTouches == 0)
    }

    @Test("戻す・やり直しで鍵の猫が消えれば、また鍵が閉じる")
    func undoRelocks() {
        let model = keyModel()
        model.findCat(cell: model.keyCat!)
        #expect(!model.isKeyLocked)
        model.undo()
        #expect(model.isKeyLocked)
        model.findCat(cell: model.keyCat!)
        model.reset()
        #expect(model.isKeyLocked)
    }

    @Test("ステージでない盤・鍵の面でないステージは制限なし")
    func nonKeyStagesAreFree() {
        let free = CatPuzzleModel(services: makeServices(), puzzle: CatPuzzleStage(11).makePuzzle(), size: .easy)
        #expect(free.keyCat == nil && !free.isKeyLocked)
        let stage11 = keyModel(stage: 11)
        #expect(stage11.keyCat == nil && !stage11.isKeyLocked)
        #expect(stage11.toggleCross(cell: 0))
        #expect(stage11.lockedTouches == 0)
    }

    // MARK: - 中断→再開

    @Test("中断して再開しても、鍵が閉じている状態・開いた状態がそのまま戻る")
    func resumeRestoresKeyState() {
        let store = MemorySnapshotStore()
        let model = keyModel(store: store)
        let room = model.keyRoom!
        let inside = model.puzzle.cells(inRoom: room).first { $0 != model.keyCat }!
        #expect(model.toggleCross(cell: inside))
        model.pauseTimer()
        let resumed = CatPuzzleModel(services: makeServices(store: store), stageDefaults: makeDefaults("resume1"))
        #expect(resumed.stage == 10)
        #expect(resumed.isKeyLocked)
        #expect(resumed.keyCat == model.keyCat)
        #expect(resumed.isLockedOut(cell: outsideCell(resumed)))

        resumed.findCat(cell: resumed.keyCat!)
        resumed.pauseTimer()
        let again = CatPuzzleModel(services: makeServices(store: store), stageDefaults: makeDefaults("resume2"))
        #expect(again.stage == 10)
        #expect(!again.isKeyLocked, "鍵を開けたあとの中断は開いたまま")
        #expect(again.toggleCross(cell: outsideCell(again)))
    }

    // MARK: - ヒント・猫を教える

    @Test("鍵が閉じている間のヒントは鍵の猫を置く（鍵の部屋の外には何も置かない）。使うと鍵が開く")
    func hintPlacesKeyCatWhileLocked() {
        let model = keyModel()
        let hint = model.nextHint
        #expect(hint?.placed == model.keyCat)
        #expect(hint?.crossed.isEmpty == true && hint?.removed.isEmpty == true)
        #expect(model.canHint)
        model.useHint()
        #expect(model.marks[model.keyCat!] == .cat)
        #expect(model.hintCells.contains(model.keyCat!))
        #expect(!model.isKeyLocked)
        #expect(model.keyOpenings == 1)
    }

    @Test("猫を教えるは、鍵が閉じている間は鍵の猫を教え、開いてからは今までどおり")
    func teachPlacesKeyCatFirst() {
        let model = keyModel()
        model.teachCat()
        #expect(model.marks[model.keyCat!] == .cat)
        #expect(!model.isKeyLocked)
        model.teachCat()
        let cats = model.catCells
        #expect(cats.count == 2)
        #expect(cats.allSatisfy { model.puzzle.solutionCells.contains($0) })
    }

    @Test("鍵の面でも最後までクリアできる")
    func keyStageCanBeCleared() {
        let model = keyModel()
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat {
            // 鍵の猫が先。あとは番号順で置いても、鍵が開いているので通る。
            if model.isKeyLocked { model.findCat(cell: model.keyCat!) }
            model.findCat(cell: cell)
        }
        #expect(model.isSolved)
        #expect(!model.isKeyLocked)
    }

    // MARK: - 60 面の誤判定の報告（#3300）

    /// 画面のタップと同じ入口（`tap(cell:)` を 0.2 秒あけて 2 回）でダブルタップする。
    private func doubleTap(_ model: CatPuzzleModel, _ cell: Int, clock: ManualClock) {
        clock.advance(by: .seconds(1))
        model.tap(cell: cell)
        clock.advance(by: .milliseconds(200))
        model.tap(cell: cell)
    }

    @Test("60 面: 鍵の部屋は玄関（部屋 6）で、鍵の猫は 4 行 3 列目（マス 29）。玄関の答えはそのマスだけで、解は 1 つ")
    func stage60KeyRoomFacts() {
        let puzzle = CatPuzzleStage(60).makePuzzle()
        let key = CatPuzzleSolver.keyCat(puzzle)
        #expect(key == 29)
        #expect(puzzle.rooms[29] == 6 && CatPuzzleHouse.room(6).name == "玄関")
        #expect(puzzle.cells(inRoom: 6) == [10, 19, 28, 29])
        #expect(puzzle.solutionCells.filter { puzzle.rooms[$0] == 6 } == [29])
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 2) == 1)
        #expect(CatPuzzleSolver.solve(puzzle) == puzzle.solutionCells.sorted())
    }

    @Test("60 面: 鍵が閉じている間、鍵の猫（玄関の答え）をダブルタップすると猫が置けて鍵が開く（ミスにならない）")
    func stage60DoubleTapKeyCat() {
        let clock = ManualClock()
        let model = keyModel(stage: 60)
        model.clockNow = clock.now
        #expect(model.isKeyLocked && model.keyCat == 29)
        doubleTap(model, 29, clock: clock)
        #expect(model.marks[29] == .cat && model.mistakes == 0 && model.wrongCrosses.isEmpty)
        #expect(!model.isKeyLocked && model.keyOpenings == 1)
        // 残りも画面と同じ入口で置いて、ミス 0 のままクリアできる。
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { doubleTap(model, cell, clock: clock) }
        #expect(model.isSolved && model.mistakes == 0)
    }

    @Test("60 面: 鍵が閉じている間、玄関の外の答えのマスをダブルタップ・× ・スライドしてもミスにならず、盤も変わらず、案内だけ出る")
    func stage60LockedOutsideAnswersAreNotMistakes() {
        let clock = ManualClock()
        let model = keyModel(stage: 60)
        model.clockNow = clock.now
        let outside = model.puzzle.solutionCells.filter { model.puzzle.rooms[$0] != 6 }
        #expect(outside.count == 8)
        var touches = 0
        for cell in outside {
            doubleTap(model, cell, clock: clock)
            touches += 2
            #expect(!model.toggleCross(cell: cell))
            touches += 1
            model.beginCrossDrag(cell: cell)
            model.dragCross(to: cell)
            model.endCrossDrag()
            touches += 1
        }
        #expect(model.mistakes == 0 && model.wrongCrosses.isEmpty)
        #expect(model.marks.allSatisfy { $0 == .empty }, "盤は変わらない")
        #expect(model.lockedTouches == touches, "触るたびに案内のきっかけだけ増える")
        #expect(model.isKeyLocked && model.moves == 0)
    }

    @Test("同梱と 10〜40 面の鍵の面すべてで、鍵の猫は鍵の部屋の唯一の答えで、画面と同じダブルタップでミス 0 でクリアできる")
    func everyKeyStageClearsWithoutMistakesViaTap() {
        let bankKeys = stride(from: 50, through: CatPuzzleStageBank.lastStage, by: 10).filter { CatPuzzleStage($0).isKey }
        for number in [10, 20, 30, 40] + bankKeys {
            let clock = ManualClock()
            let model = keyModel(stage: number)
            model.clockNow = clock.now
            guard let key = model.keyCat, let room = model.keyRoom else {
                Issue.record("\(number) 面に鍵の猫が無い")
                continue
            }
            #expect(model.puzzle.solutionCells.filter { model.puzzle.rooms[$0] == room } == [key], "\(number) 面")
            doubleTap(model, key, clock: clock)
            for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { doubleTap(model, cell, clock: clock) }
            #expect(model.isSolved && model.mistakes == 0, "\(number) 面")
        }
    }
}
