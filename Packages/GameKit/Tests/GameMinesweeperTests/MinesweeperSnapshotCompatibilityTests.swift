import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// v1.1.6 で保存された中断データを、今の版でも読めて局面が戻ることを固定する（#1390）。
///
/// `v116JSON` はタグ `v1.1.6` のソースでモデルを実際に動かして保存させ、`JSONEncoder` で書き出したバイト列そのもの
/// （長い行は `\#` でつないでいるだけで、中身は 1 行の JSON）。実行時にエンコードして往復させるだけの
/// テストでは、鍵の改名・型の変更に気付けない。読めない JSON は `SnapshotStore.load` が黙って nil を返し、
/// 遊びかけの局が消える。ここが赤くなったら保存形式を戻すか旧形式を読む移行を足すこと
/// （期待値や JSON を今の形式に書き換えて緑にしない）。
@Suite("マインスイーパ: v1.1.6 の中断データ互換（#1390）")
@MainActor
struct MinesweeperSnapshotCompatibilityTests {
    static let v116JSON = #"""
        {"rows":9,"cells":[[{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"flag","is\#
        Flagged":true,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":true,"mark\#
        ":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":false,"isMin\#
        e":false,"mark":"none","isFlagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRevealed\#
        ":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":fals\#
        e,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isConti\#
        nuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines\#
        ":0},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,\#
        "adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":true,"mark":"none","isFl\#
        agged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark\#
        ":"none","isFlagged":false,"adjacentMines":1}],[{"isContinuedMine":false,"isRevealed":false,"isM\#
        ine":false,"mark":"none","isFlagged":false,"adjacentMines":3},{"isContinuedMine":false,"isReveal\#
        ed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":3},{"isContinuedMine":f\#
        alse,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":3},{"isCon\#
        tinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMine\#
        s":1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,\#
        "adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFl\#
        agged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark\#
        ":"none","isFlagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRevealed":false,"isMin\#
        e":false,"mark":"none","isFlagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRevealed\#
        ":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1}],[{"isContinuedMine":f\#
        alse,"isRevealed":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isCon\#
        tinuedMine":false,"isRevealed":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMine\#
        s":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,\#
        "adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFl\#
        agged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark"\#
        :"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine"\#
        :false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":\#
        false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,\#
        "isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinu\#
        edMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":\#
        0}],[{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,\#
        "adjacentMines":2},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isF\#
        lagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark\#
        ":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine\#
        ":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed"\#
        :true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false\#
        ,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinu\#
        edMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1\#
        },{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"ad\#
        jacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlag\#
        ged":false,"adjacentMines":0}],[{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark\#
        ":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMin\#
        e":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed\#
        ":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":fals\#
        e,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContin\#
        uedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":\#
        0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"ad\#
        jacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagg\#
        ed":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"\#
        none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":\#
        false,"mark":"none","isFlagged":false,"adjacentMines":1}],[{"isContinuedMine":false,"isRevealed"\#
        :false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":fals\#
        e,"isRevealed":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContin\#
        uedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":\#
        1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"ad\#
        jacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagg\#
        ed":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"n\#
        one","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine":fa\#
        lse,"mark":"none","isFlagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRevealed":fal\#
        se,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"is\#
        Revealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1}],[{"isContinue\#
        dMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1}\#
        ,{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adja\#
        centMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged\#
        ":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"non\#
        e","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":fals\#
        e,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":true,\#
        "isMine":false,"mark":"none","isFlagged":false,"adjacentMines":2},{"isContinuedMine":false,"isRe\#
        vealed":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine\#
        ":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":2},{"i\#
        sContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacen\#
        tMines":1}],[{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged"\#
        :false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none\#
        ","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"isMine":false\#
        ,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"\#
        isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRev\#
        ealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":1},{"isContinuedMine"\#
        :false,"isRevealed":false,"isMine":true,"mark":"none","isFlagged":false,"adjacentMines":0},{"isC\#
        ontinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":false,"adjacentM\#
        ines":2},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":fa\#
        lse,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none",\#
        "isFlagged":false,"adjacentMines":0}],[{"isContinuedMine":false,"isRevealed":true,"isMine":false\#
        ,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":true,"\#
        isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRev\#
        ealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine"\#
        :false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMines":0},{"isC\#
        ontinuedMine":false,"isRevealed":true,"isMine":false,"mark":"none","isFlagged":false,"adjacentMi\#
        nes":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","isFlagged":fal\#
        se,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"mark":"none","\#
        isFlagged":false,"adjacentMines":1},{"isContinuedMine":false,"isRevealed":false,"isMine":false,"\#
        mark":"none","isFlagged":false,"adjacentMines":0},{"isContinuedMine":false,"isRevealed":false,"i\#
        sMine":false,"mark":"none","isFlagged":false,"adjacentMines":0}]],"cols":9,"continueUsed":false,\#
        "revealedCount":39,"totalMines":10,"flagCount":1,"elapsedSeconds":0}
        """#

    @Test("v1.1.6 の中断データを読み、盤の寸法・開いたマス・旗が戻る")
    func restoresV116Snapshot() throws {
        let snap = try JSONDecoder().decode(MinesweeperSnapshot.self, from: Data(Self.v116JSON.utf8))
        #expect(snap.rows == 9)
        #expect(snap.cols == 9)
        #expect(snap.totalMines == 10)
        #expect(snap.cells[0][0].mark == .flag)

        let store = MemorySnapshotStore()
        store.inject(Data(Self.v116JSON.utf8), for: "minesweeper")
        let model = MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.pauseTimer()
        #expect(model.gameState == .playing)
        #expect(model.revealedCount == 39)
        #expect(model.flagCount == 1)
        #expect(model.cells[0][0].mark == .flag)
        #expect(model.cells.joined().filter(\.isMine).count == 10)
    }
}
