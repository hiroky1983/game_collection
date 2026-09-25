import Testing
import Foundation
import Core
@testable import GameGomoku
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースで保存型を組み立て、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("五目並べ: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct GomokuSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"humanSide":0,"aiLevel":2,"forbiddenMoves":true,"resigned":false,"currentStone":1,"cells":[null\#
        ,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,\#
        null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,n\#
        ull,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,nu\#
        ll,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,nul\#
        l,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null\#
        ,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,0,1,null,null,null,n\#
        ull,null,null,null,null,null,null,null,null,null,null,0,null,null,null,null,null,null,null,null,\#
        null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,n\#
        ull,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,nu\#
        ll,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,nul\#
        l,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null\#
        ,null,null,null,null,null,null,null,null,null,null,null],"undoUsed":true,"hintsUsed":1,"moveHist\#
        ory":[{"row":7,"stone":0,"col":7},{"row":7,"stone":1,"col":8},{"row":8,"stone":0,"col":8}],"star\#
        tedAt":780000000}
        """#

    @Test("v1.1.6 の中断データを読み、盤・手番・禁手設定・ヒント使用数が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(GomokuSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.moveHistory?.count == 3)
        #expect(snap.forbiddenMoves == true)
        #expect(snap.hintsUsed == 1)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "gomoku")
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.board[7, 7] == .black)
        #expect(model.board[7, 8] == .white)
        #expect(model.board[8, 8] == .black)
        #expect(model.moveCount == 3)
        #expect(model.currentStone == .white)
        #expect(model.forbiddenMovesEnabled)
        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1)
    }
}
