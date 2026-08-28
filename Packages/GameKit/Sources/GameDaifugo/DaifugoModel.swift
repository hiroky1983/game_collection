import Foundation
import Observation
import Core

// MARK: - Phase

public enum DaifugoPhase: String, Equatable, Sendable, Codable {
    /// 開始前（スタートシート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 1ゲームの決着（階級が出ている）。
    case result
}

// MARK: - Snapshot

struct DaifugoSnapshot: Codable {
    let hands: [[DaifugoCard]]
    let field: [DaifugoCard]
    let fieldOwner: Int?
    let currentPlayer: Int
    let passedPlayers: [Int]
    let isRevolution: Bool
    let finishOrder: [Int]
    let fouls: [Int]
    let gameNumber: Int
    let lastRanking: [Int]
    /// 各プレイヤーの直近の動き（「パス」「8切り！」など）（#193）。
    /// **旧バージョンの保存データには存在しない**ため optional にして、欠けていても復元を失敗させない
    /// （`JSONDecoder` は非 optional のキーが無いと丸ごと復号に失敗し、中断データが消える）。
    let lastActions: [String]?
}

// MARK: - Model

/// 大富豪（CPU 3人との対戦）。プレイヤーは常に番号 0。
///
/// ルール判定は `DaifugoRules`（純粋関数）に寄せ、この型は**進行・永続化・演出**だけを持つ。
@MainActor
@Observable
public final class DaifugoModel {
    /// 人間プレイヤーの番号。
    public static let humanIndex = 0
    /// 参加人数（人間1 + CPU3）。
    public static let playerCount = 4

    public private(set) var hands: [[DaifugoCard]] = Array(repeating: [], count: playerCount)
    public private(set) var field: [DaifugoCard] = []
    public private(set) var fieldOwner: Int?
    public private(set) var currentPlayer: Int = humanIndex
    public private(set) var passedPlayers: Set<Int> = []
    public private(set) var isRevolution = false
    public private(set) var phase: DaifugoPhase = .idle
    /// 手札が尽きた順のプレイヤー番号（反則上がりを含む）。
    public private(set) var finishOrder: [Int] = []
    /// 反則上がりしたプレイヤー番号。
    public private(set) var fouls: Set<Int> = []
    /// 投了したプレイヤー番号（#194）。今のところ人間だけが投了できる。
    public private(set) var resigned: Set<Int> = []
    /// 決着後の最終順位（1位から順のプレイヤー番号）。対局中は空。
    public private(set) var ranking: [Int] = []
    /// 何ゲーム目か（1 始まり）。カード交換の有無の判定に使う。
    public private(set) var gameNumber = 0
    /// 直前ゲームの最終順位。次ゲームの交換と親決めに使う。
    public private(set) var lastRanking: [Int] = []
    /// 直前に行ったカード交換の内訳（リザルト直後の説明に使う）。
    public private(set) var lastTransfers: [DaifugoTransfer] = []
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?
    /// 各プレイヤーの直近の動き（「パス」「8切り！」など）。画面のバッジ表示用。
    public private(set) var lastActions: [String] = Array(repeating: "", count: playerCount)
    /// 手札から選択中のカード ID。
    public private(set) var selected: Set<Int> = []

    private let services: GameServices?
    private let gameID = "daifugo"
    private let cpuDelay: Duration
    private var seed: UInt64?
    /// ヒント表示のオン / オフ（#190）。設定画面はハブ側にしか無く**対局中には変わらない**ため、
    /// `@Observable` の追跡対象にはせず参照のたびに読む。
    private let hints: FeedbackPreference
    /// CPU の連続手番が二重に走らないようにする門番（View から複数回呼ばれても1本に保つ）。
    private var isRunningCPUTurns = false
    /// 「結果まで進める」が押されたか（#191）。以降の CPU 手番は間合いを取らずに消化する。
    public private(set) var isSkippingToResult = false

