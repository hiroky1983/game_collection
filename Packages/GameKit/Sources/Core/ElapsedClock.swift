import Foundation

/// 計時のあるゲームの経過秒を、**計時開始からの実経過時間**で求める部品（#1751）。
///
/// 「1 秒スリープ → `elapsedSeconds += 1`」の積み上げは、スリープがメインアクターの待ちぶん毎周遅れて
/// 戻るため実時間より短く数え、クリアタイムと自己ベストが速く記録されていた。
/// 一時停止・広告・背面の区間は、モデルがタイマーを止めて再開するときに新しい `ElapsedClock` を
/// 作り直す（`base` に止まる前の経過秒を渡す）ことで、従来どおり数えない。
public struct ElapsedClock: Sendable {
    public typealias Now = @Sendable () -> ContinuousClock.Instant

    private let base: Int
    private let start: ContinuousClock.Instant
    private let now: Now

    /// - Parameters:
    ///   - base: 計時を始める時点の経過秒（中断データの復元・再開のときは続きの秒数）。
    ///   - now: 現在時刻の取り出し口。テストは差し替えて時間を進める。
    public init(base: Int = 0, now: @escaping Now = { ContinuousClock.now }) {
        self.base = max(0, base)
        self.now = now
        self.start = now()
    }

    private var elapsed: Duration { max(.zero, now() - start) }

    /// 計時開始からの経過秒（`base` を含む・端数は切り捨て）。
    public var seconds: Int { base + Int(elapsed.components.seconds) }

    /// 次に整数秒を跨ぐまでの待ち時間。毎周 1 秒ずつ眠ると復帰の遅れが積もって表示が秒を飛ばすので、
    /// 開始から数えた秒の境目に合わせて眠る。
    public var untilNextSecond: Duration {
        let fraction = Duration(secondsComponent: 0, attosecondsComponent: elapsed.components.attoseconds)
        return .seconds(1) - fraction
    }
}
