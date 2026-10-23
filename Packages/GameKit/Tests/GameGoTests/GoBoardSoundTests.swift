import Testing
import Foundation
import Core
@testable import GameGo
import CoreTestSupport

// 自分が石を置くと碁石の音が鳴る（#2767）。パスは従来どおり軽い触覚だけ、CPU の着手は無音。

@MainActor
@Suite("囲碁: 石を置く音（#2767）")
struct GoBoardSoundTests {
    @Test("自分が打つと碁石の音、CPU の着手は無音")
    func humanStoneSounds() {
        let spy = SpyFeedbackService()
        let model = GoModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy))
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        #expect(spy.impacts == [.board(.goStone)])
        model.applyMoveForTesting(.play(row: 2, col: 2))   // CPU（白）
        #expect(spy.impacts == [.board(.goStone)], "CPU の着手は無音のまま")
    }
}
