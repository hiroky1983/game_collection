import Core
import Observation

/// おじさんの荷物運びパズル（#1016・v1.1.11 で公開 #1904）のゲーム状態。
///
/// 盤の判定・連鎖・ゲージ・得点は `OjisanPuzzleBoard` / `OjisanPuzzlePain` / `OjisanPuzzleScoring` の
/// 純粋ロジックに委譲し、ここは**落下タイマー・操作の受け口・決着**だけを持つ。
///
/// 遊び方は 2 つ（`OjisanPuzzleMode`・#1920）。荷運びモードは腰痛ゲージあり・最初から荷物が積まれていて、
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
        /// 盤の一番上まで積み上がった（荷運びモードでは、せり上がりで押し出されたときも）。
        case buried
        /// 荷物をラインより下まで片付けた（荷運びモードの勝ち）。
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
    /// 荷運びモードのクリアタイムになる。
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
        // 荷運びモードはゲージで、パズルモードは固定した組数で速くなる（ゲージの無い局は pain が 0 のまま）。
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
    /// 直前の回す操作が塞がれて回せなかったか。続けてもう一度押されたら上下（左右）を入れ替える（#2063）。
    /// 動かす・回せる・落ちる・固定するのどれかが起きたら畳む。
    private var rotationBlockedOnce = false
    /// 接地したあと、動かす・回すたびに固定が 1 刻み延びる回数の上限（定番の落ち物パズルの「動かすと猶予が延びる」・#2088）。
    /// 組がこれまでで最も低い行に達したときだけ数え直す（壁キックで持ち上げて落とし直しても数え直さない・#2123）。
    /// 無限に延ばして固定させない遊び方を防ぐ。
    static let groundExtensionLimit = 8
    /// 接地中に動かして、次の刻みでの固定を 1 回見送る予約があるか。
    private var groundExtended = false
    /// 接地してから延ばした回数。
    private var groundExtensions = 0
    /// 現在の組が達した最も低い行（組の 2 マスのうち下の方・下が大きい）。新しい組では `Int.min`。
    private var lowestRowReached = Int.min
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
        pain = mode.hasGauge ? OjisanPuzzlePain.initial(board: board) : 0
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
                rotationBlockedOnce = false
                steppedDownGroundGrace(to: moved)
                // 上限まで延ばしたあと、壁キックで持ち上げた分を落ちて再び接地したら、回す余地を与えずその場で固定する。
                // （接地した刻みが来る前に回し直され続けるのを断つ・#2123）
                if groundExtensions >= Self.groundExtensionLimit, OjisanPuzzleBoard.steppedDown(board, moved) == nil {
                    lock(moved)
                }
            } else if groundExtended {
                // 接地してから動かしたので、固定をもう 1 刻み待つ。
                groundExtended = false
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
        rotationBlockedOnce = false
        extendGroundGrace(for: moved)
        acceptInput()
        services?.feedback.impact(.light)
        return true
    }

    /// 回す。壁・床に当たるときは軸をずらして逃がす。腰が重いと受け付ける間隔が空く。
    ///
    /// 左右を壁や荷物に挟まれて回せないときは、1 回目は何も起きず、続けてもう一度押すと上下（左右）を入れ替える
    /// （定番の落ち物パズルと同じ「2 回押しで反転」・#2063）。
    @discardableResult
    public func rotate(clockwise: Bool) -> Bool {
        guard acceptsInput() else { return false }
        guard outcome == nil, phase == .dropping, let pair = current else {
            services?.feedback.notify(.warning)
            return false
        }
        let turned = OjisanPuzzleBoard.rotated(board, pair, clockwise: clockwise)
            ?? (rotationBlockedOnce ? OjisanPuzzleBoard.flipped(board, pair) : nil)
        guard let turned else {
            rotationBlockedOnce = true
            services?.feedback.notify(.warning)
            return false
        }
        current = turned
        rotationBlockedOnce = false
        extendGroundGrace(for: turned)
        acceptInput()
        services?.feedback.impact(.light)
        return true
    }

    /// 接地している組を動かした・回したら、固定を 1 刻み延ばす（上限 `groundExtensionLimit` 回）。
    private func extendGroundGrace(for pair: OjisanPuzzlePair) {
        guard OjisanPuzzleBoard.steppedDown(board, pair) == nil else {
            groundExtended = false
            return
        }
        guard groundExtensions < Self.groundExtensionLimit else { return }
        groundExtensions += 1
        groundExtended = true
    }

    private func resetGroundGrace() {
        groundExtended = false
        groundExtensions = 0
        lowestRowReached = Int.min
    }

    /// 1 段落ちたとき。これまでより低い行に達したときだけ猶予の回数を数え直す（#2123）。
    /// 壁キックで持ち上がった分を落ちるだけなら、延ばした回数は引き継ぐ。
    private func steppedDownGroundGrace(to pair: OjisanPuzzlePair) {
        let bottom = max(pair.row, pair.childRow)
        if bottom > lowestRowReached {
            resetGroundGrace()
            lowestRowReached = bottom
        } else {
            groundExtended = false
        }
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
            rotationBlockedOnce = false
            steppedDownGroundGrace(to: moved)
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
        pain = mode.hasGauge ? OjisanPuzzlePain.initial(board: board) : 0
        lastChain = 0
        chainDepth = 0
        phase = .dropping
        outcome = nil
        lastInputAt = nil
        rotationBlockedOnce = false
        resetGroundGrace()
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
        rotationBlockedOnce = false
        resetGroundGrace()
        lastChain = 0
        chainDepth = 0
        lockCount += 1
        if mode.hasGauge {
            // 見えない段にはみ出して消えた荷物は、盤に載っていないので重さに数えない。
            let placed = pair.cells.filter { OjisanPuzzleBoard.isInside(row: $0.cell.row, col: $0.cell.col) }
            pain = OjisanPuzzlePain.afterLock(pain, weights: placed.map { OjisanPuzzleLuggage.kind($0.kind)?.weight ?? 0 })
        }
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        services?.gameDidProgress(gameID: Self.gameID)
        phase = .settling
        services?.feedback.impact(.medium)

        // 入院は消える荷物の判定を先に済ませてから見る（#2063）。置いた瞬間に満タンでも、その手で消えて
        // ゲージが下がる／ラインより下になるなら入院しない。何も消えないと分かっているときだけ、待たずにここで終える。
        // ラインより下に収まっている盤（局面指定の入口で作れる）は、消えなくてもクリアが先なので `settleStep` に回す。
        let alreadyBelowLine = clearLineRow.map { OjisanPuzzleCleanup.isCleared(board, line: $0) } ?? false
        if mode.hasGauge, OjisanPuzzlePain.isHospitalized(pain), !alreadyBelowLine,
           OjisanPuzzleBoard.clearableGroups(OjisanPuzzleBoard.applyingGravity(board)).isEmpty {
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
        // 入院はクリアのあと（#2063）。連鎖まで消し終えても満タンのままなら入院。
        if mode.hasGauge, OjisanPuzzlePain.isHospitalized(pain) {
            finish(.hospitalized)
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
        resetGroundGrace()
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
    /// - 荷運びモード: クリアタイム（短いほど良い）。クリアしたときだけ秒数を載せ、入院・埋まりは勝敗の数だけ残る。
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
