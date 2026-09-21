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
    /// CPU が続けられない（取れる札が無い・札が尽きた）。ノルマで勝敗が決まる。
    case cpuStuck
    /// プレイヤーが続けられない。ノルマで勝敗が決まる。
    case playerStuck
    /// 制限時間が切れた。ノルマで勝敗が決まる。
    case timeUp
    /// プレイヤーが「ん」で終わる読みを選んだ。**ノルマに関係なく負け**。
    case playerHitN
    /// CPU が「ん」で終わる読みを選ばされた。**ノルマに関係なく勝ち**。
    case cpuHitN
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
/// 盤に 19 枚の札を並べ、残る 1 枚を最初の「場の札」にする。手番の人は、場の札の読みの語尾に続く
/// 読みを持つ札を 1 枚選んで**取る**。取った札が新しい場の札になり、相手の番になる。
/// 誰かが続けられなくなる・制限時間が切れると終わり、取った札の割合がノルマ（難易度）を満たせば勝ち。
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
    public private(set) var isPlayerTurn = false
    public private(set) var timeRemaining: Double = ShiritoriTime.initial
    public private(set) var ending: ShiritoriEnding?
    public private(set) var quota: ShiritoriQuota = .standard
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

    private let services: GameServices?
    private let deck: [ShiritoriCard]
    let gameID = "shiritori"
    private let cpuDelay: Duration
    private var seed: UInt64?
    /// CPU の手番が二重に走らないようにする門番。
    var isRunningCPUTurns = false

    public init(
        services: GameServices? = nil,
        deck: [ShiritoriCard] = ShiritoriCard.deck,
        cpuDelay: Duration = .milliseconds(800),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.deck = deck
        self.cpuDelay = cpuDelay
        self.seed = seed
    }

    // MARK: - 公開状態

    public var playerCount: Int { slots.filter { $0.owner == .player }.count }
    public var cpuCount: Int { slots.filter { $0.owner == .cpu }.count }
    /// まだ誰にも取られていない札の枚数。
    public var remainingCount: Int { slots.filter { $0.owner == nil }.count }

    /// 次に受ける語尾。開始前は nil。
    public var requiredTail: Character? {
        currentCard == nil ? nil : ShiritoriKana.tail(of: currentReading)
    }

    /// 決着時点でノルマを満たしているか（「ん」の即決着は判定しない。負け・勝ちが先に決まる）。
    public var isQuotaMet: Bool { quota.isMet(player: playerCount, cpu: cpuCount) }

    /// 評価リクエスト（#53）の判定用。引き分けは無い。
    public var reviewOutcome: GameOutcome { didPlayerWin ? .win : .loss }

    /// いま選べる札か（盤の見た目：取られていない・対局中・プレイヤーの番）。
    public func isSelectable(_ index: Int) -> Bool {
        phase == .playing && isPlayerTurn && slots.indices.contains(index) && slots[index].owner == nil
    }

    // MARK: - ゲーム開始

    public func startGame(quota: ShiritoriQuota? = nil) {
        if let quota { self.quota = quota }
        var cards = deck
        if var generator = makeGenerator() {
            cards.shuffle(using: &generator)
            seed = generator.next()   // 次ゲームで同じ配りにならないよう種を進める
        } else {
            cards.shuffle()
        }
        let openerIndex = ShiritoriRules.openerIndex(in: cards) ?? 0
        let opener = cards.remove(at: openerIndex)

        slots = cards.map { ShiritoriSlot(card: $0) }
        currentCard = opener
        currentReading = opener.primaryReading
        timeRemaining = ShiritoriTime.initial
        ending = nil
        didPlayerWin = false
        recordResult = nil
        lastEvent = nil
        gameNumber += 1
        phase = .playing
        isPlayerTurn = true
        isPaused = false

        services?.feedback.impact(.medium)   // 札が配られた
        // 1 ゲーム = 1 プレイ。中断データは持たないので、画面を離れたら失われる（#663）。
        services?.gameDidRestart(gameID: gameID, level: self.quota.analyticsLevel)
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
        currentCard = card
        currentReading = reading
        lastEvent = .played(by: owner, reading: reading, isAlternate: reading != card.primaryReading)
        // 札を取った = 捨てたら途中離脱として数える局面。
        services?.gameDidProgress(gameID: gameID)

        // 「ん」で終わる読みを選んだ側が、その場で負ける（ノルマ判定より優先）。
        if ShiritoriRules.endsWithN(reading) {
            finish(owner == .player ? .playerHitN : .cpuHitN)
            return
        }

        switch owner {
        case .player:
            timeRemaining += ShiritoriTime.successBonus
            isPlayerTurn = false
            if availableMoves.isEmpty { finish(.cpuStuck) }   // CPU が受けられる札が無い（札が尽きた場合も）
        case .cpu:
            isPlayerTurn = true
            if availableMoves.isEmpty { finish(.playerStuck) }
        }
    }

    private func finish(_ ending: ShiritoriEnding) {
        self.ending = ending
        phase = .result
        isPlayerTurn = false
        switch ending {
        case .playerHitN:                     didPlayerWin = false
        case .cpuHitN:                        didPlayerWin = true
        case .cpuStuck, .playerStuck, .timeUp: didPlayerWin = isQuotaMet
        }
        services?.feedback.notify(didPlayerWin ? .success : .error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore())
    }

    // MARK: - CPU

    /// CPU の手番なら 1 手進める。決着か人間の手番になったら止まる。
    public func runCPUTurnIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            guard phase == .playing, !isPlayerTurn else { return }
            if cpuDelay > .zero {
                guard await pauseCPUTurn(for: cpuDelay) else { return }
                guard phase == .playing, !isPlayerTurn else { return }
            }
            performCPUTurn()
        }
    }

    private func performCPUTurn() {
        guard let tail = requiredTail,
              let move = ShiritoriRules.cpuMove(slots: slots, after: tail) else {
            finish(.cpuStuck)
            return
        }
        claim(move.slot, reading: move.reading, by: .cpu)
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    func configureForTesting(
        opener: ShiritoriCard,
        board: [ShiritoriCard],
        quota: ShiritoriQuota = .normal,
        isPlayerTurn: Bool = true
    ) {
        slots = board.map { ShiritoriSlot(card: $0) }
        currentCard = opener
        currentReading = opener.primaryReading
        self.quota = quota
        timeRemaining = ShiritoriTime.initial
        ending = nil
        didPlayerWin = false
        lastEvent = nil
        gameNumber = 1
        phase = .playing
        self.isPlayerTurn = isPlayerTurn
    }
}
