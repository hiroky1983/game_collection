import Testing
import Core
import CoreTestSupport

@Suite("ElapsedClock")
struct ElapsedClockTests {
    @Test("実時間で 600 秒たてば 600 秒になる（1 秒ずつ眠った遅れを積み上げない）")
    func sixHundredSecondsOfWallTime() {
        let manual = ManualClock()
        let clock = ElapsedClock(now: manual.now)
        // 1 秒のつもりで眠ったのに毎周 20ms 遅れて戻る、を 600 周ぶん。積み上げ方式なら 600 秒に届かない。
        for _ in 0..<600 { manual.advance(by: .milliseconds(1020)) }
        #expect(clock.seconds == 612)
        let exact = ManualClock()
        let exactClock = ElapsedClock(now: exact.now)
        exact.advance(by: .seconds(600))
        #expect(exactClock.seconds == 600)
    }

    @Test("base は続きの秒数として足され、端数は切り捨てる")
    func baseAndTruncation() {
        let manual = ManualClock()
        let clock = ElapsedClock(base: 100, now: manual.now)
        manual.advance(by: .milliseconds(2999))
        #expect(clock.seconds == 102)
    }

    @Test("負の base は 0 に丸める")
    func negativeBase() {
        let manual = ManualClock()
        #expect(ElapsedClock(base: -5, now: manual.now).seconds == 0)
    }

    @Test("次の整数秒までの待ち時間は開始からの端数で決まる")
    func untilNextSecond() {
        let manual = ManualClock()
        let clock = ElapsedClock(now: manual.now)
        #expect(clock.untilNextSecond == .seconds(1))
        manual.advance(by: .milliseconds(1250))
        #expect(clock.untilNextSecond == .milliseconds(750))
    }
}
