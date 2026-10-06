import Foundation
import Observation
import Core

// MARK: - Phase / Ending / Event

public enum ShiritoriPhase: Equatable, Sendable {
    /// 開始前（開始シート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 決着。
    case result
}

/// 何で終わったか。
public enum ShiritoriEnding: Equatable, Sendable {
    /// CPU が続けられない（取れる札が無い・札が尽きた）。**勝ち**（会長決裁 2026-09-21・#1245）。
    case cpuStuck
    /// プレイヤーが続けられない。**負け**。
    case playerStuck
    /// 制限時間が切れた。ノルマに届かないまま時間が尽きたので**負け固定**（届いていれば `quotaReached` で決着済み）。
    /// `endless` モードでは、札が残ったまま時間が尽きた負け。
    case timeUp
    /// プレイヤーが「ん」で終わる読みを選んだ。**負け**。
    case playerHitN
    /// CPU が「ん」で終わる読みを選ばされた。**勝ち**。
    case cpuHitN
    /// プレイヤーが取った札がノルマの枚数に届いた。**その瞬間に勝ち**（社長決裁 2026-09-21 の訂正・#1245）。
    case quotaReached
    /// 盤と山札の札がすべてなくなった（`endless` モード）。**パーフェクト**で、プレイヤーの勝ち（#1502）。
    case perfect
}

/// 直近の出来事。画面の一言バナー用。
public enum ShiritoriEvent: Equatable, Sendable {
    /// 札を取った。`isAlternate` は表読み以外（裏読み）で受けたとき。
    case played(by: ShiritoriOwner, reading: String, isAlternate: Bool)
    /// お手つき（しりとりが成立しない札を選んだ）。
    case miss
}

// MARK: - Model

/// カードしりとり（CPU 1 人との対戦・#1243）。プレイヤーが先手。
///
/// 盤に 30 枚の札を並べ、別の 1 枚を最初の「場の札」にする（山札は 50 枚で、`quota` モードは残りを使わない・
/// `endless` モードは残りを山札にして、札が取られるたびに空いた場所へ補充する・#1502）。手番の人は、場の札の読みの語尾に続く
/// 読みを持つ札を 1 枚選んで**取る**。取った札が新しい場の札になり、相手の番になる。
/// 相手が続けられなくなれば勝ち・自分が続けられなくなれば負け。
/// 取った札がノルマ（難易度ごとの枚数）に届いた瞬間も勝ちで、届かないまま時間が切れれば負け（#1245）。
///
/// ルール判定は `ShiritoriRules`（純粋関数）に寄せ、この型は**進行・時間・記録**だけを持つ。
/// 制限時間は**プレイヤーの手番のあいだだけ**減る（CPU の演出待ちで時間を取られないように）。
/// 中断データは持たない（1 局が短く、戻っても時間が止まった局になるだけのため）。
@MainActor
@Observable
public final class ShiritoriModel: AITurnGuarded {
    public private(set) var slots: [ShiritoriSlot] = []
    /// 場の札。開始前は nil。
    public private(set) var currentCard: ShiritoriCard?
    /// 場の札で**使った読み**（裏読みで取ったときは裏読み）。次の語尾はこれで決まる。
    public private(set) var currentReading = ""
    public private(set) var phase: ShiritoriPhase = .idle
    /// 「新規ゲーム」で失われる進行があるか（#1011）。対局中だけ。開始前と結果画面は捨てるものが無い。
    public var hasProgressToLose: Bool { phase == .playing }
    public private(set) var isPlayerTurn = false
    public private(set) var timeRemaining: Double = ShiritoriTime.initial
    public private(set) var ending: ShiritoriEnding?
    public private(set) var quota: ShiritoriQuota = .standard
    /// 今の局のモード。**局の開始時に焼き込み**、途中で設定を読み直さない（#1502・1 局 = 1 RuleSet）。
    public private(set) var mode: ShiritoriMode = .standard
    /// 山札（`endless` モードで、盤の札が取られたときの補充元）。
    public private(set) var stock: [ShiritoriCard] = []
    /// 取った枚数。`endless` では取った札を盤から下げて山札から補充するので、盤の並びから数えられない。
    public private(set) var playerCount = 0
    public private(set) var cpuCount = 0
    /// 何ゲーム目か（1 始まり）。
    public private(set) var gameNumber = 0
    public private(set) var lastEvent: ShiritoriEvent?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 決着後のみ意味を持つ。
    public private(set) var didPlayerWin = false
    /// 一時停止中か。ルールや新規ゲームのシートを開いている間、読んでいるだけで時間を取られないように
    /// 止める（#510）。次に札をタップした時点で再開する。
    public private(set) var isPaused = false
    /// CPU が次に取ろうとしている札。考えた手が決まってから確定するまでの間だけセットする
    /// （#1286: 取り札が瞬時に確定せず、カーソルが動いてから選ぶ演出のため）。
    public private(set) var cpuCursorSlot: Int?
    /// 時間切れの負けの記録を、広告で続ける選択肢を出すあいだ**保留している**か（#1717）。
    /// 結果画面は出ているが `gameDidFinish` はまだ呼んでいない。続けるなら取り消し、続けないなら `commitTimeUpLoss()` で記録する。
    public private(set) var isTimeUpLossPending = false
    /// この局で時間の延長をすでに使ったか（1 局 1 回）。
    public private(set) var hasExtendedTime = false

