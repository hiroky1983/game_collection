import Testing
import Foundation
@testable import GameGomoku

/// 盤タップの「仮置き → 確定」（#2297）。
@MainActor
@Suite("五目並べ 仮置きの2段タップ（#2297）")
struct GomokuPendingMoveTests {

    private func makeModel(confirms: Bool? = nil) -> (GomokuModel, UserDefaults, String) {
        let name = "GomokuPendingMoveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        if let confirms { defaults.set(confirms, forKey: GomokuModel.confirmsPlacementKey) }
        return (GomokuModel(services: nil, defaults: defaults), defaults, name)
    }

    @Test("既定は2段: 1回目は仮置きだけで石は置かれない")
    func firstTapOnlyAims() {
        let (model, _, _) = makeModel()
        #expect(model.confirmsPlacement)
        model.tapOnBoard(row: 7, col: 7)
        #expect(model.pendingPoint == GomokuPoint(row: 7, col: 7))
        #expect(model.board[7, 7] == nil)
        #expect(model.moveCount == 0)
    }

    @Test("別の交点をタップすると仮置きが移る")
    func tapElsewhereMovesAim() {
        let (model, _, _) = makeModel()
        model.tapOnBoard(row: 7, col: 7)
        model.tapOnBoard(row: 7, col: 8)
        #expect(model.pendingPoint == GomokuPoint(row: 7, col: 8))
        #expect(model.moveCount == 0)
    }

    @Test("同じ交点の再タップで確定し、仮置きは消える")
    func secondTapCommits() {
        let (model, _, _) = makeModel()
        model.tapOnBoard(row: 7, col: 7)
        model.tapOnBoard(row: 7, col: 7)
        #expect(model.board[7, 7] == .black)
        #expect(model.moveCount == 1)
        #expect(model.pendingPoint == nil)
    }

    @Test("打てない交点は仮置きにならず、従来どおり拒否される")
    func occupiedIsRejected() async {
        let (model, _, _) = makeModel(confirms: false)
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        model.setConfirmsPlacement(true)
        let before = model.rejectedTapCount
        model.tapOnBoard(row: 7, col: 7)
        #expect(model.pendingPoint == nil)
        #expect(model.lastRejection == .occupied)
        #expect(model.rejectedTapCount == before + 1)
    }

    @Test("VoiceOver 用の tap は仮置きを経ず1操作で確定する")
    func directTapCommitsImmediately() {
        let (model, _, _) = makeModel()
        model.tap(row: 3, col: 3)
        #expect(model.board[3, 3] == .black)
        #expect(model.pendingPoint == nil)
    }

    @Test("設定を1タップにすると即確定し、切り替えで仮置きは捨てられる")
    func oneTapMode() {
        let (model, _, _) = makeModel()
        model.tapOnBoard(row: 5, col: 5)
        model.setConfirmsPlacement(false)
        #expect(model.pendingPoint == nil)
        model.tapOnBoard(row: 6, col: 6)
        #expect(model.board[6, 6] == .black)
    }

    @Test("設定は端末内の固定キーに保存され、次の起動に引き継がれる")
    func settingPersists() {
        let (model, defaults, _) = makeModel()
        model.setConfirmsPlacement(false)
        #expect(GomokuModel(services: nil, defaults: defaults).confirmsPlacement == false)
    }

    @Test("CPU の着手・新規対局・待ったで仮置きは消える")
    func clearedByStateChanges() async throws {
        let (model, _, _) = makeModel()
        model.tapOnBoard(row: 7, col: 7)
        model.tapOnBoard(row: 7, col: 7)           // 確定 → CPU の手番
        model.tapOnBoard(row: 1, col: 1)           // CPU の手番中は拒否（仮置きにならない）
        #expect(model.pendingPoint == nil)
        await model.performAIMoveIfNeeded()
        model.tapOnBoard(row: 0, col: 0)
        #expect(model.pendingPoint != nil)
        model.undoLastExchange()
        #expect(model.pendingPoint == nil)

        model.tapOnBoard(row: 0, col: 0)
        model.newGame()
        #expect(model.pendingPoint == nil)

        model.tapOnBoard(row: 0, col: 0)
        model.resign()
        #expect(model.pendingPoint == nil)
    }
}
