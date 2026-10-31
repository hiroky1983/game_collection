import Testing
import Foundation
import Core
@testable import GameGo
import CoreTestSupport

/// 盤タップの「仮置き → 確定」（#3149・五目並べ #2297 の横展開）。
@MainActor
@Suite("囲碁 仮置きの2段タップ（#3149）")
struct GoPendingMoveTests {

    private func makeModel(confirms: Bool? = nil, boardSize: GoBoardSize = .thirteen) -> (GoModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "GoPendingMoveTests-\(UUID().uuidString)")!
        if let confirms { defaults.set(confirms, forKey: GoModel.confirmsPlacementKey) }
        let model = GoModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), defaults: defaults)
        model.newGame(humanSide: .black, level: .easy, handicap: 0, boardSize: boardSize)
        return (model, defaults)
    }

    @Test("既定は2段: 1回目は仮置きだけで石は置かれない")
    func firstTapOnlyAims() {
        let (model, _) = makeModel()
        #expect(model.confirmsPlacement)
        model.tapOnBoard(row: 6, col: 6)
        #expect(model.pendingPoint == GoPoint(row: 6, col: 6))
        #expect(model.board.stone(row: 6, col: 6) == nil)
        #expect(model.moveCount == 0)
    }

    @Test("別の交点をタップすると仮置きが移る")
    func tapElsewhereMovesAim() {
        let (model, _) = makeModel()
        model.tapOnBoard(row: 6, col: 6)
        model.tapOnBoard(row: 6, col: 7)
        #expect(model.pendingPoint == GoPoint(row: 6, col: 7))
        #expect(model.moveCount == 0)
    }

    @Test("同じ交点の再タップで確定し、仮置きは消える")
    func secondTapCommits() {
        let (model, _) = makeModel()
        model.tapOnBoard(row: 6, col: 6)
        model.tapOnBoard(row: 6, col: 6)
        #expect(model.board.stone(row: 6, col: 6) == .black)
        #expect(model.moveCount == 1)
        #expect(model.pendingPoint == nil)
    }

    @Test("打てない交点は仮置きにならず、従来どおり拒否される")
    func occupiedIsRejected() {
        let (model, _) = makeModel(confirms: false)
        model.tap(row: 6, col: 6)
        model.apply(.play(row: 0, col: 0))   // CPU の応手を指定する
        model.setConfirmsPlacement(true)
        let before = model.rejectedTapCount
        model.tapOnBoard(row: 6, col: 6)
        #expect(model.pendingPoint == nil)
        #expect(model.rejectedTapCount == before + 1)
    }

    @Test("仮置きは着手・待った・新規対局・設定の切り替えで消える")
    func pendingIsDropped() {
        let (model, _) = makeModel()
        model.tapOnBoard(row: 6, col: 6); model.tapOnBoard(row: 6, col: 6)
        model.apply(.play(row: 0, col: 0))
        model.tapOnBoard(row: 3, col: 3)
        #expect(model.pendingPoint != nil)
        model.undoLastExchange()
        #expect(model.pendingPoint == nil)
        model.tapOnBoard(row: 3, col: 3)
        model.newGame(humanSide: .black, level: .easy, handicap: 0, boardSize: .nine)
        #expect(model.pendingPoint == nil)
        model.tapOnBoard(row: 3, col: 3)
        model.setConfirmsPlacement(false)
        #expect(model.pendingPoint == nil)
    }

    @Test("設定が1段なら1タップで確定し、設定は端末内に残る")
    func singleTapWhenDisabled() {
        let (model, defaults) = makeModel()
        model.setConfirmsPlacement(false)
        model.tapOnBoard(row: 6, col: 6)
        #expect(model.board.stone(row: 6, col: 6) == .black)
        #expect(model.pendingPoint == nil)
        #expect(GoModel(services: nil, defaults: defaults).confirmsPlacement == false)
    }

    @Test("VoiceOver 用の tap は仮置きを通さず1回で確定する")
    func directTapStillCommits() {
        let (model, _) = makeModel()
        model.tap(row: 6, col: 6)
        #expect(model.board.stone(row: 6, col: 6) == .black)
    }
}
