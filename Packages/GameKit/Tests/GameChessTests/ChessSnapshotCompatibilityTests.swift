import Testing
import Foundation
import Core
@testable import GameChess
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("チェス: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct ChessSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"initialFen":"rnbqkbnr\/pppppppp\/8\/8\/8\/8\/PPPPPPPP\/RNBQKBNR w KQkq - 0 1","hintsUsed":1,"a\#
        iLevel":2,"undoUsed":true,"black":"ai","moves":["e2e4","e7e5","g1f3"],"startedAt":780000000,"pha\#
        se":"playing","resigned":false,"white":"human"}
        """#

    @Test("v1.1.6 の中断データを読み、棋譜・強さ・待った/ヒントの使用状況が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(ChessSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.moves == ["e2e4", "e7e5", "g1f3"])
        #expect(snap.aiLevel == 2)
        #expect(snap.hintsUsed == 1)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "chess")
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.moves.map(\.uci) == ["e2e4", "e7e5", "g1f3"])
        #expect(model.phase == .playing)
        #expect(model.aiLevel == 2)
        #expect(model.undoUsed)
        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1)
    }
}
