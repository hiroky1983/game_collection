import Testing
import Core
import CoreTestSupport
@testable import Game2048

/// #2687: スワイプの結果（得点・新しいタイル・動かない方向）が連番付きの結果値としてモデルに残る。
@MainActor
@Suite("2048 スワイプ結果の読み上げ（#2687）")
struct Game2048ResultAnnouncementTests {
    @Test("動かない方向は「その方向には動かせません」で、連続しても連番が進む")
    func blockedDirection() {
        let model = Game2048Model(board: [[2, 4, 8, 16], [4, 8, 16, 32], [8, 16, 32, 64], [16, 32, 64, 0]], score: 0)
        // 左上詰めの盤は左・上へ動かない。
        model.move(.left)
        #expect(model.lastResult?.text == tr("その方向には動かせません"))
        model.move(.up)
        #expect(model.lastResult?.seq == 2)
    }

    @Test("合体した手は得点と新しく出たタイルを読む")
    func mergeAndSpawn() {
        var board = Game2048Logic.emptyBoard()
        board[0] = [2, 2, 0, 0]
        let model = Game2048Model(board: board, score: 0)
        model.move(.left)
        let text = model.lastResult?.text ?? ""
        #expect(text.hasPrefix(tr("得点 +%lld", 4)))
        #expect(text.contains("が出ました"))
        #expect(model.lastResult?.seq == 1)
    }

    @Test("合体が無い手は得点を省く")
    func noScore() {
        #expect(Game2048Accessibility.moveResult(gained: 0, spawned: (row: 1, col: 2, value: 2)) == tr("%1$lld行%2$lld列に %3$lld が出ました", 2, 3, 2))
        #expect(Game2048Accessibility.moveResult(gained: 8, spawned: nil) == tr("得点 +%lld", 8))
    }
}
