import Testing
import Core
import CoreTestSupport

@MainActor
@Suite("GameStopwatch（#1857）")
struct GameStopwatchTests {
    private func makeStopwatch(_ manual: ManualClock, persistInterval: Int = 30) -> GameStopwatch {
        let stopwatch = GameStopwatch(persistInterval: persistInterval)
        stopwatch.now = manual.now
        return stopwatch
    }

    @Test("数えていないときは進めない・止めたあとも進めない")
    func advanceOnlyWhileRunning() {
        let manual = ManualClock()
        let stopwatch = makeStopwatch(manual)
        #expect(stopwatch.advance(from: 0) == nil)

        stopwatch.start(base: 0) {}
        manual.advance(by: .seconds(5))
        #expect(stopwatch.advance(from: 0)?.seconds == 5)

        stopwatch.stop()
        #expect(!stopwatch.isRunning)
        manual.advance(by: .seconds(5))
        #expect(stopwatch.advance(from: 5) == nil)
    }

    @Test("再開は渡した秒数の続きから数える")
    func restartContinuesFromBase() {
        let manual = ManualClock()
        let stopwatch = makeStopwatch(manual)
        stopwatch.start(base: 100) {}
        manual.advance(by: .seconds(3))
        #expect(stopwatch.advance(from: 100)?.seconds == 103)
        stopwatch.stop()
        manual.advance(by: .seconds(500))
        stopwatch.start(base: 103) {}
        manual.advance(by: .seconds(2))
        #expect(stopwatch.advance(from: 103)?.seconds == 105)
        stopwatch.stop()
    }

    @Test("保存間隔の境目を跨いだときだけ知らせる")
    func reportsPersistBoundary() {
        let manual = ManualClock()
        let stopwatch = makeStopwatch(manual, persistInterval: 30)
        stopwatch.start(base: 0) {}
        defer { stopwatch.stop() }
        manual.advance(by: .seconds(29))
        #expect(stopwatch.advance(from: 0)?.crossedPersistBoundary == false)
        manual.advance(by: .seconds(1))
        #expect(stopwatch.advance(from: 29)?.crossedPersistBoundary == true)
        manual.advance(by: .seconds(40))   // 1 回の同期で複数の境目を跨いでも 1 回の合図
        #expect(stopwatch.advance(from: 30)?.crossedPersistBoundary == true)
    }

    @Test("モデルが先に進めた秒（テスト用の tick など）より戻さない")
    func neverGoesBackwards() {
        let manual = ManualClock()
        let stopwatch = makeStopwatch(manual)
        stopwatch.start(base: 0) {}
        defer { stopwatch.stop() }
        manual.advance(by: .seconds(2))
        #expect(stopwatch.advance(from: 50)?.seconds == 50)
    }

    @Test("startIfStopped は動いているときは張り直さない")
    func startIfStoppedKeepsRunningClock() {
        let manual = ManualClock()
        let stopwatch = makeStopwatch(manual)
        stopwatch.start(base: 0) {}
        defer { stopwatch.stop() }
        manual.advance(by: .seconds(4))
        stopwatch.startIfStopped(base: 0) {}
        #expect(stopwatch.advance(from: 0)?.seconds == 4)
    }
}