    private let services: GameServices?
    private let deck: [ShiritoriCard]
    let gameID = "shiritori"
    private let cpuDelay: Duration
    private let cpuCursorDelay: Duration
    private let cpuCursorStepDelay: Duration
    private var seed: UInt64?
    /// CPU の手番が二重に走らないようにする門番。
    var isRunningCPUTurns = false

    public init(
        services: GameServices? = nil,
        deck: [ShiritoriCard] = ShiritoriCard.deck,
        cpuDelay: Duration = .milliseconds(800),
        cpuCursorDelay: Duration = .zero,
        cpuCursorStepDelay: Duration = .zero,
        seed: UInt64? = nil
    ) {
        self.services = services
        self.deck = deck
        self.cpuDelay = cpuDelay
        self.cpuCursorDelay = cpuCursorDelay
        self.cpuCursorStepDelay = cpuCursorStepDelay
        self.seed = seed
    }

    // MARK: - 公開状態

    /// まだ誰にも取られていない札の枚数（盤の上のぶん）。
    public var remainingCount: Int { slots.filter { $0.owner == nil }.count }
    /// 山札の枚数。
    public var stockCount: Int { stock.count }

    /// 次に受ける語尾。開始前は nil。
    public var requiredTail: Character? {
        currentCard == nil ? nil : ShiritoriKana.tail(of: currentReading)
    }

    /// いまの取得枚数がノルマに届いているか。
    public var isQuotaMet: Bool { mode == .quota && quota.isMet(player: playerCount) }

    /// 評価リクエスト（#53）の判定用。引き分けは無い。
    public var reviewOutcome: GameOutcome { didPlayerWin ? .win : .loss }

    /// いま選べる札か（盤の見た目：取られていない・対局中・プレイヤーの番）。
    public func isSelectable(_ index: Int) -> Bool {
        phase == .playing && isPlayerTurn && slots.indices.contains(index) && slots[index].owner == nil
    }

    // MARK: - ゲーム開始

