import Testing
import Foundation
import Core
@testable import GameShogi
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("将棋: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct ShogiSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"gote":"ai","resigned":false,"moves":["7g7f","3c3d","8h2b+"],"initialSfen":"lnsgkgsnl\/1r5b1\/p\#
        pppppppp\/9\/9\/9\/PPPPPPPPP\/1B5R1\/LNSGKGSNL b - 1","sente":"human","aiLevel":2,"undoUsed":fal\#
        se,"phase":"playing","startedAt":780000000,"hintsUsed":2}
        """#

    @Test("v1.1.6 の中断データを読み、棋譜・強さ・ヒント使用数が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(ShogiSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.moves == ["7g7f", "3c3d", "8h2b+"])
        #expect(snap.initialSfen == Position.startSFEN)
        #expect(snap.hintsUsed == 2)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "shogi")
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.moves.map(\.usi) == ["7g7f", "3c3d", "8h2b+"])
        #expect(model.phase == .playing)
        #expect(!model.gameOver)
        #expect(model.aiLevel == 2)
        #expect(model.hintsRemaining == BoardHintBudget.perGame - 2)
    }
}
