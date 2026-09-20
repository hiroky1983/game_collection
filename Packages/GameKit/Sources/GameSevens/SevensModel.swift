import Foundation
import Observation
import Core

// MARK: - Phase

public enum SevensPhase: String, Equatable, Sendable, Codable {
    /// 開始前（スタートシート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 決着（勝者が出ている）。
    case result
}

// MARK: - Snapshot

struct SevensSnapshot: Codable {
    let hands: [[SevensCard]]
    let board: [SevensSuitRange]
    let currentPlayer: Int
    let gameNumber: Int
    /// 各プレイヤーの直近の動き（「♦7」「パス」など）。
    let lastActions: [String]?
}

// MARK: - Model

/// 七並べ（CPU 3人との対戦）。プレイヤーは常に番号 0（#1198）。
///
/// ルール判定は `SevensRules`（純粋関数）に寄せ、この型は**進行・永続化・演出**だけを持つ。
/// 大富豪と違い役の強さ判定・革命・8切りが無く、出せる手が無ければ自動でパスするだけなので、
/// `pass()` 以外の操作は「手札のカードをタップして出す」の1点に絞れる。
@MainActor
@Observable
public final class SevensModel: AITurnGuarded {
    /// 人間プレイヤーの番号。
    public static let humanIndex = 0
    /// 参加人数（人間1 + CPU3）。
    public static let playerCount = SevensRules.playerCount
    /// 山札の枚数（52枚、ジョーカー無し）。「配ったばかりか」の判定に使う。
    private static let deckCount = SevensCard.makeDeck().count

