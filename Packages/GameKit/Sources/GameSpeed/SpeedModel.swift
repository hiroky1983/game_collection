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
    /// CPU を止めている理由（広告の視聴中・バックグラウンド・シートの提示中）。1 つでも残っているあいだ
    /// `nextCPUWait()` は nil を返し、すべて解くと反応の間を数え直してから動く（止めていたぶん CPU が有利にならない）。
    public private(set) var cpuHolds: CPUHold = []
    public var isCPUHeld: Bool { !cpuHolds.isEmpty }
    /// 出せる札の案内（`SpeedRules.playableNavigationDelay` 何もしなかったら光らせる）を出しているか。
    /// あなたが操作する・場が動く・CPU を止める / 解くと消え、そこから数え直す。
    public private(set) var isShowingPlayableNavigation = false
    /// 案内の数え直しの番号。View はこれを `.task(id:)` の鍵にし、`playableNavigationWait()` だけ待って
    /// `updatePlayableNavigation()` を呼ぶ（CPU の待ちと同じく、Model は時計を持たない）。
    public private(set) var navigationEpoch = 0
    /// 「台札のほうへ払って出します」の一言を出しているか（指のタップでは札を出さない・会長 QA 2026-10-24）。
    /// View が少し待って `dismissSwipeTip()` で消す（Model は時計を持たない）。
    public private(set) var isShowingSwipeTip = false
    /// この局で一言を出したか。1 局に 1 回まで。
    private var swipeTipUsed = false
    /// この局で払って札を出したか。払い方が分かっている人には一言を出さない（初めのうちだけ）。
    private var hasSwipedThisGame = false

    /// CPU を止めている理由。理由ごとに独立して数えるので、広告が終わってもシートが開いていれば止まったまま。
    public struct CPUHold: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// リワード広告の視聴中。
        public static let ad = CPUHold(rawValue: 1 << 0)
        /// バックグラウンド・非アクティブ。
        public static let inactive = CPUHold(rawValue: 1 << 1)
        /// 遊び方・速さのシートの提示中（背面で敗北が記録されないように。#1358）。
        public static let sheet = CPUHold(rawValue: 1 << 2)
    }
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
    private let elapsedNow: ElapsedClock.Now
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
    /// 案内の 5 秒を数え始めた時刻（最後の操作か、場が動いた時刻）。
    private var navigationSince: Date?
    /// タイムが終わる時刻。
    private var timeoutEndsAt: Date?
    /// CPU を止め始めた時刻。解いたとき、止めていたぶんを `timeoutEndsAt` に足す（タイムを止めているあいだに減らさない。#3001）。
    private var holdStartedAt: Date?
    /// 勝利タイムの計時。CPU を止めている間（シート・背面・広告）は進めないので、止める前までを `playedBefore` に積み、
    /// 動いている間だけ `playClock` が数える。
    private var playedBefore: Duration = .zero
    private var playClock: ElapsedClock?
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
    ///   - now: 反応の間の計測に使う時計（テスト用）。
    ///   - elapsedNow: 勝利タイムの計測に使う時計（テスト用）。
    public init(
        services: GameServices? = nil,
        seed: UInt64? = nil,
        now: @escaping () -> Date = Date.init,
        elapsedNow: @escaping ElapsedClock.Now = { ContinuousClock.now },
        hints: FeedbackPreference = .hints,
        slowMode: FeedbackPreference = .actionSlowMode
    ) {
        self.services = services
        self.now = now
        self.elapsedNow = elapsedNow
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

    /// 案内で光らせる台札（あなたの出せる札のどれかを置ける台札）。案内を出していなければ空。
    public var playableNavigationPiles: Set<Int> {
        guard isShowingPlayableNavigation else { return [] }
        return Set(SpeedRules.placements(hand: humanHand, tops: tops).map(\.pile))
    }

    /// 案内で光らせる手札の ID。案内を出していなければ空。
    public var playableNavigationCardIDs: Set<Int> {
        isShowingPlayableNavigation ? humanPlayableIDs : []
    }

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

    /// 「新規対局」で失われる進行があるか（場が 1 度でも動いた未決着のゲーム。#2370）。
    public var hasProgressToLose: Bool { phase == .playing && hasProgressed }

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

    /// 指のタップへの反応。
    public enum TapResponse: Equatable, Sendable {
        /// 支援機能の操作として扱った（`tapHandCard` と同じ）。
        case acted
        /// 札は出さない。札を持ち上げて戻す反応だけ返す。`showsTip` は一言を出すか。
        case nudged(showsTip: Bool)
    }

    /// 手札を指でタップした（会長 QA 2026-10-24・build 52「タップで押せると『はやい』でも勝てる」）。
    /// 通常の操作では札を出さず、持ち上げて戻す反応と、1 局に 1 回の一言だけ返す。札を出す手段は払いだけ。
    /// - Parameter assistive: VoiceOver・スイッチコントロールを使っているか。使っていればタップで出す（`tapHandCard`）。
    @discardableResult
    public func fingerTapHandCard(_ card: SpeedCard, assistive: Bool) -> TapResponse {
        if assistive {
            tapHandCard(card)
            return .acted
        }
        guard phase == .playing, humanHand.contains(card) else { return .nudged(showsTip: false) }
        // 札は動いていないので、出せる札の案内（5 秒）は数え直さない（タップを続ける人にも案内が出る）。
        services?.feedback.impact(.light)
        guard !swipeTipUsed, !hasSwipedThisGame else { return .nudged(showsTip: false) }
        swipeTipUsed = true
        isShowingSwipeTip = true
        return .nudged(showsTip: true)
    }

    /// 台札を指でタップした。通常の操作では何もしない（選んだ札・置けるただ 1 枚を置く操作も止める）。
    /// 支援機能を使っているとき、または札を選んであるとき（選択は支援機能の操作でしか作られない）だけ `tapPile` する。
    /// - Returns: `tapPile` に渡したか。
    @discardableResult
    public func fingerTapPile(_ index: Int, assistive: Bool) -> Bool {
        guard assistive || selectedID != nil else { return false }
        tapPile(index)
        return true
    }

    /// 一言を消す。
    public func dismissSwipeTip() {
        isShowingSwipeTip = false
    }

    /// 手札をタップ（支援機能の操作・アクション）。置ける台札が 1 つならそこへ出し、2 つなら選択して台札のタップを待つ。
    /// 指のタップは `fingerTapHandCard` を通す（通常の操作では出さない）。
    public func tapHandCard(_ card: SpeedCard) {
        guard phase == .playing, humanHand.contains(card) else { return }
        restartPlayableNavigation()
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
        restartPlayableNavigation()
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

    /// 手札を払って台札 `index` に出す（会長 QA 2026-10-23・スワイプ前提）。出せなければ警告を鳴らして何もしない
    /// （ペナルティは無い。タップで出せない札を選んだときと同じ）。
    /// - Returns: 出せたか。
    @discardableResult
    public func swipeCard(_ card: SpeedCard, onto index: Int) -> Bool {
        guard phase == .playing, humanHand.contains(card), piles.indices.contains(index) else { return false }
        restartPlayableNavigation()
        guard SpeedRules.canPlay(card, onto: tops[index]) else {
            selectedID = nil
            services?.feedback.notify(.warning)
            return false
        }
        play(card, onto: index, by: .human)
        hasSwipedThisGame = true
        isShowingSwipeTip = false
        return true
    }

    public func clearSelection() {
        selectedID = nil
    }

    // MARK: - 出せる札の案内

    /// 札に触れた（払い始めた）ことを伝える。案内を消して 5 秒を数え直す。
    public func noteHumanActivity() {
        guard phase == .playing else { return }
        restartPlayableNavigation()
    }

    /// 案内を出すまでの残り。出す条件（ゲーム中・CPU を止めていない・ヒントがオン・あなたに出せる札がある・まだ出していない）を
    /// 満たさなければ nil（出せる札が無いときは案内しない。そのときは CPU が速くなる #2690 のまま）。
    public func playableNavigationWait() -> Duration? {
        guard isPlayableNavigationEligible, !isShowingPlayableNavigation else { return nil }
        let current = now()
        let since = navigationSince ?? current
        if navigationSince == nil { navigationSince = current }
        let elapsed = Duration.seconds(current.timeIntervalSince(since))
        return max(.zero, SpeedRules.playableNavigationDelay - elapsed)
    }

    /// `playableNavigationWait()` の待ちを終えたあとに呼ぶ。5 秒が過ぎていて条件を満たしていれば案内を出す。
    public func updatePlayableNavigation() {
        guard isPlayableNavigationEligible, let since = navigationSince else {
            isShowingPlayableNavigation = false
            return
        }
        // 待ち終えた直後の呼び出しでは、丸めで数ミリ秒足りないことがある（CPU の待ちと同じ）。
        let elapsed = Duration.seconds(now().timeIntervalSince(since)) + .milliseconds(5)
        if elapsed >= SpeedRules.playableNavigationDelay { isShowingPlayableNavigation = true }
    }

    private var isPlayableNavigationEligible: Bool {
        phase == .playing && !isCPUHeld && hints.isEnabled && humanHasPlayable
    }

    /// 案内を消し、いまから数え直す。あなたの操作・場が動いたとき・CPU を止める / 解くときに呼ぶ。
    private func restartPlayableNavigation() {
        isShowingPlayableNavigation = false
        navigationSince = now()
        navigationEpoch += 1
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
    /// - 出せる札があれば、見つけた時刻からの反応の残り（あなたが出せないあいだは半分の間。#2690）。
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
            return max(.zero, effectiveReaction - elapsed)
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
            guard elapsed >= effectiveReaction, let card = cpuHand.first(where: { $0.id == choice.cardID }) else { return }
            play(card, onto: choice.pile, by: .cpu)
            return
        }
        cpuArmedAt = nil
        guard !humanHasPlayable, let since = stuckSince else { return }
        let elapsed = Duration.seconds(current.timeIntervalSince(since)) + .milliseconds(5)
        if elapsed >= stuckDelay { performFlip() }
    }

    /// CPU を止める / 解く。広告の視聴中（あなたが触れないあいだに CPU だけが出し切ってしまい、見終えた
    /// 広告のタイムが乗らない）・バックグラウンド移行時（アクション枠の基盤規約「即一時停止」）・
    /// シートの提示中（読んでいるあいだに負けが記録される、を防ぐ。#1358）に使う。
    /// 理由ごとに数えるので、ほかの理由が残っていれば解いても止まったまま。
    /// すべて解いたときは反応の間・めくるまでの間を数え直し、`cpuRun` を進めて View の待ちを組み直す。
    public func holdCPU(_ reason: CPUHold, _ held: Bool) {
        var next = cpuHolds
        if held { next.formUnion(reason) } else { next.subtract(reason) }
        guard next != cpuHolds else { return }
        let wasHeld = isCPUHeld
        cpuHolds = next
        cpuArmedAt = nil
        stuckSince = nil
        // 止めているあいだは数えない。解いたらそこから 5 秒を数え直す（広告・シート・背面の時間で案内を出さない）。
        restartPlayableNavigation()
        if !wasHeld && isCPUHeld {
            holdStartedAt = now()
            pausePlayClock()
        }
        if wasHeld && !isCPUHeld {
            if let started = holdStartedAt, let ends = timeoutEndsAt {
                timeoutEndsAt = ends.addingTimeInterval(max(0, now().timeIntervalSince(started)))
            }
            holdStartedAt = nil
            if phase == .playing { playClock = ElapsedClock(now: elapsedNow) }
            cpuRun += 1
        }
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
        // 広告の視聴中に付与される場合、止めた時刻はタイムの開始より前なので数え直す。
        if isCPUHeld { holdStartedAt = now() }
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
        restartPlayableNavigation()
        hasProgressed = false
        swipeTipUsed = false
        hasSwipedThisGame = false
        isShowingSwipeTip = false
        timingMultiplier = slowMode.isEnabled ? SpeedRules.slowModeMultiplier : 1
        playedBefore = .zero
        playClock = isCPUHeld ? nil : ElapsedClock(now: elapsedNow)
        phase = .playing
        cpuRun += 1
        services?.feedback.impact(.card(.shuffle))   // 札が切られて配られた
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

    /// 見つけた時点で決めた反応の間。あなたが出せる札を持たないあいだだけ縮める（#2690）。
    /// 待つたびに判定するので、あなたが出せるようになった瞬間に元の長さへ戻る。
    private var effectiveReaction: Duration {
        humanHasPlayable ? cpuReaction : cpuReaction * SpeedRules.humanStuckReactionRatio
    }

    /// めくるまでの間。めくった直後にまためくる（2 回目以降）は短い間にする。
    private var stuckDelay: Duration {
        let base = consecutiveFlips > 0 ? SpeedRules.stuckRepeatDelayMilliseconds : SpeedRules.stuckDelayMilliseconds
        return .milliseconds(Int((Double(base) * timingMultiplier).rounded()))
    }

    private func play(_ card: SpeedCard, onto pile: Int, by player: Player) {
        switch player {
        case .human:
            guard let index = humanHand.firstIndex(of: card) else { return }
            humanHand.remove(at: index)
            if let next = humanStock.popLast() { humanHand.insert(next, at: index) }
            services?.feedback.impact(.card(.place))
        case .cpu:
            guard let index = cpuHand.firstIndex(of: card) else { return }
            cpuHand.remove(at: index)
            if let next = cpuStock.popLast() { cpuHand.insert(next, at: index) }
            // CPU の着手では触覚を鳴らさない（あなたの操作と区別するため）。
        }
        piles[pile].append(card)
        consecutiveFlips = 0
        restartPlayableNavigation()
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
        // 山札が尽きた人はめくらない（手札を出し切れば勝ち）。めくるのは山札が残っている側だけ（会長 QA 2026-10-24）。
        // 以前は尽きた人が自分側の台札を切り直して山札に抱え直していたため、出し切りかけた人の残りが 20 枚近くへ
        // 戻り、後半が 1 局の 6 割を占めていた（計測は `SpeedPacingTests`・PR の表）。
        // 両方とも尽きてどちらも出せないときだけ、台札をそれぞれ切り直して一番上を入れ替える。札は台札に残したまま
        // 手札へは戻さない（山札へ戻す形だと、両方の残りがまた 20 枚近くへ戻り同じ間延びになるため）。
        if humanStock.isEmpty && cpuStock.isEmpty {
            shuffle(&piles[0])
            shuffle(&piles[1])
        }
        if let card = humanStock.popLast() { piles[0].append(card) }
        if let card = cpuStock.popLast() { piles[1].append(card) }
        cpuArmedAt = nil
        stuckSince = nil
        selectedID = nil
        restartPlayableNavigation()
        services?.feedback.impact(.card(.flip))
        markProgress()
        cpuRun += 1
    }

    /// 場が動いた = 途中で捨てたら離脱として数える境目（#500）。1 ゲームに 1 回通せばよい。
    private func markProgress() {
        guard !hasProgressed else { return }
        hasProgressed = true
        services?.gameDidProgress(gameID: Self.gameID)
    }

    /// 動いている勝利タイムの計時を止め、ここまでの経過を `playedBefore` に積む。
    private func pausePlayClock() {
        guard let clock = playClock else { return }
        playedBefore += clock.duration
        playClock = nil
    }

    private func concludeGame(winner: Player) {
        self.winner = winner
        phase = .result
        isShowingPlayableNavigation = false
        selectedID = nil
        cpuArmedAt = nil
        stuckSince = nil
        timeoutEndsAt = nil
        pausePlayClock()
        let elapsed = playedBefore.timeInterval
        let seconds = max(1, Int(elapsed.rounded(.up)))
        winSeconds = winner == .human ? seconds : nil
        services?.feedback.notify(winner == .human ? .success : .error)
        finish(outcome: winner == .human ? .win : .loss, seconds: winSeconds)
    }

    private func concludeDraw() {
        isDraw = true
        winner = nil
        phase = .result
        isShowingPlayableNavigation = false
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
        restartPlayableNavigation()
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
