import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

/// #1600: 同じプロセスのまま「続きから」で再開した局の `duration_sec` に、再開後の時間が入る。
@Suite("2048 続きから再開の所要時間（#1600）")
@MainActor
struct Game2048ResumeDurationTests {
    private final class Clock {
        var seconds: TimeInterval = 0
        var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    }

    @Test("休憩 → 復元 → 終局で duration_sec に再開後の時間が入り、休憩中は入らない")
    func durationIncludesTimeAfterResume() {
        let clock = Clock()
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(),
            ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["2048"], now: { clock.now })
        )

        // 新規に開いて 40 秒遊び、ハブへ戻る（休憩）。
        let first = Game2048Model(services: services)
        clock.seconds += 40
        if let direction = Direction.allCases.first(where: { Game2048Logic.slide(first.board, $0).moved }) {
            first.move(direction)
        }
        services.gameDidLeave(gameID: "2048")

        // 休憩 20 秒。アプリは終了せず「続きから」で開く。
        clock.seconds += 20
        services.gameDidOpen(gameID: "2048", source: .hub, position: 1, resume: true)
        let restored = Game2048Model(services: services)
        #expect(spy.starts.count == 1, "再開で game_start は増えない")

        // 300 秒遊んで詰む。
        clock.seconds += 300
        while !restored.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(restored.board, $0).moved
            }) else { break }
            restored.move(direction)
        }
        #expect(restored.gameOver)
        #expect(spy.ends.count == 1)
        #expect(spy.ends.first?.durationSec == 340, "40 + 300 秒。休憩の 20 秒は入らない")
    }
}
