import Testing
import Foundation
import Core
@testable import GameSudoku
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("数独: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct SudokuSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"hintsUsed":0,"given":[false,true,false,false,true,false,true,true,true,true,false,true,true,fa\#
        lse,true,false,true,false,false,true,true,false,true,false,false,true,true,false,true,true,false\#
        ,true,false,false,true,true,false,false,false,false,false,true,true,true,true,true,false,true,fa\#
        lse,true,false,false,true,false,true,false,true,false,true,true,true,false,true,false,true,true,\#
        true,false,true,true,true,false,true,false,true,true,true,false,true,false,true],"hintedCells":[\#
        ],"continueUsed":false,"board":[8,4,0,0,6,0,9,2,7,7,0,6,8,0,3,0,1,0,0,5,2,0,7,0,0,6,3,0,7,8,0,3,\#
        0,0,5,4,0,0,0,0,0,9,7,3,2,2,0,1,0,4,0,0,8,0,6,0,4,0,5,7,2,0,1,0,2,9,4,0,6,3,7,0,3,0,7,2,9,0,5,0,\#
        6],"mistakes":0,"elapsedSeconds":0,"difficulty":"easy","notes":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,\#
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,\#
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"solution":[8,4,3,5,6,1,9,2,7,7,9,6,8,2,3,4,1,5,1,5,2,9,7,4,8\#
        ,6,3,9,7,8,6,3,2,1,5,4,4,6,5,1,8,9,7,3,2,2,3,1,7,4,5,6,8,9,6,8,4,3,5,7,2,9,1,5,2,9,4,1,6,3,7,8,3\#
        ,1,7,2,9,8,5,4,6]}
        """#

    @Test("v1.1.6 の中断データを読み、盤・難易度・入れた数字が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(SudokuSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.difficulty == .easy)
        #expect(snap.board[0] == 8)
        #expect(!snap.given[0])

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "sudoku")
        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.pauseTimer()
        // 検証に落ちると中断データは消され `.idle` のまま
        #expect(model.state == .playing)
        #expect(model.difficulty == .easy)
        #expect(model.board == snap.board)
        #expect(model.board[0] == 8)
    }
}
