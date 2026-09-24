import Core
import Foundation
import Observation

/// スピード（#1323）のゲーム状態。
///
/// このアプリの対戦ゲームはすべて順番制（`AITurnGuarded`）だが、スピードには手番が無く、あなたと CPU が
/// 同時に台札へ出し合う。そこで CPU は**時計を持たず**、「次にどれだけ待てばよいか」（`nextCPUWait()`）と
/// 「待ち終えたら何をするか」（`performCPUAction()`）の 2 つに分け、実際に待つのは View の `.task(id: cpuRun)`
/// だけにする（ぱっと暗算 #1321 の `advanceDisplay()` と同じ考え方）。時刻は `now` から読むので、テストは
/// 実時間を待たずに時計を手で進めて検証できる。
///
/// - あなたの側に制限時間は無い。速さで競うのは「CPU より先に出せるか」だけ。
/// - 場が動くたび（誰かが出す・めくる・タイム）に `cpuRun` が進み、View の待ちが組み直される。
///   CPU が出せる札を見つけた時刻（`cpuArmedAt`）はあなたが出しても持ち越すので、あなたが連打しても
///   CPU の反応が先送りされ続けることはない（見つけた札が出せなくなったときだけ仕切り直す）。
@MainActor
@Observable
public final class SpeedModel {
    public static let gameID = "speed"

    public enum Phase: Equatable, Sendable {
        /// まだ 1 ゲームも始めていない（速さのシートを出す）。
        case idle
        /// 出し合っている。
        case playing
        /// 決着した。
        case result
    }

    public enum Player: Equatable, Sendable {
        case human
        case cpu
    }

    public private(set) var settings: SpeedSettings
    public private(set) var phase: Phase = .idle
    /// あなたの手札（最大 4 枚。出した位置に山札から補充するので並びは動かない）。
    public private(set) var humanHand: [SpeedCard] = []
    public private(set) var humanStock: [SpeedCard] = []
    public private(set) var cpuHand: [SpeedCard] = []
    public private(set) var cpuStock: [SpeedCard] = []
    /// 台札 2 山。0 = 左（あなたの山札からめくる側）、1 = 右（CPU の山札からめくる側）。末尾が見えている札。
    public private(set) var piles: [[SpeedCard]] = [[], []]
    /// 手札で選択中の札の ID。両方の台札に置けるときだけ選択を挟む。
    public private(set) var selectedID: Int?
    public private(set) var winner: Player?
    /// めくるだけが続いて場が動かず、引き分けにしたか。
    public private(set) var isDraw = false
    /// ゲームの通し番号。広告の前後で同じゲームかの照合に使う（#729 の局ガード）。
    public private(set) var gameSerial = 0
    /// CPU の待ちを組み直す回数。View はこれを `.task(id:)` の鍵にする。場が動くたびに進む。
    public private(set) var cpuRun = 0
    /// このゲームでタイム（広告）を使ったか。1 ゲーム 1 回。
    public private(set) var timeoutUsed = false
    /// 「めくる」が続いた回数。誰かが出せば 0 に戻る。
    public private(set) var consecutiveFlips = 0
    /// CPU を止めているか（広告の視聴中・バックグラウンド）。止めているあいだ `nextCPUWait()` は nil を返し、
    /// 解くと反応の間を数え直してから動く（止めていたぶん CPU が有利にならない）。
    public private(set) var isCPUHeld = false
    /// 勝ったときの所要秒数（切り上げ・最低 1 秒）。負け・引き分けでは nil。
    public private(set) var winSeconds: Int?
    /// 直近の決着で確定した記録。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// いまの速さでの連勝。`PlayRecord.currentStreak` と同じ値で、アプリを閉じても続く。
    public private(set) var streak = 0
    /// いまの速さでの最速の勝ち（秒）。まだ勝ちが無ければ nil。
    public private(set) var bestSeconds: Int?

