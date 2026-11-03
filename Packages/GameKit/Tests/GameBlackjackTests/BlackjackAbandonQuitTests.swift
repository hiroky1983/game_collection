import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport

/// 勝負を捨てて最初に戻した時点で、旧プレイの `quit` を出す（#3226）。
@MainActor
@Suite("ブラックジャック 勝負を捨てた局の quit（#3226）")
struct BlackjackAbandonQuitTests {
    private final class Clock {
        var seconds: TimeInterval = 0
        var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    }

    private func makeModel(_ clock: Clock) -> (BlackjackModel, GameServices, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["blackjack"], now: { clock.now })
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (BlackjackModel(services: services, seed: 7), services, spy)
    }

    @Test("放置しても quit の duration_sec は旧プレイの実プレイ時間")
    func quitDurationExcludesIdleAfterRestart() {
        let clock = Clock()
        let (model, services, spy) = makeModel(clock)
        model.deal()
        clock.seconds += 30
        model.restartMatch()
        #expect(spy.quits.map(\.durationSec) == [30], "やり直した時点で quit が出る")

        clock.seconds += 600
        model.deal()
        #expect(spy.quits.map(\.durationSec) == [30], "次の配りで旧プレイの quit は増えない")
        #expect(spy.starts.count == 2)
    }

    @Test("やり直したあと何もせずハブへ戻っても game_end は二重に出ない")
    func leavingAfterRestartDoesNotDoubleEnd() {
        let clock = Clock()
        let (model, services, spy) = makeModel(clock)
        model.deal()
        clock.seconds += 20
        model.restartMatch()
        services.gameDidLeave(gameID: "blackjack")
        #expect(spy.ends(of: "blackjack") == 1)
    }
}
