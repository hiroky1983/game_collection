import Core
import Observation

/// 腰痛おじさんパズル（#1016・v1.1.11 で公開 #1904）のゲーム状態。
///
/// 盤の判定・連鎖・ゲージ・得点は `OjisanPuzzleBoard` / `OjisanPuzzlePain` / `OjisanPuzzleScoring` の
/// 純粋ロジックに委譲し、ここは**落下タイマー・操作の受け口・決着**だけを持つ。
///
/// 遊び方は 2 つ（`OjisanPuzzleMode`・#1920）。腰痛モードは腰痛ゲージあり・最初から荷物が積まれていて、
/// 時間で下からせり上がり、ラインより下に片付ければクリア。パズルモードはゲージなしで、得点を競って埋まるまで続く。
/// 1 局のあいだはモードを変えない（`newGame(mode:)` で始め直したときだけ替わる）。
///
/// 解析（`game_start` / `game_end`）と記録（得点の自己ベスト）は `GameServices` の共通の入口でつなぐ（#1904）。
/// 中断と復元は持たない（落ちものの途中局面を戻す形を決めていないため。`OjisanPuzzleModule.resumesFromSnapshot`
/// は false のまま）。画面を離れれば局は捨てられ、1 つでも荷物を置いていれば途中離脱（quit）として数える。
/// Game Center・広告にはつないでいない。
@MainActor
@Observable
public final class OjisanPuzzleModel {
    /// 決着の種類。
    public enum Outcome: Sendable {
        /// 腰痛ゲージが 100 に達した。
        case hospitalized
        /// 盤の一番上まで積み上がった（腰痛モードでは、せり上がりで押し出されたときも）。
        case buried
        /// 荷物をラインより下まで片付けた（腰痛モードの勝ち）。
        case cleared
    }

    /// 進行の段階。落下中と、消える/落ちるの後片付け中で刻みの速さを変える。
    private enum Phase {
        case dropping
        case settling
    }

    /// この局の遊び方。局のあいだは変わらない。
    public private(set) var mode: OjisanPuzzleMode
    /// 盤（0 = 空きマス、1...5 = 荷物の種類）。
    public private(set) var board: [[Int]]
    /// 落下中の組。後片付け中は nil。
    public private(set) var current: OjisanPuzzlePair?
    /// 次に落ちてくる組。
    public private(set) var next: OjisanPuzzlePair
    public private(set) var score: Int = 0
    /// 腰痛ゲージ（0...100）。
    public private(set) var pain: Int = 0
    /// 直前の 1 手で何連鎖したか。次に固定するまで出したままにする。
    public private(set) var lastChain: Int = 0
    /// 連鎖が起きるたびに増える通し番号。表示側のトランジションを毎回再生させるための nonce。
    public private(set) var chainEventID: Int = 0
    /// 決着。nil なら進行中。
    public private(set) var outcome: Outcome?
    /// 決着時に記録した結果（自己ベストの更新内訳）。リザルトに `RecordLabel` で出す。
    public private(set) var recordResult: RecordResult?

    /// 局が始まってからの時間（ミリ秒）。落下ループの刻みを足していくので、止めているあいだは進まない。
    /// 腰痛モードのクリアタイムになる。
    public private(set) var elapsedMilliseconds = 0
    /// クリアのライン（この行より上に荷物が無ければクリア）。ラインの無い局は nil。
    public private(set) var clearLineRow: Int?
    /// 荷物がせり上がる間隔（ミリ秒）。せり上がらない局は nil。
    public private(set) var riseIntervalMilliseconds: Int?
    /// 次のせり上がりまでの残り（ミリ秒）。せり上がらない局は nil。
    public var millisecondsUntilRise: Int? {
        riseIntervalMilliseconds.map { max(0, $0 - riseClock) }
    }

    /// 組を 1 つでも固定した、まだ決着していない局か。捨てると途中離脱として数えられる局かどうか（新規ゲームの確認に使う）。
    public var hasProgress: Bool { outcome == nil && lockCount > 0 }

    /// 盤に落下中の組を重ねた、描画用の盤。View はこれだけを見れば描ける。
    public var displayBoard: [[Int]] {
        guard let current else { return board }
        var result = board
        for placed in current.cells
        where OjisanPuzzleBoard.isInside(row: placed.cell.row, col: placed.cell.col) {
            result[placed.cell.row][placed.cell.col] = placed.kind
        }
        return result
    }

    /// 腰がまだ軽いときの落下の刻み（ミリ秒）。
    public static let baseDropInterval = 620
    /// 後片付け（重力・消去）の刻み。連鎖が目で追える速さにする。
    public static let settleInterval = 200

