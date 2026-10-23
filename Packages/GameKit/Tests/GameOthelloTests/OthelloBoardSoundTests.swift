import Testing
import Foundation
import Core
@testable import GameOthello
import CoreTestSupport

// 自分が石を置くとオセロの石の音が鳴る（#2767）。返る石は鳴らさない。

@MainActor
@Suite("オセロ: 石を置く音（#2767）")
struct OthelloBoardSoundTests {
    @Test("自分が置くと石の音が 1 回だけ（返る石の分は鳴らさない）")
    func humanDiscSounds() {
        let spy = SpyFeedbackService()
        let model = OthelloModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        )
        model.newGame(humanSide: .black, aiLevel: 1)
        model.tap(row: 2, col: 3)   // 初期配置で黒が打てる 4 手のひとつ
        #expect(spy.impacts == [.board(.othelloDisc)])
    }
}