    private let services: GameServices?
    private let now: () -> Date
    private var generator: SplitMix64?
    /// ヒント表示のオン / オフ（#190）。ゲーム中には変わらないので参照のたびに読む。
    private let hints: FeedbackPreference
    /// 設定の「ゆっくりモード」。ゲームの開始時に倍率へ焼き込む（途中で切り替えても進行中には効かない）。
    private let slowMode: FeedbackPreference
    private var timingMultiplier = 1.0
    /// CPU が出せる札を見つけた時刻と、そのとき決めた反応の間。出せなくなったら捨てる。
    private var cpuArmedAt: Date?
    private var cpuReaction: Duration = .zero
    /// どちらも出せなくなった時刻。
    private var stuckSince: Date?
    /// タイムが終わる時刻。
    private var timeoutEndsAt: Date?
    private var startedAt: Date?
    /// `gameDidStart` を一度通したか。2 ゲーム目からは `gameDidRestart` で数える。
    private var hasCountedStart = false
    /// このゲームで `gameDidProgress` を通したか（冪等だが呼び出しを減らす）。
    private var hasProgressed = false
    #if DEBUG
    /// 撮影用。true のあいだは CPU を動かさない。
    private var isFrozenForCapture = false
    #endif

    /// - Parameters:
    ///   - seed: 配りと CPU の揺らぎを種から決める（テスト用。省略時はシステム乱数）。
    ///   - now: 反応の間・所要時間の計測に使う時計（テスト用）。
    public init(
        services: GameServices? = nil,
        seed: UInt64? = nil,
        now: @escaping () -> Date = Date.init,
        hints: FeedbackPreference = .hints,
        slowMode: FeedbackPreference = .actionSlowMode
    ) {
        self.services = services
        self.now = now
        self.hints = hints
        self.slowMode = slowMode
        generator = seed.map { SplitMix64(seed: $0) }
        // 中断データは最後に選んだ速さの控え。ゲームは復元せず、必ず速さのシートから入る。
        settings = services?.snapshots.load(SpeedSnapshot.self, for: Self.gameID)?.settings ?? .standard
        refreshRecord()
    }

    // MARK: - 読み取り

    /// 見えている台札（左・右）。空の山は nil。
    public var tops: [SpeedCard?] { piles.map(\.last) }

    /// あなたが出せる札の ID。
    public var humanPlayableIDs: Set<Int> {
        guard phase == .playing else { return [] }
        return Set(SpeedRules.placements(hand: humanHand, tops: tops).map(\.cardID))
    }

    public var humanHasPlayable: Bool { phase == .playing && SpeedRules.hasPlayable(hand: humanHand, tops: tops) }
    public var cpuHasPlayable: Bool { phase == .playing && SpeedRules.hasPlayable(hand: cpuHand, tops: tops) }

    /// どちらも出せる札が無い（= めくる局面）。
    public var isStuck: Bool { phase == .playing && !humanHasPlayable && !cpuHasPlayable }

    /// 「めくる」を押せるか。
    public var canFlip: Bool { isStuck }

    /// 手札のヒント（#190）。設定でオフのときは出さない。
    public var showsHints: Bool { hints.isEnabled }

    /// 選択中の札。
    public var selectedCard: SpeedCard? {
        guard let selectedID else { return nil }
        return humanHand.first { $0.id == selectedID }
    }

    /// `card` を置ける台札の番号。
    public func playableTargets(for card: SpeedCard) -> [Int] {
        guard phase == .playing else { return [] }
        return tops.indices.filter { SpeedRules.canPlay(card, onto: tops[$0]) }
    }

    /// 手札 + 山札の残り枚数。
    public func remaining(of player: Player) -> Int {
        switch player {
        case .human: return humanHand.count + humanStock.count
        case .cpu:   return cpuHand.count + cpuStock.count
        }
    }

    /// タイム（広告を見て CPU を休ませる）を出してよいか。負けそうなとき（CPU の残りが 8 枚以下で
    /// あなたより少ない）に限り、1 ゲーム 1 回。
    public var canUseTimeout: Bool {
        phase == .playing && !timeoutUsed
            && remaining(of: .cpu) <= SpeedRules.timeoutCPURemainingLimit
            && remaining(of: .cpu) < remaining(of: .human)
    }

    /// タイムの最中か。
    public var isTimeoutActive: Bool {
        guard let timeoutEndsAt else { return false }
        return phase == .playing && now() < timeoutEndsAt
    }

    /// 評価リクエスト（#53）の判定用。
    public var reviewOutcome: GameOutcome {
        if isDraw { return .draw }
        return winner == .human ? .win : .loss
    }

    // MARK: - 進行

    /// 速さを決めて新しいゲームを始める。
    public func start(_ newSettings: SpeedSettings) {
        settings = newSettings
        persist()
        refreshRecord()
        beginGame()
    }

    /// 同じ速さでもう一度。
    public func restart() {
        guard phase == .result else { return }
        beginGame()
    }

    // MARK: - あなたの操作

