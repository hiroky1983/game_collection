import Testing
import Foundation
import Core
@testable import GameChess
import CoreTestSupport

// 自分の着手で木の駒の音が鳴る（#2767）。CPU の着手は無音のまま。

@MainActor
@Suite("チェス: 駒を置く音（#2767）")
struct ChessBoardSoundTests {
    @Test("自分が指すと駒の音、CPU の着手は無音")
    func humanMoveSounds() {
        let spy = SpyFeedbackService()
        let model = ChessGameModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        )
        model.apply(ChessMove.fromUCI("e2e4")!)
        #expect(spy.impacts == [.board(.chessPiece)])
        model.apply(ChessMove.fromUCI("e7e5")!)   // CPU（黒）
        #expect(spy.impacts == [.board(.chessPiece)], "CPU の着手は無音のまま")
    }
}
