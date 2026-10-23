import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 旗モードの切り替え（#761）。以前は View の `@State` で Model を通らず、手応えが鳴らなかった。
@Suite("マインスイーパー 旗モードの切り替え")
@MainActor
struct MinesweeperFlagModeTests {

    @Test("切り替えるたびに rigid が1回だけ鳴り、盤面には触れない")
    func toggleFiresRigidOnce() {
        let spy = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        #expect(!model.flagMode)

        model.toggleFlagMode()
        #expect(model.flagMode)
        #expect(spy.impacts == [.rigid])
        #expect(spy.notices.isEmpty)

        model.toggleFlagMode()
        #expect(!model.flagMode)
        #expect(spy.impacts == [.rigid, .rigid])
        #expect(model.gameState == .idle, "モードの切り替えだけで局は始まらない")
    }

    @Test("周囲 0 の開いたマスを触っても警告を鳴らさない（#2719）")
    func zeroCellTapIsSilent() {
        let spy = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        model.tap(row: 4, col: 4)   // 初手は周囲も地雷から外すので 0 マスになる
        #expect(model.cells[4][4].isRevealed && model.cells[4][4].adjacentMines == 0)
        spy.reset()

        model.tap(row: 4, col: 4)
        #expect(spy.notices(of: .warning) == 0)
        #expect(model.gameState == .playing)
    }

    @Test("旗数が合わない数字マスの警告は残る（#2719）")
    func numberCellWithoutFlagsStillWarns() {
        let spy = SpyFeedbackService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        model.tap(row: 4, col: 4)
        guard let target = (0..<9).flatMap({ r in (0..<9).map { (r, $0) } })
            .first(where: { model.cells[$0.0][$0.1].isRevealed && model.cells[$0.0][$0.1].adjacentMines > 0 })
        else { return }   // 乱数で数字マスが開かなかった盤は対象外
        spy.reset()

        model.tap(row: target.0, col: target.1)
        #expect(spy.notices(of: .warning) == 1)
    }

    @Test("新規ゲームで旗モードはオフに戻る")
    func newGameResetsFlagMode() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        model.toggleFlagMode()
        #expect(model.flagMode)

        model.newGame(rows: 16, cols: 16, mines: 40)
        #expect(!model.flagMode)
    }

    @Test("旗モードは中断データに書かれ、再開時もオンのまま（#2247）")
    func flagModeIsRestored() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)          // 局を始めて中断データを作る
        model.toggleFlagMode()
        #expect(model.flagMode)
        #expect(model.gameState == .playing)
        #expect(store.exists(for: "minesweeper"))

        let restored = MinesweeperModel(services: services)
        #expect(restored.gameState == .playing, "中断データから復元できている（空振り防止）")
        #expect(restored.flagMode, "旗のつもりのタップがマスを開く操作にならない")
    }
}
