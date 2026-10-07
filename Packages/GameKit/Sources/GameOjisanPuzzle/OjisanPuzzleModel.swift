import Core
import Observation

/// 腰痛おじさんパズル（#1016・v1.1.11 で公開 #1904）のゲーム状態。
///
/// 盤の判定・連鎖・ゲージ・得点は `OjisanPuzzleBoard` / `OjisanPuzzlePain` / `OjisanPuzzleScoring` の
/// 純粋ロジックに委譲し、ここは**落下タイマー・操作の受け口・決着**だけを持つ（`BlockPuzzleModel` と同じ作法）。
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
        /// 盤の一番上まで積み上がった。
        case buried
    }

    /// 進行の段階。落下中と、消える/落ちるの後片付け中で刻みの速さを変える。
    private enum Phase {
        case dropping
        case settling
    }

    /// 盤（0 = 空きマス、1...4 = 荷物の種類）。
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
    /// 連鎖が起きるたびに増える通し番号。表示側のトランジションを毎回再生させるための nonce
    /// （`BlockPuzzleModel.clearEventID` と同じ理由）。
    public private(set) var chainEventID: Int = 0
    /// 決着。nil なら進行中。
    public private(set) var outcome: Outcome?
    /// 決着時に記録した結果（自己ベストの更新内訳）。リザルトに `RecordLabel` で出す。
    public private(set) var recordResult: RecordResult?

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
        max(90, Int(Double(Self.baseDropInterval) * OjisanPuzzlePain.fallFactor(for: pain)))
    }

    /// いまの腰の重さの段階。表示（顔・見出し）もこれで決める。
    public var painStage: OjisanPuzzlePain.Stage { OjisanPuzzlePain.stage(for: pain) }

    private let services: GameServices?
    private var rng: OjisanPuzzleRandom
    private var phase: Phase = .dropping
    /// 後片付け中に数えている連鎖の深さ。
    private var chainDepth = 0
    private var loop: Task<Void, Never>?
    /// 直近に左右移動・回転を受け付けた時刻。腰が重いときの「ワンテンポ」を測るのに使う。
    private var lastInputAt: ContinuousClock.Instant?
    static let gameID = "ojisanpuzzle"

    /// 通常の入口。
    public convenience init(services: GameServices? = nil) {
        self.init(services: services, seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// 種を固定して開始する。荷物の並びが再現できるのでテスト・プレビューから使う。
    public init(services: GameServices? = nil, seed: UInt64) {
        self.services = services
        var generator = OjisanPuzzleRandom(seed: seed)
        board = OjisanPuzzleBoard.emptyBoard()
        current = OjisanPuzzleBoard.makePair(using: &generator)
        next = OjisanPuzzleBoard.makePair(using: &generator)
        rng = generator
        // 中断データを持たないので、開くたびに新しいプレイ。`gameDidStart` は冪等なので
        // 再描画で init が何度走っても増えない（#158）。
        services?.gameDidStart(gameID: Self.gameID)
    }

    /// 盤とゲージを直接与えて開始する。狙った局面（あと 1 手で連鎖・入院寸前・積み上がり寸前）から
    /// 確かめるための入口。
    public init(
        services: GameServices? = nil,
        board: [[Int]],
        current: OjisanPuzzlePair?,
        pain: Int = 0,
        seed: UInt64 = 1
    ) {
        self.services = services
        var generator = OjisanPuzzleRandom(seed: seed)
        self.board = board
        self.current = current
        self.pain = OjisanPuzzlePain.clamped(pain)
        self.next = OjisanPuzzleBoard.makePair(using: &generator)
        self.rng = generator
        // 狙った局面から始める入口も、新しいプレイの開始として数える（ブロックならべの同種の入口と同じ扱い）。
        services?.gameDidStart(gameID: Self.gameID)
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
                self.tick()
            }
        }
    }

    /// 落下を止める。局面はそのまま残す。
    public func pause() {
        loop?.cancel()
        loop = nil
    }

    /// タイマー 1 刻み。**テストから時間を進めるため internal** にしてある（public にはしない）。
    func tick() {
        guard outcome == nil else { return }
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

    /// もう一度。
    public func newGame() {
        pause()
        board = OjisanPuzzleBoard.emptyBoard()
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
        services?.gameDidRestart(gameID: Self.gameID)
        resume()
    }

    // MARK: - 固定と連鎖

    /// 組を盤に固定して、後片付け（重力・消去）へ移る。
    private func lock(_ pair: OjisanPuzzlePair) {
        board = OjisanPuzzleBoard.locking(board, pair)
        current = nil
        lastChain = 0
        chainDepth = 0
        pain = OjisanPuzzlePain.afterLock(pain)
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        services?.gameDidProgress(gameID: Self.gameID)
        phase = .settling
        services?.feedback.impact(.medium)

        // 荷物が増えた瞬間に腰が限界を迎えることがある。消せば減るので、判定は消し終えてからでは遅い。
        if OjisanPuzzlePain.isHospitalized(pain) {
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
            pain = OjisanPuzzlePain.afterChain(pain, cells: cells, chain: chainDepth)
            board = OjisanPuzzleBoard.removing(board, groups: groups)
            lastChain = chainDepth
            chainEventID += 1
            services?.feedback.impact(.medium)
            return
        }

        spawnNext()
    }

    /// 次の組を盤へ出す。出す場所が埋まっていたら積み上がりで終わり。
    private func spawnNext() {
        let pair = next
        guard OjisanPuzzleBoard.canPlace(board, pair) else {
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
        services?.feedback.notify(.error)
        // 入院・積み上がりのどちらも負けとして記録し、得点を自己ベストに残す
        // （ブロックならべと同じ「終わり = 負け・得点で競う」形）。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .loss,
            score: GameScore(metric: .points, points: score)
        )
    }
}