    /// いまの落下の刻み（ミリ秒）。腰が重いほど短い＝速く落ちる。
    public var dropInterval: Int {
        // 腰痛モードはゲージで、パズルモードは固定した組数で速くなる（ゲージの無い局は pain が 0 のまま）。
        let speedUp = mode.hasGauge ? 1.0 : OjisanPuzzleSpeedUp.factor(locks: lockCount)
        return max(90, Int(Double(Self.baseDropInterval) * OjisanPuzzlePain.fallFactor(for: pain) * speedUp))
    }

    /// いまの腰の重さの段階。表示（顔・見出し）もこれで決める。
    public var painStage: OjisanPuzzlePain.Stage { OjisanPuzzlePain.stage(for: pain) }

    private let services: GameServices?
    private var rng: OjisanPuzzleRandom
    private var phase: Phase = .dropping
    /// 後片付け中に数えている連鎖の深さ。
    private var chainDepth = 0
    /// 固定した組の数（パズルモードの加速に使う）。
    private var lockCount = 0
    private var hasAnnouncedStart = false
    /// 前回のせり上がりからの経過（ミリ秒）。
    private var riseClock = 0
    /// せり上がりの時間が来ていて、次の組を出す前に上げる。落下中の組の下で盤が動かないようにするため。
    private var risePending = false
    private var loop: Task<Void, Never>?
    /// 直近に左右移動・回転を受け付けた時刻。腰が重いときの「ワンテンポ」を測るのに使う。
    private var lastInputAt: ContinuousClock.Instant?
    static let gameID = "ojisanpuzzle"

    /// 通常の入口。
    ///
    /// `announcesStart` を false にすると `game_start` を送らずに作る（開始シートで遊び方を選ぶ前の局。
    /// 選んだあとの `newGame(mode:)` か `announceStartIfNeeded()` で送る。選ぶ前の既定の遊び方で数えない）。
    public convenience init(services: GameServices? = nil, mode: OjisanPuzzleMode = .backpain, announcesStart: Bool = true) {
        self.init(services: services, mode: mode, announcesStart: announcesStart,
                  seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// 種を固定して開始する。荷物の並びが再現できるのでテスト・プレビューから使う。
    public init(
        services: GameServices? = nil, mode: OjisanPuzzleMode = .backpain, announcesStart: Bool = true, seed: UInt64
    ) {
        self.services = services
        self.mode = mode
        var generator = OjisanPuzzleRandom(seed: seed)
        board = mode.isCleanup ? OjisanPuzzleCleanup.initialBoard(using: &generator) : OjisanPuzzleBoard.emptyBoard()
        clearLineRow = mode.isCleanup ? OjisanPuzzleCleanup.clearLineRow : nil
        riseIntervalMilliseconds = mode.isCleanup ? OjisanPuzzleCleanup.riseIntervalMilliseconds : nil
        current = OjisanPuzzleBoard.makePair(using: &generator)
        next = OjisanPuzzleBoard.makePair(using: &generator)
        rng = generator
        // 中断データを持たないので、開くたびに新しいプレイ。`gameDidStart` は冪等なので
        // 再描画で init が何度走っても増えない（#158）。
        if announcesStart { announceStartIfNeeded() }
    }

    /// 盤とゲージを直接与えて開始する。狙った局面（あと 1 手で連鎖・入院寸前・積み上がり寸前）から
    /// 確かめるための入口。
    public init(
        services: GameServices? = nil,
        board: [[Int]],
        current: OjisanPuzzlePair?,
        pain: Int = 0,
        mode: OjisanPuzzleMode = .backpain,
        clearLineRow: Int? = nil,
        riseIntervalMilliseconds: Int? = nil,
        seed: UInt64 = 1
    ) {
        self.services = services
        self.mode = mode
        self.clearLineRow = clearLineRow
        self.riseIntervalMilliseconds = riseIntervalMilliseconds
        var generator = OjisanPuzzleRandom(seed: seed)
        self.board = board
        self.current = current
        self.pain = OjisanPuzzlePain.clamped(pain)
        self.next = OjisanPuzzleBoard.makePair(using: &generator)
        self.rng = generator
        // 狙った局面から始める入口も、新しいプレイの開始として数える（ブロックならべの同種の入口と同じ扱い）。
        announceStartIfNeeded()
    }

    /// `game_start` をまだ送っていなければ送る（冪等）。
    public func announceStartIfNeeded() {
        guard !hasAnnouncedStart else { return }
        hasAnnouncedStart = true
        services?.gameDidStart(gameID: Self.gameID, mode: mode.analyticsMode)
    }

    // MARK: - 進行

    /// 落下を始める / 再開する。画面が出ているあいだだけ回す。
    public func resume() {
        guard loop == nil, outcome == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.outcome == nil else { return }
                let interval = self.phase == .dropping ? self.dropInterval : Self.settleInterval
                try? await Task.sleep(for: .milliseconds(interval))
                // sleep を挟むとその間に画面が閉じる・決着することがあるので、起きたら必ず確かめ直す
                // （リポジトリの CPU 進行ループと同じ定石）。
                guard !Task.isCancelled else { return }
                // 待った時間をそのまま渡す。操作（ハードドロップ等）で段階が変わっても、時計は実際に待った分だけ進む。
                self.tick(elapsed: interval)
            }
        }
    }