    public func startGame(quota: ShiritoriQuota? = nil, mode: ShiritoriMode? = nil) {
        commitTimeUpLoss()   // 保留中の負けは、始め直す前に記録する（前の局の記録を落とさない）
        if let quota { self.quota = quota }
        if let mode { self.mode = mode }
        let deal: ShiritoriDeal
        if var generator = makeGenerator() {
            deal = ShiritoriRules.deal(deck: deck, mode: self.mode, quota: self.quota, using: &generator)
            seed = generator.next()   // 次ゲームで同じ配りにならないよう種を進める
        } else {
            var generator = SystemRandomNumberGenerator()
            deal = ShiritoriRules.deal(deck: deck, mode: self.mode, quota: self.quota, using: &generator)
        }

        slots = deal.board.map { ShiritoriSlot(card: $0) }
        stock = deal.stock
        playerCount = 0
        cpuCount = 0
        currentCard = deal.opener
        currentReading = deal.opener.primaryReading
        timeRemaining = ShiritoriTime.initial
        ending = nil
        didPlayerWin = false
        recordResult = nil
        lastEvent = nil
        gameNumber += 1
        phase = .playing
        isPlayerTurn = true
        isPaused = false
        hasExtendedTime = false
        cpuCursorSlot = nil

        services?.feedback.impact(.medium)   // 札が配られた
        // 1 ゲーム = 1 プレイ。中断データは持たないので、画面を離れたら失われる（#663）。
        // とことんモードは難易度の概念が無いので level を送らない（ノルマ側の段階別集計に混ぜない）。
        services?.gameDidRestart(gameID: gameID, level: self.mode == .quota ? self.quota.analyticsLevel : nil)
        services?.gameWillNotResume(gameID: gameID)

        // 最初の場の札に続けられる札が無いと何もできない。`openerIndex` が避けるので通常は起きない。
        if availableMoves.isEmpty { finish(.playerStuck) }
    }

    private func makeGenerator() -> SplitMix64? {
        seed.map { SplitMix64(seed: $0) }
    }

    // MARK: - プレイヤーの操作

    /// 札をタップして取る。しりとりが成立しなければお手つき（時間 -5 秒・手番はそのまま）。
    public func select(_ index: Int) {
        guard isSelectable(index) else { return }
        isPaused = false
        guard let tail = requiredTail,
              let reading = ShiritoriRules.acceptingReading(of: slots[index].card, after: tail) else {
            miss()
            return
        }
        services?.feedback.impact(.medium)
        claim(index, reading: reading, by: .player)
    }

    /// 時間を進める。**プレイヤーの手番のあいだだけ**減り、0 になったら時間切れで終わる。
    public func tick(_ seconds: Double) {
        guard phase == .playing, isPlayerTurn, !isPaused, seconds > 0 else { return }
        timeRemaining = max(0, timeRemaining - seconds)
        if timeRemaining <= 0 { finish(.timeUp) }
    }

    /// 対局中だけ止める（開始前・決着後は止めるものが無い）。
    public func pause() {
        if phase == .playing { isPaused = true }
    }

    private func miss() {
        lastEvent = .miss
        services?.feedback.notify(.warning)
        timeRemaining = max(0, timeRemaining - ShiritoriTime.missPenalty)
        if timeRemaining <= 0 { finish(.timeUp) }
    }

    // MARK: - 進行

    private var availableMoves: [ShiritoriMove] {
        requiredTail.map { ShiritoriRules.moves(slots: slots, after: $0) } ?? []
    }

    private func claim(_ index: Int, reading: String, by owner: ShiritoriOwner) {
        let card = slots[index].card
        slots[index].owner = owner
        slots[index].claimedReading = reading
        switch owner {
        case .player: playerCount += 1
        case .cpu:    cpuCount += 1
        }
        currentCard = card
        currentReading = reading
        lastEvent = .played(by: owner, reading: reading, isAlternate: reading != card.primaryReading)
        // 札を取った = 捨てたら途中離脱として数える局面。
        services?.gameDidProgress(gameID: gameID)

        // 「ん」で終わる読みを選んだ側が、その場で負ける（ノルマ到達より優先。その札でノルマに届く場合も負け）。
        if ShiritoriRules.endsWithN(reading) {
            finish(owner == .player ? .playerHitN : .cpuHitN)
            return
        }

        // とことんモード: 取った札は場の札へ移ったので、空いた場所へ山札から補充する（山札が尽きたら補充なし）。
        // 補充してから行き詰まりを判定する（補充された札で続けられることがある）。
        if mode == .endless, !stock.isEmpty {
            slots[index] = ShiritoriSlot(card: stock.remove(at: refillIndex(after: owner, reading: reading)))
        }
        // 盤にも山札にも札が 1 枚も残っていなければパーフェクト（誰が最後の 1 枚を取っても）。
        if mode == .endless, remainingCount == 0, stock.isEmpty {
            if owner == .player { timeRemaining += ShiritoriTime.successBonus }
            finish(.perfect)
            return
        }

        switch owner {
        case .player:
            timeRemaining += ShiritoriTime.successBonus
            isPlayerTurn = false
            if isQuotaMet {
                finish(.quotaReached)
                return
            }
            if availableMoves.isEmpty { finish(.cpuStuck) }   // CPU が受けられる札が無い（札が尽きた場合も）
        case .cpu:
            isPlayerTurn = true
            if availableMoves.isEmpty { finish(.playerStuck) }
        }
    }

