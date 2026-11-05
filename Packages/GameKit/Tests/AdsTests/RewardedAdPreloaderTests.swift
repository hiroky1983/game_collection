import Testing
import Foundation
@testable import Core

/// リワード広告の先読みの再試行と打ち切り（#3341）。実際の `RewardedAd` は端末側なので、読み込みの口を
/// 差し替えて失敗させる。広告の表示はしない。
@MainActor
@Suite("リワード広告の先読み（再試行・打ち切り）")
struct RewardedAdPreloaderTests {
    private struct LoadFailure: Error {}

    /// 読み込みを回数ぶん失敗させてから成功させる口と、待った間隔の記録。
    private final class Harness {
        var loads = 0
        var slept: [Duration] = []
        let failures: Int
        init(failures: Int) { self.failures = failures }
    }

    private func makePreloader(_ h: Harness, delays: [Duration] = [.seconds(5), .seconds(15), .seconds(45)])
        -> RewardedAdPreloader<String> {
        RewardedAdPreloader<String>(
            retryDelays: delays, loadTimeout: nil,
            sleep: { h.slept.append($0) },
            load: {
                h.loads += 1
                if h.loads <= h.failures { throw LoadFailure() }
                return "ad\(h.loads)"
            }
        )
    }

    private func settle(_ p: RewardedAdPreloader<String>) async {
        while p.isPreparing { await Task.yield() }
    }

    @Test("先読みが失敗しても 5・15・45 秒と間を空けて読み直し、使える広告が預かれる")
    func retriesWithGrowingDelays() async {
        let h = Harness(failures: 3)
        let p = makePreloader(h)
        p.start()
        await settle(p)
        #expect(h.loads == 4 && h.slept == [.seconds(5), .seconds(15), .seconds(45)])
        #expect(p.isReady)
        #expect(p.take() == "ad4")
        #expect(!p.isReady)
    }

    @Test("再試行が尽きたら諦める。次の start() でまた最初から読む")
    func givesUpThenStartsAgain() async {
        let h = Harness(failures: 4)
        let p = makePreloader(h)
        p.start()
        await settle(p)
        #expect(h.loads == 4 && !p.isReady && !p.isPreparing)
        p.start()
        await settle(p)
        #expect(h.loads == 5 && p.isReady)
    }

    @Test("預かっている・先読み中なら start() は二重に読まない")
    func startIsIdempotent() async {
        let h = Harness(failures: 0)
        let p = makePreloader(h)
        p.start()
        p.start()
        await settle(p)
        p.start()
        await settle(p)
        #expect(h.loads == 1)
    }

    @Test("直前に失敗した直後の start(afterFailure:) は、最初の間隔を待ってから読む")
    func afterFailureWaitsFirst() async {
        let h = Harness(failures: 0)
        let p = makePreloader(h)
        p.start(afterFailure: true)
        await settle(p)
        #expect(h.slept == [.seconds(5)] && h.loads == 1 && p.isReady)
    }

    @Test("再試行を止めると、待ちのあとに読み直さない")
    func cancelRetriesStopsChain() async {
        let h = Harness(failures: 10)
        let p = RewardedAdPreloader<String>(
            retryDelays: [.seconds(5), .seconds(15)], loadTimeout: nil,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            load: { h.loads += 1; throw LoadFailure() }
        )
        p.start()
        while h.loads == 0 { await Task.yield() }
        p.cancelRetries()
        #expect(!p.isPreparing)
        for _ in 0..<50 { await Task.yield() }
        #expect(h.loads == 1)
    }

    @Test("応答が返らない読み込みは打ち切られ、タップの待ちも戻る（押せなくならない）")
    func hungLoadTimesOut() async {
        // SDK が cancel に応えず返ってこない状況。テストの最後まで resume しない。
        var pending: [CheckedContinuation<String, Never>] = []
        let p = RewardedAdPreloader<String>(
            retryDelays: [], loadTimeout: .milliseconds(50),
            load: { await withCheckedContinuation { pending.append($0) } }
        )
        p.start()
        await p.awaitCurrentAttempt()
        await settle(p)
        #expect(!p.isReady && !p.isPreparing)
        let loaded = await p.loadNow()
        #expect(loaded == nil)
        pending.forEach { $0.resume(returning: "late") }
    }

    @Test("再試行の待ち時間中のタップは待たされず、その場で読める")
    func tapDuringBackoffDoesNotWait() async {
        let h = Harness(failures: 1)
        let p = RewardedAdPreloader<String>(
            retryDelays: [.seconds(5)], loadTimeout: nil,
            sleep: { _ in try await Task.sleep(for: .seconds(60)) },
            load: {
                h.loads += 1
                if h.loads <= h.failures { throw LoadFailure() }
                return "tap"
            }
        )
        p.start()
        while h.loads == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        await p.awaitCurrentAttempt()   // 待ち時間中なので即座に戻る
        #expect(!p.isReady)
        p.cancelRetries()
        #expect(await p.loadNow() == "tap")
    }

    @Test("失効した広告は取り出せず、isReady も偽になる")
    func expiredAdIsNotReady() async {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let p = RewardedAdPreloader<String>(
            lifetime: 60, retryDelays: [], loadTimeout: nil,
            now: { clock }, load: { "ad" }
        )
        p.start()
        await settle(p)
        #expect(p.isReady)
        clock = clock.addingTimeInterval(61)
        #expect(!p.isReady && p.take() == nil)
    }
}