    /// 手札をタップ。置ける台札が 1 つならそこへ出し、2 つなら選択して台札のタップを待つ。
    public func tapHandCard(_ card: SpeedCard) {
        guard phase == .playing, humanHand.contains(card) else { return }
        let targets = playableTargets(for: card)
        switch targets.count {
        case 0:
            selectedID = nil
            services?.feedback.notify(.warning)
        case 1:
            selectedID = nil
            play(card, onto: targets[0], by: .human)
        default:
            selectedID = selectedID == card.id ? nil : card.id
            services?.feedback.impact(.rigid)
        }
    }

    /// 台札をタップ。選択中の札があればそこへ出す。無ければ、その台札に置ける手札がちょうど 1 枚のときに出す。
    public func tapPile(_ index: Int) {
        guard phase == .playing, piles.indices.contains(index) else { return }
        if let card = selectedCard {
            guard SpeedRules.canPlay(card, onto: tops[index]) else {
                services?.feedback.notify(.warning)
                return
            }
            selectedID = nil
            play(card, onto: index, by: .human)
            return
        }
        let candidates = humanHand.filter { SpeedRules.canPlay($0, onto: tops[index]) }
        guard candidates.count == 1 else {
            services?.feedback.notify(.warning)
            return
        }
        play(candidates[0], onto: index, by: .human)
    }

    public func clearSelection() {
        selectedID = nil
    }

    /// どちらも出せないとき、両方の山札から 1 枚ずつ台札に置く（「めくる」）。
    public func flipStocks() {
        guard canFlip else {
            services?.feedback.notify(.warning)
            return
        }
        performFlip()
    }

    // MARK: - CPU

    /// 次に CPU が動くまでの待ち。ゲーム中でなければ nil。
    ///
    /// - 出せる札があれば、見つけた時刻からの反応の残り。
    /// - 出せる札が無く、あなたが出せるなら、場を見直す間隔（あなたを待つ）。
    /// - どちらも出せなければ、「めくる」までの残り。
    /// - タイム中なら、タイムの残り。
    public func nextCPUWait() -> Duration? {
        guard phase == .playing, !isCPUHeld else { return nil }
        #if DEBUG
        if isFrozenForCapture { return nil }
        #endif
        let current = now()
        if let timeoutEndsAt, current < timeoutEndsAt {
            return .seconds(timeoutEndsAt.timeIntervalSince(current))
        }
        if cpuHasPlayable {
            stuckSince = nil
            if cpuArmedAt == nil {
                cpuArmedAt = current
                cpuReaction = makeReaction()
            }
            let elapsed = Duration.seconds(current.timeIntervalSince(cpuArmedAt ?? current))
            return max(.zero, cpuReaction - elapsed)
        }
        cpuArmedAt = nil
        if humanHasPlayable {
            stuckSince = nil
            return SpeedRules.scanInterval
        }
        if stuckSince == nil { stuckSince = current }
        let elapsed = Duration.seconds(current.timeIntervalSince(stuckSince ?? current))
        return max(.zero, stuckDelay - elapsed)
    }

    /// `nextCPUWait()` の待ちを終えたあとに呼ぶ。反応の間が過ぎていれば出し、めくる間が過ぎていればめくる。
    /// まだなら何もしない（View は続けて `nextCPUWait()` を取り直す）。
    public func performCPUAction() {
        guard phase == .playing, !isCPUHeld else { return }
        #if DEBUG
        if isFrozenForCapture { return }
        #endif
        let current = now()
        if let timeoutEndsAt {
            guard current >= timeoutEndsAt else { return }
            self.timeoutEndsAt = nil
            cpuArmedAt = nil
            stuckSince = nil
        }
        if let choice = SpeedRules.cpuChoice(hand: cpuHand, tops: tops, opponentHand: humanHand) {
            guard let armedAt = cpuArmedAt else {
                cpuArmedAt = current
                cpuReaction = makeReaction()
                return
            }
            // 待ち終えた直後の呼び出しでは、丸めで数ミリ秒足りないことがある。
            let elapsed = Duration.seconds(current.timeIntervalSince(armedAt)) + .milliseconds(5)
            guard elapsed >= cpuReaction, let card = cpuHand.first(where: { $0.id == choice.cardID }) else { return }
            play(card, onto: choice.pile, by: .cpu)
            return
        }
        cpuArmedAt = nil
        guard !humanHasPlayable, let since = stuckSince else { return }
        let elapsed = Duration.seconds(current.timeIntervalSince(since)) + .milliseconds(5)
        if elapsed >= stuckDelay { performFlip() }
    }

