import Testing
import Foundation
import Core
@testable import GameGomoku
import CoreTestSupport

// 五目並べは碁石なので囲碁と同じ音（#2767）。CPU の着手は無音のまま。

@MainActor
@Suite("五目並べ: 石を置く音（#2767）")
struct GomokuBoardSoundTests {
    @Test("自分が打つと碁石の音")
    func humanStoneSounds() {
        let spy = SpyFeedbackService()
        let model = GomokuModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy),
            defaults: UserDefaults(suiteName: "gomoku-board-sound")!
        )
        model.newGame(humanSide: .black, aiLevel: 1)
        model.tap(row: 7, col: 7)
        #expect(spy.impacts == [.board(.goStone)])
    }
}