    /// 落下を止める。局面はそのまま残す。
    public func pause() {
        loop?.cancel()
        loop = nil
    }

    /// タイマー 1 刻み。**テストから時間を進めるため internal** にしてある（public にはしない）。
    func tick(elapsed: Int? = nil) {
        guard outcome == nil else { return }
        let step = elapsed ?? (phase == .dropping ? dropInterval : Self.settleInterval)
        elapsedMilliseconds += step
        riseClock += step
        if let interval = riseIntervalMilliseconds, riseClock >= interval { risePending = true }
        switch phase {
        case .dropping:
            guard let pair = current else { return }
            if let moved = OjisanPuzzleBoard.steppedDown(board, pair) {
                current = moved
            } else {
                lock(pair)
            }
        case .settling:
            settleStep()
        }
    }

    // MARK: - 操作

    /// 左右へ 1 マス動かす。腰が重いと受け付ける間隔が空く（`acceptsInput`）。
    @discardableResult
    public func move(by delta: Int) -> Bool {
        guard acceptsInput() else { return false }
        guard outcome == nil, phase == .dropping, let pair = current,
              let moved = OjisanPuzzleBoard.moved(board, pair, byColumns: delta) else {
            services?.feedback.notify(.warning)
            return false
        }
        current = moved
        acceptInput()
        services?.feedback.impact(.light)
        return true
    }

    /// 回す。壁・床に当たるときは軸をずらして逃がす。腰が重いと受け付ける間隔が空く。
    @discardableResult
    public func rotate(clockwise: Bool) -> Bool {
        guard acceptsInput() else { return false }
        guard outcome == nil, phase == .dropping, let pair = current,
              let turned = OjisanPuzzleBoard.rotated(board, pair, clockwise: clockwise) else {
            services?.feedback.notify(.warning)
            return false
        }
        current = turned
        acceptInput()
        services?.feedback.impact(.light)
        return true
    }

    /// 左右移動・回転を受け付けてよいか。**腰が重いほどワンテンポ遅れる**（企画の核心）。
    ///
    /// 受け付けなかったときは触覚を鳴らさない。詰まっているときに拒否のたびに震えると
    /// 「壊れている」ように感じるため、「体が動かない」は無反応で表す。
    private func acceptsInput() -> Bool {
        let delay = OjisanPuzzlePain.inputDelayMilliseconds(for: pain)
        guard delay > 0, let last = lastInputAt else { return true }
        return ContinuousClock.now - last >= .milliseconds(delay)
    }

    /// 入力を受け付けた時刻を控える。次の入力までの間隔はここから測る。
    private func acceptInput() {
        lastInputAt = ContinuousClock.now
    }

    /// 1 段落とす。落ちなければその場で固定する。
    @discardableResult
    public func softDrop() -> Bool {
        guard outcome == nil, phase == .dropping, let pair = current else {
            services?.feedback.notify(.warning)
            return false
        }
        if let moved = OjisanPuzzleBoard.steppedDown(board, pair) {
            current = moved
        } else {
            lock(pair)
        }
        return true
    }

    /// 一気に落として固定する。
    @discardableResult
    public func hardDrop() -> Bool {
        guard outcome == nil, phase == .dropping, let pair = current else {
            services?.feedback.notify(.warning)
            return false
        }
        lock(OjisanPuzzleBoard.hardDropped(board, pair))
        return true
    }

    /// もう一度。`mode` を渡すと、その遊び方で始め直す（省略すると同じ遊び方）。
    public func newGame(mode newMode: OjisanPuzzleMode? = nil) {
        pause()
        let previousMode = mode
        mode = newMode ?? previousMode
        board = mode.isCleanup ? OjisanPuzzleCleanup.initialBoard(using: &rng) : OjisanPuzzleBoard.emptyBoard()
        clearLineRow = mode.isCleanup ? OjisanPuzzleCleanup.clearLineRow : nil
        riseIntervalMilliseconds = mode.isCleanup ? OjisanPuzzleCleanup.riseIntervalMilliseconds : nil
        elapsedMilliseconds = 0
        riseClock = 0
        risePending = false
        lockCount = 0
        current = OjisanPuzzleBoard.makePair(using: &rng)
        next = OjisanPuzzleBoard.makePair(using: &rng)
        score = 0
        pain = 0
        lastChain = 0
        chainDepth = 0
        phase = .dropping
        outcome = nil
        lastInputAt = nil
        recordResult = nil
        // 未決着のまま捨てた局は、始め直す前に途中離脱（quit）として送られる（#500）。
        // 捨てた局の `mode` は開始時に焼き込んだ値で出る（`game_end` の `mode` は途中で替わらない・#820）。
        hasAnnouncedStart = true
        services?.gameDidRestart(gameID: Self.gameID, mode: mode.analyticsMode)
        resume()
    }