    /// CPU を止める / 解く。広告の視聴中（あなたが触れないあいだに CPU だけが出し切ってしまい、見終えた
    /// 広告のタイムが乗らない）とバックグラウンド移行時（アクション枠の基盤規約「即一時停止」）に使う。
    /// 解いたときは反応の間・めくるまでの間を数え直し、`cpuRun` を進めて View の待ちを組み直す。
    public func holdCPU(_ held: Bool) {
        guard held != isCPUHeld else { return }
        isCPUHeld = held
        cpuArmedAt = nil
        stuckSince = nil
        if !held { cpuRun += 1 }
    }

    // MARK: - 救済

    /// 広告を見終えたあと、CPU を `SpeedRules.timeoutDuration` のあいだ休ませる（#1323 の広告救済。1 ゲーム 1 回）。
    ///
    /// - Parameter serial: 広告を出す**前に**控えた `gameSerial`。広告のあいだにゲームが変わっていたら適用せず false を返す。
    /// - Returns: 適用できたか。
    public func grantTimeoutAfterAd(forGame serial: Int) -> Bool {
        guard serial == gameSerial, canUseTimeout else { return false }
        timeoutUsed = true
        timeoutEndsAt = now().addingTimeInterval(SpeedRules.timeoutDuration.timeInterval)
        cpuArmedAt = nil
        stuckSince = nil
        cpuRun += 1
        services?.feedback.notify(.success)
        return true
    }

    // MARK: - 内部

    private func beginGame() {
        gameSerial += 1
        deal()
        selectedID = nil
        winner = nil
        isDraw = false
        timeoutUsed = false
        timeoutEndsAt = nil
        consecutiveFlips = 0
        winSeconds = nil
        recordResult = nil
        cpuArmedAt = nil
        stuckSince = nil
        hasProgressed = false
        timingMultiplier = slowMode.isEnabled ? SpeedRules.slowModeMultiplier : 1
        startedAt = now()
        phase = .playing
        cpuRun += 1
        services?.feedback.impact(.medium)   // 札が配られた
        if hasCountedStart {
            services?.gameDidRestart(gameID: Self.gameID, level: settings.level.analyticsLevel)
        } else {
            services?.gameDidStart(gameID: Self.gameID, level: settings.level.analyticsLevel)
            hasCountedStart = true
        }
        // 中断データは速さの控えでゲームそのものは復元しない。既定の「中断データが在る = 続きから戻れる」を
        // 打ち消し、途中で離れたら休憩ではなく離脱として数える（ぱっと暗算 #1321 と同じ）。
        services?.gameWillNotResume(gameID: Self.gameID)
    }

    /// 赤 26 枚をあなた、黒 26 枚を CPU に配り、4 枚ずつ手札にして、1 枚ずつ台札に置く。
    private func deal() {
        var red = SpeedCard.redHalf()
        var black = SpeedCard.blackHalf()
        shuffle(&red)
        shuffle(&black)
        humanHand = Array(red.suffix(SpeedRules.handSize))
        humanStock = Array(red.dropLast(SpeedRules.handSize))
        cpuHand = Array(black.suffix(SpeedRules.handSize))
        cpuStock = Array(black.dropLast(SpeedRules.handSize))
        piles = [[], []]
        if let first = humanStock.popLast() { piles[0].append(first) }
        if let first = cpuStock.popLast() { piles[1].append(first) }
    }

    private func shuffle(_ cards: inout [SpeedCard]) {
        if var seeded = generator {
            defer { generator = seeded }
            cards.shuffle(using: &seeded)
        } else {
            cards.shuffle()
        }
    }

    /// 反応の間。基準に ±20% の揺らぎを乗せ、ゆっくりモードなら倍率を掛ける。
    private func makeReaction() -> Duration {
        let jitter: Double
        if var seeded = generator {
            defer { generator = seeded }
            jitter = Double.random(in: -SpeedRules.reactionJitterRatio...SpeedRules.reactionJitterRatio, using: &seeded)
        } else {
            jitter = Double.random(in: -SpeedRules.reactionJitterRatio...SpeedRules.reactionJitterRatio)
        }
        let base = Double(settings.level.reactionMilliseconds)
        return .milliseconds(Int((base * (1 + jitter) * timingMultiplier).rounded()))
    }

