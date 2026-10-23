import Testing
import Foundation
import Core
@testable import GameShogi
import CoreTestSupport

// 自分の着手で本物の駒の音が鳴る（#2767）。CPU の着手は無音のまま。

@MainActor
@Suite("将棋: 駒を指す音（#2767）")
struct ShogiBoardSoundTests {
    private func makeModel(_ spy: SpyFeedbackService) -> ShogiGameModel {
        ShogiGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy))
    }

    private func move(_ from: Substring, _ to: Substring, promote: Bool = false) -> Move {
        .board(from: Sq.fromUSI(from)!, to: Sq.fromUSI(to)!, promote: promote)
    }

    @Test("自分が指すと指す音、駒を取ると取る音。CPU の着手は無音")
    func humanMoveAndCapture() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy)
        model.apply(move("7g", "7f"))
        #expect(spy.impacts == [.board(.shogiPiece)])
        model.apply(move("3c", "3d"))            // CPU（後手）
        #expect(spy.impacts == [.board(.shogiPiece)], "CPU の着手は無音のまま")
        model.apply(move("8h", "2b", promote: true))   // 角で角を取る
        #expect(spy.impacts == [.board(.shogiPiece), .board(.shogiCapture)])
        #expect(spy.notices.isEmpty)
    }

    @Test("同梱ファイルが見つかり、触覚は従来どおり medium")
    func bundledAndHaptic() throws {
        for sound in BoardSound.allCases { _ = try #require(sound.url) }
        #expect(BoardSound.shogiPiece.haptic == .medium)
        #expect(FeedbackImpact.board(.shogiCapture).hasSound)
    }
}