    public private(set) var hands: [[SevensCard]] = Array(repeating: [], count: playerCount)
    /// スートごとの場の開通状況（index = `SevensSuit.rawValue`）。
    public private(set) var board: [SevensSuitRange] = SevensRules.emptyBoard()
    public private(set) var currentPlayer: Int = humanIndex
    public private(set) var phase: SevensPhase = .idle
    /// 手札を最初になくした人。対局中は nil。
    public private(set) var winner: Int?
    /// 何ゲーム目か（1 始まり）。
    public private(set) var gameNumber = 0
    /// 各プレイヤーの直近の動き。画面のバッジ表示用。
    public private(set) var lastActions: [String] = Array(repeating: "", count: playerCount)
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    let gameID = "sevens"
    private let cpuDelay: Duration
    private var seed: UInt64?
    /// CPU の連続手番が二重に走らないようにする門番。
    var isRunningCPUTurns = false

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(500),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        self.seed = seed
        if let snap = services?.snapshots.load(SevensSnapshot.self, for: gameID) {
            hands         = snap.hands
            board         = snap.board
            currentPlayer = snap.currentPlayer
            gameNumber    = snap.gameNumber
            // 直近の動きのバッジは、人数分そろっているときだけ戻す。旧データには無く、
            // 壊れた配列をそのまま入れると `lastActions[index]` の参照で落ちるため。
            if let actions = snap.lastActions, actions.count == Self.playerCount {
                lastActions = actions
            }
            phase = .playing
        }
    }

    // MARK: - 公開状態

    /// 人間の手札（画面に並べる順にソート済み）。
    public var playerHand: [SevensCard] { hands[Self.humanIndex] }

    /// 人間の手番か。
    public var isPlayerTurn: Bool { phase == .playing && currentPlayer == Self.humanIndex }

    /// 人間が勝ったか（決着後のみ意味を持つ）。
    public var didPlayerWin: Bool { winner == Self.humanIndex }

    /// 出せる手が無く、パスするしかないか。
    public var mustPass: Bool {
        isPlayerTurn && SevensRules.playableCards(hand: playerHand, board: board).isEmpty
    }

    /// 評価リクエスト（#53）の判定用。勝てば勝ち、負ければ負け（引き分けは無い）。
    public var reviewOutcome: GameOutcome {
        guard let winner else { return .draw }
        return winner == Self.humanIndex ? .win : .loss
    }

    public func playerName(_ index: Int) -> String {
        index == Self.humanIndex ? "あなた" : "CPU\(index)"
    }

    /// そのカードが今出せるか（手札1枚ずつのタップ判定に使う）。
    public func canPlay(_ card: SevensCard) -> Bool {
        isPlayerTurn && SevensRules.canPlay(card, board: board)
    }

    // MARK: - ゲーム開始

    public func startGame() {
        var deck = SevensCard.makeDeck()
        if var generator = makeGenerator() {
            deck.shuffle(using: &generator)
            seed = generator.next()   // 次ゲームで同じ配りにならないよう種を進める
        } else {
            deck.shuffle()
        }

        var dealt: [[SevensCard]] = Array(repeating: [], count: Self.playerCount)
        for (offset, card) in deck.enumerated() {
            dealt[offset % Self.playerCount].append(card)
        }
        dealt = dealt.map { $0.sorted { $0.sortKey < $1.sortKey } }

        hands = dealt
        board = SevensRules.emptyBoard()
        winner = nil
        lastActions = Array(repeating: "", count: Self.playerCount)
        gameNumber += 1
        currentPlayer = SevensRules.openingPlayer(hands: dealt)
        recordResult = nil
        phase = .playing

        services?.feedback.impact(.medium)   // カードが配られた
        // 配ったばかりの局は `persist()` 側のガードで保存されず、前局の中断データが消えるだけになる
        // （1手目を出した時点で改めて保存される）。
        persist()
        // 1 ゲーム = 1 プレイ。中断からの復元は init が状態を戻すだけでここを通らないので数えない。
        services?.gameDidRestart(gameID: gameID)
    }

    private func makeGenerator() -> SplitMix64? {
        seed.map { SplitMix64(seed: $0) }
    }

    // MARK: - 人間の操作

    /// 手札のカードをタップして出す。出せない札なら警告だけ返す。
    public func play(_ card: SevensCard) {
        guard isPlayerTurn else { return }
        guard SevensRules.canPlay(card, board: board) else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.medium)
        playCard(card, by: Self.humanIndex)
    }

    /// 出せる手が無いときのパス。出せる手があるうちは何もしない（強制はここで担保する）。
    public func pass() {
        guard isPlayerTurn else { return }
        guard mustPass else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.light)
        passTurn(by: Self.humanIndex)
    }

    // MARK: - 進行

    private func playCard(_ card: SevensCard, by player: Int) {
        hands[player] = hands[player].filter { $0.id != card.id }
        board = SevensRules.apply(card, to: board)
        // 札が出た = 捨てたら途中離脱として数える局面。
        services?.gameDidProgress(gameID: gameID)

        let finished = hands[player].isEmpty
        lastActions[player] = card.suit.symbol + card.rankLabel + (finished ? " あがり！" : "")

        if finished {
            concludeGame(winner: player)
            return
        }

        advanceTurn(from: player)
        persist()
    }

    private func passTurn(by player: Int) {
        lastActions[player] = "パス"
        advanceTurn(from: player)
        persist()
    }

    private func advanceTurn(from player: Int) {
        currentPlayer = (player + 1) % Self.playerCount
    }

    private func concludeGame(winner: Int) {
        self.winner = winner
        phase = .result

        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore())
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - CPU

    /// CPU の手番が続く限り進める。人間の手番になるか決着したら止まる。
    public func runCPUTurnsIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            while phase == .playing, currentPlayer != Self.humanIndex {
                guard !Task.isCancelled else { return }
                if cpuDelay > .zero {
                    guard await pauseCPUTurn(for: cpuDelay) else { return }
                    guard phase == .playing, currentPlayer != Self.humanIndex else { return }
                }
                performCPUTurn(currentPlayer)
            }
        }
    }

    /// CPU の1手。出せる手が無ければパス。
    private func performCPUTurn(_ player: Int) {
        if let card = SevensRules.greedyPlay(hand: hands[player], board: board) {
            playCard(card, by: player)
        } else {
            passTurn(by: player)
        }
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    func configureForTesting(
        hands: [[SevensCard]],
        board: [SevensSuitRange] = SevensRules.emptyBoard(),
        currentPlayer: Int = SevensModel.humanIndex,
        gameNumber: Int = 1
    ) {
        self.hands = hands.map { $0.sorted { $0.sortKey < $1.sortKey } }
        self.board = board
        self.currentPlayer = currentPlayer
        self.gameNumber = gameNumber
        winner = nil
        lastActions = Array(repeating: "", count: Self.playerCount)
        phase = .playing
        persist()
    }

    // MARK: - 永続化

    /// 配ったばかりで1手も進んでいない局か。
    ///
    /// 場が空のときは全員がまだ何も出していない（7 を持つ人しか出せない = 必ず1手目はカードを出す手）
    /// ので、「4人の手札の合計が山札と同じ」で判定できる（大富豪の `isUntouchedDeal` と同じ考え方）。
    private var isUntouchedDeal: Bool {
        hands.reduce(0) { $0 + $1.count } == Self.deckCount
    }

    private func persist() {
        guard phase == .playing, !isUntouchedDeal else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = SevensSnapshot(
            hands: hands,
            board: board,
            currentPlayer: currentPlayer,
            gameNumber: gameNumber,
            lastActions: lastActions
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
