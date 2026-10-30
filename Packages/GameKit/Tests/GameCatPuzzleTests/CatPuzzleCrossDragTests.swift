import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// スライドで続けて × を付け外しする入口（#3116）。
@MainActor
struct CatPuzzleCrossDragTests {
    /// 4×4 の見本（答えは行の順に列 1・3・0・2）。
    private let sample = CatPuzzle(
        side: 4,
        rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3],
        solution: [1, 3, 0, 2]
    )

    private func makeModel(feedback: SpyFeedbackService = SpyFeedbackService()) -> CatPuzzleModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        return CatPuzzleModel(services: services, puzzle: sample)
    }

    @Test("空から始めたスライドは、通った空マスだけ × になる（× のマスはそのまま）")
    func slideFromEmptyAddsCrosses() {
        let model = makeModel()
        model.toggleCross(cell: 6)
        model.beginCrossDrag(cell: 4)
        model.dragCross(to: 5)
        model.dragCross(to: 6)
        model.dragCross(to: 7)
        model.endCrossDrag()
        #expect(model.marks[4] == .cross && model.marks[5] == .cross && model.marks[7] == .cross)
        #expect(model.marks[6] == .cross, "もとから ×")
        #expect(model.marks[0] == .empty)
    }

    @Test("× から始めたスライドは × だけ外れる（空のマスはそのまま）")
    func slideFromCrossRemovesCrosses() {
        let model = makeModel()
        for cell in [4, 6, 7] { model.toggleCross(cell: cell) }
        model.beginCrossDrag(cell: 4)
        model.dragCross(to: 5)
        model.dragCross(to: 6)
        model.dragCross(to: 7)
        model.endCrossDrag()
        #expect(model.marks[4] == .empty && model.marks[6] == .empty && model.marks[7] == .empty)
        #expect(model.marks[5] == .empty)
    }

    @Test("猫・ヒントの印・赤い × は変わらない")
    func slideLeavesFixedMarks() {
        let model = makeModel()
        model.findCat(cell: 1)
        model.findCat(cell: 0) // 答えでない → 赤い ×（ミス 1）
        #expect(model.marks[1] == .cat && model.wrongCrosses == [0])
        model.beginCrossDrag(cell: 3)
        model.dragCross(to: 2)
        model.dragCross(to: 1)
        model.dragCross(to: 0)
        model.endCrossDrag()
        #expect(model.marks[3] == .cross && model.marks[2] == .cross)
        #expect(model.marks[1] == .cat && model.marks[0] == .cross && model.wrongCrosses == [0])
        // × から始めて外すスライドでも、赤い × は残る。
        model.beginCrossDrag(cell: 3)
        model.dragCross(to: 0)
        model.endCrossDrag()
        #expect(model.marks[3] == .empty && model.marks[2] == .empty)
        #expect(model.marks[1] == .cat && model.marks[0] == .cross)
    }

    @Test("1 回のスライドは戻す 1 回ぶん・手数 1。往復しても 1 回だけ変わる")
    func slideIsOneUndoStepAndRoundTripChangesOnce() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback: feedback)
        model.beginCrossDrag(cell: 4)
        feedback.reset()
        model.dragCross(to: 5)
        model.dragCross(to: 6)
        model.dragCross(to: 5)
        model.dragCross(to: 4)
        model.dragCross(to: 5)
        model.endCrossDrag()
        #expect(model.moves == 1)
        #expect(feedback.impacts.count == 2, "新しく変えた 5 と 6 の 2 回だけ（4 は開始時）")
        #expect(model.marks[4...6].allSatisfy { $0 == .cross })
        model.undo()
        #expect(model.marks.allSatisfy { $0 == .empty }, "戻す 1 回でスライド全体が戻る")
        #expect(!model.canUndo)
    }

    @Test("速いスライドで飛んだマスは線で補間して埋める")
    func fastSlideInterpolatesSkippedCells() {
        let model = makeModel()
        model.beginCrossDrag(cell: 0)
        model.dragCross(to: 3)
        model.dragCross(to: 15)
        model.endCrossDrag()
        #expect([0, 1, 2, 3, 7, 11, 15].allSatisfy { model.marks[$0] == .cross })
        #expect(CatPuzzleModel.cellsOnLine(from: 0, to: 15, side: 4) == [0, 5, 10, 15])
        #expect(CatPuzzleModel.cellsOnLine(from: 12, to: 3, side: 4) == [12, 9, 6, 3])
    }

    @Test("盤の外に出たあと戻っても、外を通った線は補間しない")
    func leavingBoardBreaksInterpolation() {
        let model = makeModel()
        model.beginCrossDrag(cell: 0)
        model.dragCross(to: nil)
        model.dragCross(to: 15)
        model.endCrossDrag()
        #expect(model.marks[0] == .cross && model.marks[15] == .cross)
        #expect(model.marks[5] == .empty && model.marks[10] == .empty)
    }

    @Test("座標からマスへの変換。余白・盤の外は nil")
    func cellAtPoint() {
        func cell(_ x: CGFloat, _ y: CGFloat) -> Int? {
            CatPuzzleModel.cell(at: CGPoint(x: x, y: y), side: 4, cellSide: 50, inset: 8)
        }
        #expect(cell(8, 8) == 0)
        #expect(cell(57.9, 57.9) == 0)
        #expect(cell(58, 8) == 1)
        #expect(cell(207.9, 207.9) == 15)
        #expect(cell(7.9, 20) == nil && cell(20, 7.9) == nil)
        #expect(cell(208, 20) == nil && cell(20, 208) == nil)
        #expect(cell(-30, 20) == nil)
    }

    @Test("スライドを始めるとダブルタップの控えを捨てる。短い動きは今のタップのまま")
    func slideDropsPendingTapAndTapStillWorks() {
        let clock = ManualClock()
        let model = makeModel()
        model.clockNow = clock.now
        model.tap(cell: 1)
        model.beginCrossDrag(cell: 4)
        model.dragCross(to: 5)
        model.endCrossDrag()
        // 直前のタップ (1) と同じマスへのタップは、スライドを挟んだのでダブルタップにならない。
        clock.advance(by: .milliseconds(100))
        model.tap(cell: 1)
        #expect(model.marks[1] == .empty && model.mistakes == 0, "2 回目は新しい 1 回目 = × を外すだけ")
        // タップ → 同じマスのタップは今までどおりダブルタップで猫。
        clock.advance(by: .seconds(1))
        model.tap(cell: 1)
        clock.advance(by: .milliseconds(100))
        model.tap(cell: 1)
        #expect(model.marks[1] == .cat)
    }

    @Test("終局後・コンティニューの提案中は効かない")
    func frozenIgnoresSlide() {
        let model = makeModel()
        for cell in sample.solutionCells { model.findCat(cell: cell) }
        #expect(model.isOver)
        model.beginCrossDrag(cell: 2)
        model.dragCross(to: 3)
        model.endCrossDrag()
        #expect(model.marks[2] == .empty && model.marks[3] == .empty)
    }

    @Test("スライド中にやり直し・戻すで盤が変わったら、古いスライドは捨てる")
    func boardChangeDiscardsDrag() {
        let model = makeModel()
        model.beginCrossDrag(cell: 4)
        model.dragCross(to: 5)
        model.reset()
        model.dragCross(to: 6)
        model.endCrossDrag()
        #expect(model.marks.allSatisfy { $0 == .empty }, "やり直しのあとの古いスライドは盤に作用しない")
    }
}
