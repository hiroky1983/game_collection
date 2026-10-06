import Core
import Foundation

/// 手で進める時計（#1751）。`ElapsedClock` の `now` に差し込み、実時間を待たずに経過秒を検証する。
public final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    public init() {}

    /// `ElapsedClock.Now` として渡す。
    public var now: ElapsedClock.Now {
        { [self] in lock.withLock { instant } }
    }

    public func advance(by duration: Duration) {
        lock.withLock { instant = instant.advanced(by: duration) }
    }
}