    /// 山札のどれを補充するか。CPU が取った直後に、プレイヤーが続けられる札が盤に 1 枚も無いときだけ、
    /// 続けられる札（「ん」で終わらないものを優先）を山札から先に出す（#1659: とことんは CPU が盤の左から
    /// 取り進めるため、山札に後続が残っているのにプレイヤーが詰んで負けになる局が約半数あった）。
    /// プレイヤーが取った直後は触らない（CPU を詰ませて勝つ道を残す）。
    private func refillIndex(after owner: ShiritoriOwner, reading: String) -> Int {
        guard owner == .cpu, let tail = ShiritoriKana.tail(of: reading),
              ShiritoriRules.moves(slots: slots, after: tail).isEmpty else { return 0 }
        let followers = stock.indices.compactMap { i -> (index: Int, reading: String)? in
            ShiritoriRules.acceptingReading(of: stock[i], after: tail).map { (i, $0) }
        }
        return (followers.first { !ShiritoriRules.endsWithN($0.reading) } ?? followers.first)?.index ?? 0
    }

    // MARK: - 広告で時間を延長（#1717）

    /// 延長で足す秒数（会長指示 2026-10-02: 15 秒では少なすぎるので 30 秒）。
    static let extensionSeconds: Double = ShiritoriTime.adExtension

    /// 時間切れの結果画面で、広告を見て続けられるか。1 局 1 回・時間切れの負けに限る
    /// （詰み・「ん」の負けは時間では救えないので対象外）。
    public var canExtendTime: Bool {
        phase == .result && ending == .timeUp && isTimeUpLossPending && !hasExtendedTime
    }

    /// 広告を見終えたあと、時間を足して同じ局を再開する。
    ///
    /// - Parameter serial: 広告を出す**前**に控えた `gameNumber`。視聴中に局が入れ替わっていたら
    ///   延長を乗せずに false を返す（局ガード）。
    /// - Returns: 延長したか。
    public func extendTimeAfterAd(forGame serial: Int) -> Bool {
        guard serial == gameNumber, canExtendTime else { return false }
        isTimeUpLossPending = false
        hasExtendedTime = true
        ending = nil
        phase = .playing
        isPlayerTurn = true
        isPaused = false
        timeRemaining = Self.extensionSeconds
        services?.feedback.notify(.success)
        // 時間切れで `game_end` を送り済みなので、続きは新しいプレイとして数える。
        services?.gameDidRestart(gameID: gameID, level: mode == .quota ? quota.analyticsLevel : nil)
        services?.gameWillNotResume(gameID: gameID)
        return true
    }

    /// 保留していた時間切れの負けを記録する。続けない・続けられなかったとき、局を始め直すとき、画面を離れるときに呼ぶ。冪等。
    public func commitTimeUpLoss() {
        guard isTimeUpLossPending else { return }
        isTimeUpLossPending = false
        recordFinish()
    }

    private func finish(_ ending: ShiritoriEnding) {
        self.ending = ending
        phase = .result
        isPlayerTurn = false
        switch ending {
        case .playerHitN, .playerStuck, .timeUp: didPlayerWin = false
        case .cpuHitN, .cpuStuck, .quotaReached, .perfect: didPlayerWin = true
        }
        // 広告で続けられる時間切れは、続けるかを選ぶまで負けを記録しない（#1717）。
        // 広告を出せない構成（services なし）は従来どおりその場で記録する。
        // 解析の `game_end`（loss）だけは今送る（#1375 と同じ流儀）。記録を後に回しても、結果画面で離れて
        // `gameDidLeave` が先に走ると休憩・離脱と判定され、負けが `quit` になる・欠ける。結果画面に居た時間も
        // `duration_sec` に乗せない。続けるなら `extendTimeAfterAd` が新しいプレイとして数え直す。
        if ending == .timeUp, !hasExtendedTime, let services {
            isTimeUpLossPending = true
            services.feedback.notify(.error)
            services.gameDidDecide(gameID: gameID, outcome: .loss)
            return
        }
        services?.feedback.notify(didPlayerWin ? .success : .error)
        recordFinish()
    }

