import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GameShogi
import CoreTestSupport

/// 壊れた中断データで起動が落ちない（#1384。チェス #520 と同じ方針）。
@Suite("将棋の壊れた中断データ")
@MainActor
struct ShogiBrokenSnapshotTests {
    private func model(sfen: String = Position.startSFEN, moves: [String], reviewPly: Int? = nil)
        throws -> (ShogiGameModel, MemorySnapshotStore)
    {
        let store = MemorySnapshotStore()
        try store.save(
            ShogiSnapshot(
                initialSfen: sfen, moves: moves, phase: .playing, reviewPly: reviewPly,
                sente: .human, gote: .human, aiLevel: nil, startedAt: Date(), undoUsed: false),
            for: "shogi")
        return (ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService())), store)
    }

    @Test("移動元が空きマスの手で落ちず、その手の手前で切り詰める")
    func illegalMoveTruncates() throws {
        // 7g7f（合法）の次に、駒の無い 5e5d。
        let (m, _) = try model(moves: ["7g7f", "5e5d", "8c8d"])
        #expect(m.moves.count == 1)
    }

    @Test("持っていない駒を打つ手でも落ちない")
    func dropWithoutHandPieceTruncates() throws {
        let (m, _) = try model(moves: ["P*5e"])
        #expect(m.moves.isEmpty)
    }

    @Test("読めない初期局面は初形に倒す")
    func unreadableSfenFallsBackToStart() throws {
        let (m, _) = try model(sfen: "garbage", moves: ["7g7f"])
        #expect(m.moves.count == 1)
        #expect(m.initialSFEN == Position.startSFEN)
    }

    @Test("検討位置は手数の範囲に丸める")
    func reviewPlyIsClamped() throws {
        let (m, _) = try model(moves: ["7g7f"], reviewPly: 99)
        #expect(m.reviewPly == 1)
    }
}
