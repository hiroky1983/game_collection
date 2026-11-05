import Foundation

/// リワード広告の先読み 1 本ぶんの段取り（#3341）。読み込みの失敗を**間を空けて再試行**し、
/// 応答が返らない読み込みを**時間で打ち切る**。
///
/// 以前は先読みの失敗を握りつぶして再試行せず、ハブからゲームを開き直すまで先読みが空のままだった。
/// また、タップ時は先読みの完了を無期限に待っていたため、SDK の応答が返らないと「広告で振る」が
/// 広告待ちのまま戻らず押せなくなりうる。実際の `RewardedAd` は端末側なので、読み込みの口は
/// クロージャで受け取り、再試行の間隔・打ち切り・タップとの相乗りだけをここで純粋に検証する
/// （`PreloadedAdSlot` と同じ流儀）。
@MainActor
public final class RewardedAdPreloader<Ad> {
    /// 失敗してから次の読み込みまでの間隔。尽きたらその回の先読みは諦める（次の `start()` まで）。
    public static var defaultRetryDelays: [Duration] { [.seconds(5), .seconds(15), .seconds(45)] }
    /// 1 回の読み込みを待つ上限。これを超えたら失敗として扱う。
    public static var defaultLoadTimeout: Duration { .seconds(20) }

    private var slot: PreloadedAdSlot<Ad>
    private let retryDelays: [Duration]
    private let loadTimeout: Duration?
    private let sleep: @MainActor (Duration) async throws -> Void
    private let now: () -> Date
    private let load: @MainActor () async throws -> Ad

    /// 先読みの全体（読み込み → 失敗なら間を空けて再試行）。二重に始めないためと、止めるため。
    private var chain: Task<Void, Never>?
    /// 進行中の読み込み 1 回ぶん。タップがその完了に相乗りする。再試行の待ち時間は含まない。
    private var attempt: Task<Void, Never>?

    /// - Parameters:
    ///   - loadTimeout: nil なら打ち切らない（テスト用）。
    ///   - sleep: 再試行の待ち。テストでは待たずに返す。
    public init(
        lifetime: TimeInterval = PreloadedAdSlot<Ad>.defaultLifetime,
        retryDelays: [Duration] = RewardedAdPreloader.defaultRetryDelays,
        loadTimeout: Duration? = RewardedAdPreloader.defaultLoadTimeout,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init,
        load: @escaping @MainActor () async throws -> Ad
    ) {
        slot = PreloadedAdSlot<Ad>(lifetime: lifetime)
        self.retryDelays = retryDelays
        self.loadTimeout = loadTimeout
        self.sleep = sleep
        self.now = now
        self.load = load
    }

    /// 使える広告を預かっているか。
    public var isReady: Bool { slot.hasFreshAd(now: now()) }

    /// 先読みの最中か（読み込み中、または次の再試行の待ち）。画面の「読み込み中」表示に使える。
    public var isPreparing: Bool { chain != nil }

    /// 先読みを始める。使える広告を預かっている・すでに先読み中なら何もしない。
    ///
    /// - Parameter afterFailure: 直前の読み込みが失敗した直後なら true。最初の間隔だけ待ってから読む。
    public func start(afterFailure: Bool = false) {
        guard chain == nil, !isReady else { return }
        chain = Task { [weak self] in
            guard let self else { return }
            await self.runChain(skippingFirstAttempt: afterFailure)
            self.chain = nil
        }
    }

    /// 進行中の読み込みが終わるまで待つ。再試行の待ち時間中は待たずにすぐ返る（タップを長く待たせない）。
    public func awaitCurrentAttempt() async {
        await attempt?.value
    }

    /// 預かった広告を取り出す。取り出したら空になる。
    public func take() -> Ad? {
        slot.take(now: now())
    }

    /// 再試行を止める。タップがその場で読み込むときに、裏の再試行と二重に読まないために呼ぶ。
    public func cancelRetries() {
        chain?.cancel()
        chain = nil
    }

    /// その場で 1 本読み込む（打ち切りあり）。預けずに返す。失敗・打ち切りは nil。
    public func loadNow() async -> Ad? {
        await loadOnce()
    }

    private func runChain(skippingFirstAttempt: Bool) async {
        var retry = 0
        var skip = skippingFirstAttempt
        while !Task.isCancelled {
            if skip {
                skip = false
            } else {
                let task = Task { [weak self] in
                    guard let self, let ad = await self.loadOnce() else { return }
                    self.slot.store(ad, loadedAt: self.now())
                }
                attempt = task
                await task.value
                attempt = nil
                if isReady { return }
            }
            guard retry < retryDelays.count else { return }
            do { try await sleep(retryDelays[retry]) } catch { return }
            retry += 1
        }
    }

    /// 読み込みを 1 回。`loadTimeout` を超えたら nil（SDK 側が応答しなくても、ここは打ち切って返る）。
    private func loadOnce() async -> Ad? {
        let race = LoadRace<Ad>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let loading = Task { [load] in
                race.finish(try? await load())
            }
            let timer = loadTimeout.map { timeout in
                Task {
                    try? await Task.sleep(for: timeout)
                    race.finish(nil)
                }
            }
            race.onFinish = {
                timer?.cancel()
                loading.cancel()
                continuation.resume()
            }
        }
        return race.result
    }
}

/// 読み込みと打ち切りの先着判定。先に決まった方が結果になり、あとから来た方は捨てる。
@MainActor
private final class LoadRace<Ad> {
    private(set) var result: Ad?
    private var finished = false
    var onFinish: (@MainActor () -> Void)?

    /// - Returns: この呼び出しで決まったか。
    @discardableResult
    func finish(_ ad: Ad?) -> Bool {
        guard !finished else { return false }
        finished = true
        result = ad
        onFinish?()
        return true
    }
}