    /// 自分が上がった後の消化試合で使う間合い（#191）。自分の操作が無い区間なので短くする。
    static let finishedCPUDelay: Duration = .milliseconds(120)
    /// 自分が上がった後に消化した CPU の手番数（#191）。
    /// 手番数 × `finishedCPUDelay` が消化試合の待ち時間になるため、テストで上限を見張る。
    private(set) var cpuTurnsAfterPlayerFinished = 0

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(650),
        seed: UInt64? = nil,
        hints: FeedbackPreference = .hints
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        self.seed = seed
        self.hints = hints
        if let snap = services?.snapshots.load(DaifugoSnapshot.self, for: gameID) {
            hands         = snap.hands
            field         = snap.field
            fieldOwner    = snap.fieldOwner
            currentPlayer = snap.currentPlayer
            passedPlayers = Set(snap.passedPlayers)
            isRevolution  = snap.isRevolution
            finishOrder   = snap.finishOrder
            fouls         = Set(snap.fouls)
            gameNumber    = snap.gameNumber
            lastRanking   = snap.lastRanking
            // 直近の動きのバッジは、人数分そろっているときだけ戻す（#193）。旧データには無く、
            // 壊れた配列をそのまま入れると `lastActions[index]` の参照で落ちるため。
            if let actions = snap.lastActions, actions.count == Self.playerCount {
                lastActions = actions
            }
            phase         = .playing
        }
    }

    // MARK: - 公開状態

    /// 人間の手札（画面に並べる順にソート済み）。
    public var playerHand: [DaifugoCard] { hands[Self.humanIndex] }

    /// 人間がもう上がっているか。
    public var isPlayerFinished: Bool { hands[Self.humanIndex].isEmpty && phase != .idle }

    /// 人間の手番か（上がっていれば false）。
    public var isPlayerTurn: Bool { phase == .playing && currentPlayer == Self.humanIndex }

    /// 「結果まで進める」を出せるか（#191）。自分が上がっていて、まだ決着していないとき。
    public var canSkipToResult: Bool { phase == .playing && isPlayerFinished }

    /// 投了できるか（#194）。対局中で、まだ上がっていないときだけ。
    /// 上がった後は勝ち取った階級を捨てる操作になってしまうので出さない（代わりに「結果まで進める」がある）。
    public var canResign: Bool { phase == .playing && !isPlayerFinished }

    /// 人間の最終順位（0 始まり）。決着していなければ nil。
    public var playerPlace: Int? { ranking.firstIndex(of: Self.humanIndex) }

    /// 人間の階級名。決着していなければ空文字。
    public var playerTitle: String {
        playerPlace.map { DaifugoRules.title(forPlace: $0) } ?? ""
    }

    /// 選択中のカードを今の場に出せるか。
    public var canPlaySelection: Bool {
        guard isPlayerTurn, !selected.isEmpty else { return false }
        return DaifugoRules.isValidPlay(selectedCards, field: field, isRevolution: isRevolution)
    }

    /// 人間がパスできるか（親のときはパスできない = 場を流せないため）。
    public var canPass: Bool { isPlayerTurn && !field.isEmpty }

    /// 手札のヒント（#190）。強調するものが無いときは nil。
    ///
    /// nil になるのは、設定でオフ / 自分の手番でない / 手札が空 / **手札すべてが出せる**
    /// （場が流れている等）の4通り。最後の1つを弾くのは、全札に枠が付くだけの
    /// 情報量ゼロの強調を出さないため。逆に**1枚も出せない**ときは全札を暗く落とし、
    /// 「パスするしかない」ことを伝える。
    public var handHint: DaifugoHandHint? {
        guard hints.isEnabled, isPlayerTurn, !playerHand.isEmpty else { return nil }
        let playable = DaifugoRules.playableCardIDs(
            hand: playerHand, field: field, isRevolution: isRevolution
        )
        guard playable.count < playerHand.count else { return nil }
        return DaifugoHandHint(
            playable: playable,
            unplayable: Set(playerHand.map(\.id)).subtracting(playable)
        )
    }

    /// 選択中の組を出せない理由の1行表示（#190）。出せるとき・未選択・ヒントがオフなら nil。
    public var selectionIssue: String? {
        guard hints.isEnabled, isPlayerTurn else { return nil }
        return DaifugoRules.rejectionReason(selectedCards, field: field, isRevolution: isRevolution)
    }

    /// 評価リクエスト（#53）の判定用。大富豪なら勝ち、大貧民なら負け、間は引き分け扱い。
    public var reviewOutcome: GameOutcome {
        guard let place = playerPlace else { return .draw }
        if place == 0 { return .win }
        if place == ranking.count - 1 { return .loss }
        return .draw
    }

    public func playerName(_ index: Int) -> String {
        index == Self.humanIndex ? "あなた" : "CPU\(index)"
    }

    private var selectedCards: [DaifugoCard] {
        playerHand.filter { selected.contains($0.id) }
    }

    // MARK: - ゲーム開始

    /// 新しい1ゲームを始める。2ゲーム目以降は前ゲームの階級に応じてカード交換を行う。
    public func startGame() {
        var deck = DaifugoCard.makeDeck()
        if var generator = makeGenerator() {
            deck.shuffle(using: &generator)
            seed = generator.next()   // 次ゲームで同じ配りにならないよう種を進める
        } else {
            deck.shuffle()
        }

        var dealt: [[DaifugoCard]] = Array(repeating: [], count: Self.playerCount)
        // 53枚は割り切れないので、配り始めをゲームごとにずらして枚数の偏りを固定しない。
        let firstReceiver = gameNumber % Self.playerCount
        for (offset, card) in deck.enumerated() {
            dealt[(firstReceiver + offset) % Self.playerCount].append(card)
        }
        dealt = dealt.map { $0.sorted { $0.sortKey < $1.sortKey } }

        lastTransfers = []
        if lastRanking.count == Self.playerCount {
            let exchanged = DaifugoRules.applyExchange(hands: dealt, ranking: lastRanking)
            dealt = exchanged.hands
            lastTransfers = exchanged.transfers
        }

        hands = dealt
        field = []
        fieldOwner = nil
        passedPlayers = []
        isRevolution = false
        finishOrder = []
        fouls = []
        resigned = []
        ranking = []
        selected = []
        lastActions = Array(repeating: "", count: Self.playerCount)
        gameNumber += 1
        currentPlayer = openingPlayer()
        recordResult = nil
        isSkippingToResult = false
        cpuTurnsAfterPlayerFinished = 0
        phase = .playing

        services?.feedback.impact(.medium)   // カードが配られた
        persist()
        // 1 ゲーム = 1 プレイ（`gameDidFinish` もゲームごとに呼んでいる）。
        // 中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID)
    }

    /// 親（最初の手番）。初回は♦3を持つ人、2ゲーム目以降は前回の大貧民。
    private func openingPlayer() -> Int {
        if let previousLast = lastRanking.last { return previousLast }
        let opening = hands.firstIndex { hand in
            hand.contains { $0.rank == 3 && $0.suit == .diamonds }
        }
        return opening ?? Self.humanIndex
    }

    private func makeGenerator() -> SeededGenerator? {
        seed.map { SeededGenerator(seed: $0) }
    }

    // MARK: - 人間の操作

    public func toggleSelection(_ card: DaifugoCard) {
        guard isPlayerTurn else { return }
        if selected.contains(card.id) {
            selected.remove(card.id)
        } else {
            selected.insert(card.id)
        }
        services?.feedback.impact(.rigid)
    }

    public func clearSelection() {
        selected = []
    }

    /// 選択中のカードを出す。出せない組み合わせなら何もせず警告だけ返す。
    public func playSelected() {
        guard isPlayerTurn else { return }
        let cards = selectedCards
        guard DaifugoRules.isValidPlay(cards, field: field, isRevolution: isRevolution) else {
            services?.feedback.notify(.warning)
            return
        }
        selected = []
        services?.feedback.impact(.medium)
        play(cards, by: Self.humanIndex)
    }

    /// パスする。親（場が空）のときはパスできない。
    public func pass() {
        guard isPlayerTurn else { return }
        guard canPass else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.light)
        passTurn(by: Self.humanIndex)
    }

    /// 自分が上がった後の CPU 同士の消化試合を、待たずに決着まで進める（#191）。
    /// 進行そのものは通常どおり行うため、階級・記録は早送りしても変わらない。
    public func skipToResult() {
        guard canSkipToResult else { return }
        isSkippingToResult = true
        services?.feedback.impact(.light)
    }

    /// 投了する（#194）。その場でゲームを打ち切り、自分は大貧民（最下位）で決着する。
    ///
    /// 残った CPU の順位は**手札の少ない順**（同数はプレイヤー番号順）で埋める。打ち切りなので
    /// 最後まで打たせず、上がりに最も近い並びで代用する。自分は反則上がりよりさらに下の最下位に
    /// 固定するため、`ranking` へ投了者として渡す。決着を通常どおり `concludeGame()` に通すので、
    /// 記録（敗北）・階級・次ゲームのカード交換の扱いは自然に上がったときと同じ経路になる。
    public func resign() {
        guard canResign else { return }
        let remaining = activePlayers()
            .filter { $0 != Self.humanIndex }
            .sorted { (hands[$0].count, $0) < (hands[$1].count, $1) }
        for player in remaining {
            finishOrder.append(player)
            hands[player] = []
        }
        hands[Self.humanIndex] = []
        finishOrder.append(Self.humanIndex)
        resigned.insert(Self.humanIndex)
        lastActions[Self.humanIndex] = "投了"
        concludeGame()
    }

    // MARK: - 進行

    private func play(_ cards: [DaifugoCard], by player: Int) {
        let ids = Set(cards.map(\.id))
        hands[player] = hands[player].filter { !ids.contains($0.id) }

        var note = cards.map(\.rankLabel).joined(separator: " ")
        if DaifugoRules.triggersRevolution(cards) {
            isRevolution.toggle()
            note += isRevolution ? " 革命！" : " 革命返し！"
        }

        field = cards
        fieldOwner = player

        let finished = hands[player].isEmpty
        if finished {
            finishOrder.append(player)
            if DaifugoRules.isFoulFinish(cards) {
                fouls.insert(player)
                note += " 反則上がり"
            } else {
                note += " あがり！"
            }
        }

        let clears = DaifugoRules.clearsField(cards)
        if clears { note += finished ? "（8切り）" : " 8切り！" }
        lastActions[player] = note

        if isGameOver() {
            concludeGame()
            return
        }

        if clears {
            // 8切りは場を流す。出した本人が残っていればそのまま親を続ける。
            clearField(preferredLeader: player)
        } else {
            // 上がった人の場はそのまま残る（次の人が続けて出すか、全員パスで流れる）。
            advanceTurn(from: player)
        }
        persist()
    }

    private func passTurn(by player: Int) {
        passedPlayers.insert(player)
        lastActions[player] = "パス"
        advanceTurn(from: player)
        persist()
    }

    /// 手番を次へ送る。まだ出せる人（手札があり、この場でパスしていない人）が
    /// 1人以下になったら場が流れ、その人が新しい親になる。
    ///
    /// 一度パスした人は場が流れるまで復帰しない（一般的なルール）。
    private func advanceTurn(from player: Int) {
        let eligible = eligiblePlayers()
        guard eligible.count > 1 else {
            clearField(preferredLeader: eligible.first ?? fieldOwner ?? player)
            return
        }
        currentPlayer = nextEligiblePlayer(after: player) ?? eligible[0]
    }

    /// 場を流して親を決める。親候補が既に上がっていれば次に手札が残っている人へ回す。
    private func clearField(preferredLeader: Int) {
        field = []
        fieldOwner = nil
        passedPlayers = []
        if !hands[preferredLeader].isEmpty {
            currentPlayer = preferredLeader
        } else if let next = nextActivePlayer(after: preferredLeader) {
            currentPlayer = next
        }
    }

    private func activePlayers() -> [Int] {
        hands.indices.filter { !hands[$0].isEmpty }
    }

    /// この場でまだ出せる人（手札が残っていて、パスしていない人）。
    private func eligiblePlayers() -> [Int] {
        activePlayers().filter { !passedPlayers.contains($0) }
    }

    private func nextActivePlayer(after player: Int) -> Int? {
        next(after: player) { !hands[$0].isEmpty }
    }

    private func nextEligiblePlayer(after player: Int) -> Int? {
        next(after: player) { !hands[$0].isEmpty && !passedPlayers.contains($0) }
    }

    private func next(after player: Int, where isMatch: (Int) -> Bool) -> Int? {
        for step in 1...Self.playerCount {
            let candidate = (player + step) % Self.playerCount
            if isMatch(candidate) { return candidate }
        }
        return nil
    }

    private func isGameOver() -> Bool {
        activePlayers().count <= 1
    }

    private func concludeGame() {
        if let last = activePlayers().first {
            finishOrder.append(last)
            hands[last] = []
        }
        ranking = DaifugoRules.ranking(finishOrder: finishOrder, fouls: fouls, resigned: resigned)
        lastRanking = ranking
        field = []
        fieldOwner = nil
        passedPlayers = []
        phase = .result

        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore(metric: .winLoss))
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - CPU

    /// CPU の手番が続く限り進める。人間の手番になるか決着したら止まる。
    /// View から複数の契機で呼ばれても内部で1本に制限する。
    public func runCPUTurnsIfNeeded() async {
        guard !isRunningCPUTurns else { return }
        isRunningCPUTurns = true
        defer { isRunningCPUTurns = false }

        while phase == .playing, currentPlayer != Self.humanIndex {
            // 間合いは毎手番ごとに読み直す。消化試合に入った時点・早送りを押された時点から
            // 待たずに済むようにするため（#191）。
            let delay = currentCPUDelay
            if delay > .zero {
                try? await Task.sleep(for: delay)
                // `try? await Task.sleep(for:)` はキャンセル後**毎回即座に**返る
                // （`CancellationError` を `try?` が握り潰す）。キャンセルを見ないと、
                // 画面を離れた瞬間に残りの CPU 手番が遅延ゼロで走り抜けてしまう（#287）。
                // 下の状態 guard は状態しか見ないので、これの代わりにはならない。
                guard !Task.isCancelled else { return }
                guard phase == .playing, currentPlayer != Self.humanIndex else { return }
            }
            performCPUTurn(currentPlayer)
        }
    }

    /// この手番で取る間合い（#191）。自分が上がった後は短くし、早送り中は取らない。
    /// `cpuDelay` が 0 のテストでは常に 0 のまま（`min` で頭打ちにしているため）。
    private var currentCPUDelay: Duration {
        guard isPlayerFinished else { return cpuDelay }
        return isSkippingToResult ? .zero : min(cpuDelay, Self.finishedCPUDelay)
    }

    /// CPU の1手。CPU の着手では触覚を鳴らさない（人間の操作と区別するため）。
    private func performCPUTurn(_ player: Int) {
        if isPlayerFinished { cpuTurnsAfterPlayerFinished += 1 }
        if let play = DaifugoRules.greedyPlay(
            hand: hands[player], field: field, isRevolution: isRevolution
        ) {
            self.play(play, by: player)
        } else {
            passTurn(by: player)
        }
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    /// `internal` なのでアプリからは呼べない（`@testable import` からのみ見える）。
    func configureForTesting(
        hands: [[DaifugoCard]],
        field: [DaifugoCard] = [],
        fieldOwner: Int? = nil,
        currentPlayer: Int = DaifugoModel.humanIndex,
        isRevolution: Bool = false,
        passedPlayers: Set<Int> = [],
        gameNumber: Int = 1,
        finishOrder: [Int] = []
    ) {
        self.hands = hands.map { $0.sorted { $0.sortKey < $1.sortKey } }
        self.field = field
        self.fieldOwner = fieldOwner
        self.currentPlayer = currentPlayer
        self.isRevolution = isRevolution
        self.passedPlayers = passedPlayers
        self.gameNumber = gameNumber
        self.finishOrder = finishOrder
        fouls = []
        resigned = []
        ranking = []
        selected = []
        lastActions = Array(repeating: "", count: Self.playerCount)
        isSkippingToResult = false
        cpuTurnsAfterPlayerFinished = 0
        phase = .playing
        persist()
    }

    // MARK: - 永続化

    private func persist() {
        guard phase == .playing else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = DaifugoSnapshot(
            hands: hands,
            field: field,
            fieldOwner: fieldOwner,
            currentPlayer: currentPlayer,
            passedPlayers: Array(passedPlayers).sorted(),
            isRevolution: isRevolution,
            finishOrder: finishOrder,
            fouls: Array(fouls).sorted(),
            gameNumber: gameNumber,
            lastRanking: lastRanking,
            lastActions: lastActions
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
