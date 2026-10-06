import Foundation

/// 計時のあるゲームの「動かし方・止め方」を 1 か所にまとめた部品（#1857）。
///
/// ナンプレ・フリーセル・ソリティア・スパイダー・麻雀ソリティア・マインスイーパーが、1 秒ごとのループ
/// （`Task`）・`ElapsedClock` の張り直し・保存の間隔を自前で持っていたものを寄せた。
/// **モデルは `elapsedSeconds` と保存の中身だけを持つ**。いつ決着か・何を保存するかはゲームの責務で、
/// この部品は「数える」「止める」「保存の境目を跨いだと教える」だけを行う。
///
/// ループの `Task` は呼び出し側のクロージャ経由でしかモデルに触れない。クロージャは `[weak self]` で
/// 渡す前提で、画面を離れて止め忘れても**モデルを握り続けない**（#375・#1369 の再発防止）。
@MainActor
public final class GameStopwatch {
    private let persistInterval: Int
    private var task: Task<Void, Never>?
    private var clock: ElapsedClock?

    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    public var now: ElapsedClock.Now = { ContinuousClock.now }

    /// - Parameter persistInterval: 計時中に保存し直す間隔（秒）。長考のあとにアプリを終了しても、
    ///   失われる計時をこの幅に抑える（#240・#513）。
    public init(persistInterval: Int) {
        self.persistInterval = persistInterval
    }

    /// 数えている間は true。
    public var isRunning: Bool { task != nil }

    /// `base` 秒から数え始める（既に数えていれば張り直す）。
    /// - Parameter onSecond: 秒の境目ごとに呼ぶ。中で `advance(from:)` を使って経過秒を取り込む。
    public func start(base: Int, onSecond: @escaping @MainActor () -> Void) {
        task?.cancel()
        let clock = ElapsedClock(base: base, now: now)
        self.clock = clock
        // `[weak self]`: モデルが解放されたら（止め忘れても）ループを畳む。
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: clock.untilNextSecond)
                guard !Task.isCancelled, self != nil else { break }
                onSecond()
            }
        }
    }

    /// 数えていなければ `base` 秒から数え始める。
    public func startIfStopped(base: Int, onSecond: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        start(base: base, onSecond: onSecond)
    }

    /// 実経過時間に合わせた経過秒。数えていないときは nil。
    /// - Parameter current: モデルが今持っている経過秒（これより戻さない）。
    /// - Returns: 新しい経過秒と、保存間隔の境目を跨いだか。
    public func advance(from current: Int) -> (seconds: Int, crossedPersistBoundary: Bool)? {
        guard let clock, isRunning else { return nil }
        let seconds = max(current, clock.seconds)
        return (seconds, seconds / persistInterval != current / persistInterval)
    }

    /// 数えるのをやめる。直近の秒の境目からの端数は、止める前に `advance(from:)` で取り込むこと。
    public func stop() {
        task?.cancel()
        task = nil
    }
}