    // MARK: - 固定と連鎖

    /// 組を盤に固定して、後片付け（重力・消去）へ移る。
    private func lock(_ pair: OjisanPuzzlePair) {
        board = OjisanPuzzleBoard.locking(board, pair)
        current = nil
        lastChain = 0
        chainDepth = 0
        lockCount += 1
        if mode.hasGauge {
            pain = OjisanPuzzlePain.afterLock(pain, weights: pair.cells.map { OjisanPuzzleLuggage.kind($0.kind)?.weight ?? 0 })
        }
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        services?.gameDidProgress(gameID: Self.gameID)
        phase = .settling
        services?.feedback.impact(.medium)

        // 荷物が増えた瞬間に腰が限界を迎えることがある。消せば減るので、判定は消し終えてからでは遅い。
        if mode.hasGauge, OjisanPuzzlePain.isHospitalized(pain) {
            finish(.hospitalized)
        }
    }

    /// 後片付けの 1 刻み。重力を 1 回かけ、消せる塊があれば消す。どちらも無ければ次の組を出す。
    private func settleStep() {
        let settled = OjisanPuzzleBoard.applyingGravity(board)
        if settled != board {
            board = settled
            return
        }

        let groups = OjisanPuzzleBoard.clearableGroups(board)
        if !groups.isEmpty {
            chainDepth += 1
            let cells = groups.reduce(0) { $0 + $1.count }
            score += OjisanPuzzleScoring.chainPoints(cells: cells, chain: chainDepth)
            if mode.hasGauge { pain = OjisanPuzzlePain.afterChain(pain, cells: cells, chain: chainDepth) }
            board = OjisanPuzzleBoard.removing(board, groups: groups)
            lastChain = chainDepth
            chainEventID += 1
            services?.feedback.impact(.medium)
            return
        }

        // 片付け終わったところでラインを見る（連鎖の途中や落下中の組では判定しない）。
        if let line = clearLineRow, OjisanPuzzleCleanup.isCleared(board, line: line) {
            finish(.cleared)
            return
        }
        spawnNext()
    }

    /// 次の組を盤へ出す。時間が来ていれば先に荷物を 1 段せり上げる。どこにも出せなければ積み上がりで終わり。
    private func spawnNext() {
        if risePending {
            risePending = false
            riseClock = 0
            let risen = OjisanPuzzleCleanup.rising(board, using: &rng)
            board = risen.board
            if risen.overflowed {
                finish(.buried)
                return
            }
        }
        // 出る列の出現位置が塞がっていたら積み上がり（別の列へは逃がさない・#1954）。
        let pair = next
        guard !OjisanPuzzleBoard.isSpawnBlocked(board) else {
            finish(.buried)
            return
        }
        current = pair
        next = OjisanPuzzleBoard.makePair(using: &rng)
        phase = .dropping
    }

    private func finish(_ outcome: Outcome) {
        self.outcome = outcome
        current = nil
        pause()
        services?.feedback.notify(outcome == .cleared ? .success : .error)
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome == .cleared ? .win : .loss,
            score: recordScore(for: outcome)
        )
    }

    /// 決着の記録。保存先はモードごとの区分（`ojisanpuzzle#<区分>`）で、互いの自己ベストを汚さない。
    ///
    /// - 腰痛モード: クリアタイム（短いほど良い）。クリアしたときだけ秒数を載せ、入院・埋まりは勝敗の数だけ残る。
    /// - パズルモード: 得点（高いほど良い）。終わりは必ず埋まりなので毎回負けとして数える
    ///   （ブロックならべと同じ「終わり = 負け・得点で競う」形）。
    private func recordScore(for outcome: Outcome) -> GameScore {
        if mode.isCleanup {
            return GameScore(
                metric: .shortestTime,
                seconds: outcome == .cleared ? max(1, elapsedMilliseconds / 1000) : nil,
                variant: mode.recordVariant,
                variantLabel: mode.recordVariantLabel
            )
        }
        return GameScore(
            metric: .points, points: score,
            variant: mode.recordVariant, variantLabel: mode.recordVariantLabel
        )
    }
}
