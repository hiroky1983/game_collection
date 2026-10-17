import Testing
@testable import GameHanoi

@Suite("ハノイの塔のロジック")
struct HanoiLogicTests {

    @Test("始めの盤は左の柱に大きい順に積まれ、正しい盤で、まだ揃っていない", arguments: HanoiLogic.diskRange)
    func initialBoard(disks: Int) {
        let pegs = HanoiLogic.initial(disks: disks)
        #expect(pegs[0] == Array((1...disks).reversed()))
        #expect(pegs[1].isEmpty && pegs[2].isEmpty)
        #expect(HanoiLogic.isValid(pegs, disks: disks))
        #expect(!HanoiLogic.isSolved(pegs, disks: disks))
    }

    @Test("どの枚数でも解けて、最少手順は 2ⁿ−1 手（合法手だけで右の柱に揃う）", arguments: HanoiLogic.diskRange)
    func everyBoardIsSolvableInMinimumMoves(disks: Int) throws {
        var pegs = HanoiLogic.initial(disks: disks)
        let steps = HanoiLogic.solution(disks: disks)
        #expect(steps.count == HanoiLogic.minimumMoves(disks: disks))
        #expect(steps.count == (1 << disks) - 1)
        for (index, step) in steps.enumerated() {
            #expect(!HanoiLogic.isSolved(pegs, disks: disks), "\(index) 手目より前に揃ってしまった")
            pegs = try #require(HanoiLogic.moving(pegs, from: step.from, to: step.to), "\(index) 手目が反則")
            #expect(HanoiLogic.isValid(pegs, disks: disks), "\(index) 手目のあと盤が壊れた")
        }
        #expect(HanoiLogic.isSolved(pegs, disks: disks))
    }

    @Test("最少手数は 3 枚で 7 手、7 枚で 127 手")
    func minimumMoves() {
        #expect(HanoiLogic.minimumMoves(disks: 3) == 7)
        #expect(HanoiLogic.minimumMoves(disks: 4) == 15)
        #expect(HanoiLogic.minimumMoves(disks: 7) == 127)
    }

    @Test("小さい円盤の上に大きい円盤は置けず、理由を返す")
    func largerOnSmallerIsRejected() {
        let pegs: [[Int]] = [[3], [2], [1]]
        #expect(HanoiLogic.rejection(pegs, from: 1, to: 2) == .largerOnSmaller)
        #expect(HanoiLogic.moving(pegs, from: 1, to: 2) == nil)
        #expect(HanoiLogic.rejection(pegs, from: 0, to: 1) == .largerOnSmaller)
        // 小さいほうを大きいほうの上へは置ける。空の柱へも置ける。
        #expect(HanoiLogic.moving(pegs, from: 2, to: 1) == [[3], [2, 1], []])
        #expect(HanoiLogic.moving([[3, 2], [], [1]], from: 0, to: 1) == [[3], [2], [1]])
    }

    @Test("空の柱からは取れない・同じ柱や範囲外へは動かさない")
    func invalidMoves() {
        let pegs = HanoiLogic.initial(disks: 3)
        #expect(HanoiLogic.rejection(pegs, from: 1, to: 2) == .emptySource)
        #expect(HanoiLogic.moving(pegs, from: 1, to: 2) == nil)
        #expect(HanoiLogic.moving(pegs, from: 0, to: 0) == nil)
        #expect(HanoiLogic.moving(pegs, from: 0, to: 3) == nil)
        #expect(HanoiLogic.moving(pegs, from: -1, to: 1) == nil)
    }

    @Test("壊れた盤（枚数違い・重複・大きいものが上）は正しい盤と見なさない")
    func invalidBoards() {
        #expect(!HanoiLogic.isValid([[3, 2], [], []], disks: 3))
        #expect(!HanoiLogic.isValid([[3, 2, 2], [], []], disks: 3))
        #expect(!HanoiLogic.isValid([[2, 3], [1], []], disks: 3))
        #expect(!HanoiLogic.isValid([[3, 2, 1], []], disks: 3))
        #expect(!HanoiLogic.isValid(HanoiLogic.initial(disks: 2), disks: 2), "範囲外の枚数")
        #expect(HanoiLogic.isValid([[3], [2, 1], []], disks: 3))
    }

    @Test("揃ったのは右の柱に全部が大きい順に並んだときだけ（まんなかでは揃わない）")
    func solvedOnlyOnRightPeg() {
        #expect(HanoiLogic.isSolved([[], [], [3, 2, 1]], disks: 3))
        #expect(!HanoiLogic.isSolved([[], [3, 2, 1], []], disks: 3))
        #expect(!HanoiLogic.isSolved([[1], [], [3, 2]], disks: 3))
    }
}
