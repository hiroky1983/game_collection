import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 「新しいゲーム」で捨てた局の `quit` はその場で出る（#3226）。次の最初のタップまで遅れると、
/// 新しい盤を放置した時間が旧プレイの `duration_sec` に混ざる。
@MainActor
@Suite("Minesweeper 新しいゲームで捨てた局の quit（#3226）")
struct MinesweeperAbandonQuitTests {
    private final class Clock {
        var seconds: TimeInterval = 0
        var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    }

    private func makeModel(_ clock: Clock) -> (MinesweeperModel, GameServices, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["minesweeper"], now: { clock.now })
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (MinesweeperModel(services: services), services, spy)
    }

    @Test("放置しても quit の duration_sec は旧プレイの実プレイ時間")
    func quitDurationExcludesIdleAfterNewGame() {
        let clock = Clock()
        let (model, services, spy) = makeModel(clock)
        model.tap(row: 4, col: 4)
        clock.seconds += 30
        model.newGame(rows: 9, cols: 9, mines: 10)
        #expect(spy.quits.map(\.durationSec) == [30], "新しいゲームを押した時点で quit が出る")

        clock.seconds += 600   // 新しい盤を前面のまま放置
        model.tap(row: 4, col: 4)
        #expect(spy.quits.map(\.durationSec) == [30], "最初のタップで旧プレイの quit は増えない")
        #expect(spy.starts.count == 2)
    }

    @Test("新しいゲームのあと何もせずハブへ戻っても game_end は二重に出ない")
    func leavingAfterNewGameDoesNotDoubleEnd() {
        let clock = Clock()
        let (model, services, spy) = makeModel(clock)
        model.tap(row: 4, col: 4)
        clock.seconds += 20
        model.newGame(rows: 9, cols: 9, mines: 10)
        services.gameDidLeave(gameID: "minesweeper")
        #expect(spy.ends(of: "minesweeper") == 1)
    }

    @Test("1手も指していない盤を捨てても quit は出ない")
    func untouchedBoardSendsNothing() {
        let clock = Clock()
        let (model, services, spy) = makeModel(clock)
        model.newGame(rows: 9, cols: 9, mines: 10)
        #expect(spy.ends(of: "minesweeper") == 0)
    }
}
