import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 思考中に画面を離れる（#1621）。`Task.detached { … }.value` は親がキャンセルされても走り切るので、
/// 戻ったあとに `commit` を通すと、離脱後に CPU の着手（決着なら敗北の記録）が確定してしまう。
@MainActor
@Suite("五目並べ 思考中のキャンセル（#1621）")
struct GomokuCancelDuringThinkingTests {
    @Test("思考中にキャンセルされたら着手しない")
    func cancelledThinkingDoesNotPlaceStone() async throws {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 1) // CPU=黒(先手)
        try #require(model.isAITurn)

        let task = Task { await model.performAIMoveIfNeeded() }
        task.cancel()
        await task.value

        #expect(model.moveCount == 0)
        #expect(model.lastMove == nil)
        #expect(model.isThinking == false)
        #expect(model.isAITurn)   // 手番は CPU のまま（戻ってきたら再開できる）
    }

    @Test("対照: キャンセルしなければ着手する")
    func uncancelledThinkingPlacesStone() async throws {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 1)
        try #require(model.isAITurn)

        await model.performAIMoveIfNeeded()

        #expect(model.moveCount == 1)
    }
}
