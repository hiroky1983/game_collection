import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

/// 4x4 でない盤の中断データは消して新規開始に倒す（#1384）。
@Suite("2048の壊れた中断データ")
@MainActor
struct Game2048BrokenSnapshotTests {
    private func load(board: [[Int]]) throws -> (Game2048Model, MemorySnapshotStore) {
        let store = MemorySnapshotStore()
        try store.save(
            Game2048Snapshot(board: board, score: 10, continueUsed: false, hasWon: false, showWinPrompt: false),
            for: "2048")
        return (Game2048Model(services: GameServices(snapshots: store, ads: NoopAdService())), store)
    }

    @Test("行が足りない盤で落ちず、新規盤で始める")
    func shortBoardIsDiscarded() throws {
        let (model, _) = try load(board: [[2, 0]])
        #expect(model.board.count == Game2048Logic.size)
        #expect(model.score == 0)
    }

    @Test("列の長さが合わない盤も捨てる")
    func ragged() throws {
        var board = Game2048Logic.emptyBoard()
        board[2] = [2]
        let (model, _) = try load(board: board)
        #expect(model.score == 0)
    }

    @Test("負のタイルを含む盤も捨てる")
    func negativeTile() throws {
        var board = Game2048Logic.emptyBoard()
        board[1][1] = -2
        let (model, _) = try load(board: board)
        #expect(model.score == 0)
    }

    @Test("4x4 の盤は復元する（対照）")
    func validBoardIsKept() throws {
        var board = Game2048Logic.emptyBoard()
        board[0][0] = 4
        let (model, _) = try load(board: board)
        #expect(model.score == 10)
        #expect(model.board[0][0] == 4)
    }
}
