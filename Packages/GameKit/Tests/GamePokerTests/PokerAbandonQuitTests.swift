import Testing
import Foundation
import Core
@testable import GamePoker
import CoreTestSupport

/// 勝負を捨てて最初に戻した時点で、旧プレイの `quit` を出す（#3226）。
@MainActor
@Suite("ポーカー 勝負を捨てた局の quit（#3226）")
struct PokerAbandonQuitTests {
    private final class Clock {
        var seconds: TimeInterval = 0
        var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    }

    @Test("放置しても quit の duration_sec は旧プレイの実プレイ時間で、ハブへ戻っても二重に出ない")
    func quitDurationExcludesIdleAfterRestart() {
        let clock = Clock()
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"], now: { clock.now })
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = PokerModel(services: services)
        model.startGame()
        model.confirmExchange()   // 交換を確定して初めて「指した」盤になる（#500）
        clock.seconds += 30
        model.restartSession()
        #expect(spy.quits.map(\.durationSec) == [30])

        clock.seconds += 600
        services.gameDidLeave(gameID: "poker")
        #expect(spy.ends(of: "poker") == 1)
    }
}