    private func recordFinish() {
        // 従来のモードの記録は variant nil のまま（保存先を変えない）。とことんは別枠で、順位表へは送らない。
        let variant = mode.scoreVariant
        recordResult = services?.gameDidFinish(
            gameID: gameID, outcome: reviewOutcome,
            score: GameScore(variant: variant?.key, variantLabel: variant?.label, isLeaderboardEligible: variant == nil)
        )
    }

    // MARK: - CPU

    /// CPU の手番なら 1 手進める。決着か人間の手番になったら止まる。
    ///
    /// 手が決まったら、まだ取られていない札を盤の並び順（左から右）に対象までなぞってから確定する
    /// （#1286・会長指摘 2026-09-23: 対象へ一瞬で止まるだけでは「動いた」と感じられなかった。
    /// 通過する札は `cpuCursorStepDelay`、最後に止まる対象だけ `cpuCursorDelay` の間見せる。
    /// `cpuDelay` は「考え始めるまでの間」のまま変えない）。
    public func runCPUTurnIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            guard phase == .playing, !isPlayerTurn else { return }
            if cpuDelay > .zero {
                guard await pauseCPUTurn(for: cpuDelay) else { return }
                guard phase == .playing, !isPlayerTurn else { return }
            }
            guard let tail = requiredTail,
                  let move = ShiritoriRules.cpuMove(slots: slots, after: tail) else {
                finish(.cpuStuck)
                return
            }
            let sweep = slots.indices.filter { $0 <= move.slot && slots[$0].owner == nil }
            for (offset, slot) in sweep.enumerated() {
                cpuCursorSlot = slot
                let isFinal = offset == sweep.count - 1
                let delay = isFinal ? cpuCursorDelay : cpuCursorStepDelay
                guard delay > .zero else { continue }
                guard await pauseCPUTurn(for: delay) else {
                    cpuCursorSlot = nil
                    return
                }
                guard phase == .playing, !isPlayerTurn else {
                    cpuCursorSlot = nil
                    return
                }
            }
            cpuCursorSlot = nil
            claim(move.slot, reading: move.reading, by: .cpu)
        }
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    func configureForTesting(
        opener: ShiritoriCard,
        board: [ShiritoriCard],
        quota: ShiritoriQuota = .normal,
        mode: ShiritoriMode = .quota,
        stock: [ShiritoriCard] = [],
        isPlayerTurn: Bool = true
    ) {
        slots = board.map { ShiritoriSlot(card: $0) }
        self.stock = stock
        playerCount = 0
        cpuCount = 0
        currentCard = opener
        currentReading = opener.primaryReading
        self.quota = quota
        self.mode = mode
        timeRemaining = ShiritoriTime.initial
        ending = nil
        didPlayerWin = false
        lastEvent = nil
        gameNumber = 1
        phase = .playing
        isTimeUpLossPending = false
        hasExtendedTime = false
        self.isPlayerTurn = isPlayerTurn
    }
}

#if DEBUG
extension ShiritoriModel {
    /// 撮影用: CPU が対象スロットへカーソルを向けている状態を再現する
    /// （`cpuCursorSlot` は中断データを持たないため注入できず、シミュレータは自動タップできない・#1286）。
    func debugShowCPUCursor() {
        configureForTesting(
            opener: ShiritoriCard(.apple, "りんご"),
            board: [ShiritoriCard(.gorilla, "ごりら"), ShiritoriCard(.spinningTop, "こま")],
            isPlayerTurn: false
        )
        cpuCursorSlot = 0
        // 本物の CPU 手番タスクが横から追い越して確定させないように、走者の枠を埋めておく。
        isRunningCPUTurns = true
    }
}
#endif