    private var stuckDelay: Duration {
        .milliseconds(Int((Double(SpeedRules.stuckDelayMilliseconds) * timingMultiplier).rounded()))
    }

    private func play(_ card: SpeedCard, onto pile: Int, by player: Player) {
        switch player {
        case .human:
            guard let index = humanHand.firstIndex(of: card) else { return }
            humanHand.remove(at: index)
            if let next = humanStock.popLast() { humanHand.insert(next, at: index) }
            services?.feedback.impact(.medium)
        case .cpu:
            guard let index = cpuHand.firstIndex(of: card) else { return }
            cpuHand.remove(at: index)
            if let next = cpuStock.popLast() { cpuHand.insert(next, at: index) }
            // CPU の着手では触覚を鳴らさない（あなたの操作と区別するため）。
        }
        piles[pile].append(card)
        consecutiveFlips = 0
        // CPU が出したら反応の間を数え直す。あなたが出しただけなら、CPU が見つけていた札の間は持ち越す
        // （出せなくなっていれば `nextCPUWait()` が捨てる）。連打で CPU を先送りし続けられないようにするため。
        if player == .cpu { cpuArmedAt = nil }
        stuckSince = nil
        // 選択を外すのはあなたが出したときだけ。CPU の着手で黙って外すと、選択したつもりで台札をタップした
        // 瞬間に「選択なし」の分岐へ入り、別の札が出る（CodeRabbit 指摘・PR #1345）。置けるかは `tapPile` が確かめる。
        if player == .human { selectedID = nil }
        markProgress()
        if remaining(of: player) == 0 {
            concludeGame(winner: player)
            return
        }
        cpuRun += 1
    }

    private func performFlip() {
        consecutiveFlips += 1
        if consecutiveFlips >= SpeedRules.maxConsecutiveFlips {
            concludeDraw()
            return
        }
        // 山札が尽きていれば、自分側の台札を切り直して山札にする。
        if humanStock.isEmpty {
            humanStock = piles[0]
            shuffle(&humanStock)
            piles[0] = []
        }
        if cpuStock.isEmpty {
            cpuStock = piles[1]
            shuffle(&cpuStock)
            piles[1] = []
        }
        if let card = humanStock.popLast() { piles[0].append(card) }
        if let card = cpuStock.popLast() { piles[1].append(card) }
        cpuArmedAt = nil
        stuckSince = nil
        selectedID = nil
        services?.feedback.impact(.light)
        markProgress()
        cpuRun += 1
    }

    /// 場が動いた = 途中で捨てたら離脱として数える境目（#500）。1 ゲームに 1 回通せばよい。
    private func markProgress() {
        guard !hasProgressed else { return }
        hasProgressed = true
        services?.gameDidProgress(gameID: Self.gameID)
    }

    private func concludeGame(winner: Player) {
        self.winner = winner
        phase = .result
        selectedID = nil
        cpuArmedAt = nil
        stuckSince = nil
        timeoutEndsAt = nil
        let elapsed = startedAt.map { now().timeIntervalSince($0) } ?? 0
        let seconds = max(1, Int(elapsed.rounded(.up)))
        winSeconds = winner == .human ? seconds : nil
        services?.feedback.notify(winner == .human ? .success : .error)
        finish(outcome: winner == .human ? .win : .loss, seconds: winSeconds)
    }

    private func concludeDraw() {
        isDraw = true
        winner = nil
        phase = .result
        selectedID = nil
        cpuArmedAt = nil
        stuckSince = nil
        timeoutEndsAt = nil
        services?.feedback.notify(.warning)
        finish(outcome: .draw, seconds: nil)
    }

