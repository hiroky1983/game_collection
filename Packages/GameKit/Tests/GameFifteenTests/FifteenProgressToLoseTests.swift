import Testing
import Core
@testable import GameFifteen

/// 「リセット」の確認を出すかの境目（#1011）。
@MainActor
@Suite("15パズル リセットで失われる進行（#1011）")
struct FifteenProgressToLoseTests {

    /// 揃った盤から空白を 1 手上へ動かした盤（解ける・まだ揃っていない）。
    private static let oneMoveFromSolved = FifteenLogic.slide(FifteenLogic.solved, at: 11)!.tiles

    @Test("手数 0 の盤は失うものが無い")
    func untouchedBoardHasNothingToLose() {
        let model = FifteenModel(services: nil, tiles: Self.oneMoveFromSolved)
        #expect(!model.hasProgressToLose)
    }

    @Test("動かしてまだ揃っていない盤は失う進行がある")
    func movedBoardHasProgress() {
        let model = FifteenModel(services: nil, tiles: Self.oneMoveFromSolved, moves: 3)
        #expect(model.hasProgressToLose)
    }

    @Test("解き終えた盤は失うものが無い")
    func solvedBoardHasNothingToLose() throws {
        let model = FifteenModel(services: nil, tiles: Self.oneMoveFromSolved, moves: 3)
        model.tap(at: 15)
        try #require(model.isSolved)
        #expect(!model.hasProgressToLose)
    }
}