    private func finish(outcome: GameOutcome, seconds: Int?) {
        // 決着 1 回につき `gameDidFinish` は 1 回だけ。勝ったときだけ所要時間を記録し、
        // タイムを使った回は時間の記録から外す（休ませたぶん有利になるため。勝ち・連勝には数える）。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome,
            score: GameScore(
                metric: .winLoss,
                seconds: timeoutUsed ? nil : seconds,
                variant: settings.variant,
                variantLabel: settings.variantLabel
            )
        )
        if let record = recordResult?.record {
            streak = record.currentStreak
            bestSeconds = record.bestSeconds
        } else {
            streak = outcome == .win ? streak + 1 : 0
        }
    }

    private func persist() {
        try? services?.snapshots.save(SpeedSnapshot(settings: settings), for: Self.gameID)
    }

    private func refreshRecord() {
        let record = services?.playLog?.record(gameID: Self.gameID, variant: settings.variant)
        streak = record?.currentStreak ?? 0
        bestSeconds = record?.bestSeconds
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    /// `internal` なのでアプリからは呼べない（`@testable import` からのみ見える）。
    func configureForTesting(
        humanHand: [SpeedCard],
        humanStock: [SpeedCard] = [],
        cpuHand: [SpeedCard],
        cpuStock: [SpeedCard] = [],
        piles: [[SpeedCard]],
        settings: SpeedSettings? = nil
    ) {
        if let settings { self.settings = settings }
        if phase != .playing { beginGame() }
        self.humanHand = humanHand
        self.humanStock = humanStock
        self.cpuHand = cpuHand
        self.cpuStock = cpuStock
        self.piles = piles
        selectedID = nil
        consecutiveFlips = 0
        cpuArmedAt = nil
        stuckSince = nil
        cpuRun += 1
    }

    #if DEBUG
    /// 撮影・動作確認用（`-speedScenario playing|both|stuck|timeout|win|lose`）。局面を固定して絵を安定させる。
    /// CPU は動かさない。Release には残さない（`ModuleTests` が走査で固定する）。
    public func applyDebugScenario(_ name: String) {
        func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
            SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
        }
        settings = SpeedSettings(level: .normal)
        streak = 3
        bestSeconds = 41
        let redRest = SpeedCard.redHalf().filter { ![5, 9, 12, 2].contains($0.rank) || $0.suit == .diamonds }
        let blackRest = SpeedCard.blackHalf().filter { ![6, 10, 1, 8].contains($0.rank) || $0.suit == .clubs }
        switch name {
        case "playing":
            // ♥5 が左の台札（♠6）に出せる局面。
            configureForTesting(
                humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
                humanStock: Array(redRest.prefix(14)),
                cpuHand: [card(.spades, 6), card(.clubs, 10), card(.spades, 1), card(.spades, 8)],
                cpuStock: Array(blackRest.prefix(12)),
                piles: [[card(.diamonds, 3), card(.spades, 6)], [card(.clubs, 4), card(.hearts, 10)]]
            )
        case "both":
            // ♥5 が左（♦4）にも右（♣6）にも出せる（選択中）。
            configureForTesting(
                humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
                humanStock: Array(redRest.prefix(14)),
                cpuHand: [card(.spades, 3), card(.clubs, 10), card(.spades, 1), card(.spades, 8)],
                cpuStock: Array(blackRest.prefix(12)),
                piles: [[card(.diamonds, 4)], [card(.clubs, 6)]]
            )
            selectedID = card(.hearts, 5).id
        case "stuck":
            // 台札は 3 と 3。手札に 2・4・A・K が無いので、どちらも出せない。
            configureForTesting(
                humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 7)],
                humanStock: Array(redRest.prefix(14)),
                cpuHand: [card(.spades, 6), card(.clubs, 10), card(.spades, 1), card(.spades, 8)],
                cpuStock: Array(blackRest.prefix(12)),
                piles: [[card(.diamonds, 3)], [card(.clubs, 3)]]
            )
        case "timeout":
            // CPU が残り 3 枚で負けそう（タイムのボタンが出る）。
            configureForTesting(
                humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
                humanStock: Array(redRest.prefix(10)),
                cpuHand: [card(.spades, 6), card(.clubs, 10), card(.spades, 1)],
                cpuStock: [],
                piles: [[card(.diamonds, 3)], [card(.clubs, 3)]]
            )
        case "win":
            configureForTesting(
                humanHand: [card(.hearts, 5)], humanStock: [],
                cpuHand: [card(.spades, 6), card(.clubs, 10), card(.spades, 1), card(.spades, 8)],
                cpuStock: Array(blackRest.prefix(12)),
                piles: [[card(.diamonds, 4)], [card(.clubs, 9)]]
            )
            tapHandCard(card(.hearts, 5))
        case "lose":
            configureForTesting(
                humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
                humanStock: Array(redRest.prefix(10)),
                cpuHand: [card(.spades, 6)], cpuStock: [],
                piles: [[card(.diamonds, 7)], [card(.clubs, 3)]]
            )
            cpuArmedAt = now().addingTimeInterval(-10)
            cpuReaction = .zero
            performCPUAction()
        default:
            break
        }
        isFrozenForCapture = true
    }
    #endif
}

private extension Duration {
    /// `Date` の計算に使う秒数。
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
