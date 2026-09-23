import Foundation
import Observation
import Core

// MARK: - Phase

public enum ColorRelayPhase: String, Equatable, Sendable, Codable {
    /// 開始前。
    case idle
    /// 対局中。
    case playing
    /// 1 ゲームの決着。
    case result
}

// MARK: - Snapshot

struct ColorRelaySnapshot: Codable {
    let hands: [[RelayCard]]
    let drawPile: [RelayCard]
    let discardPile: [RelayCard]
    let currentPlayer: Int
    let isClockwise: Bool
    let activeColor: RelayColor
    let pendingDraw: Int
    let hasDrawnThisTurn: Bool
    let drawnCardID: Int?
    let gameNumber: Int
    let lastActions: [String]
    let isPenaltyWaived: Bool
    let turnSerial: Int
}

// MARK: - Model

/// いろリレー（CPU 3 人との対戦・#1320）。プレイヤーは常に番号 0。
///
/// 出せるかどうか・CPU の選択は `ColorRelayRules`（純粋関数）に寄せ、この型は**進行・永続化・演出**だけを持つ。
/// CPU の手番の回し方は大富豪と同じ定石（`AITurnGuarded`・#531）。
@MainActor
@Observable
public final class ColorRelayModel: AITurnGuarded {
    /// 人間プレイヤーの番号。
    public static let humanIndex = 0
    /// 参加人数（人間 1 + CPU 3）。
    public static let playerCount = 4
    /// `GameModule.id` と同じ値。`ModuleTests` が一致を確かめる。
    public static let gameID = "colorrelay"
    public private(set) var hands: [[RelayCard]] = Array(repeating: [], count: playerCount)
    public private(set) var drawPile: [RelayCard] = []
    /// 捨て札。末尾が場に見えている札。
    public private(set) var discardPile: [RelayCard] = []
    public private(set) var currentPlayer: Int = humanIndex
    /// 番の回る向き。true なら 0 → 1 → 2 → 3。
    public private(set) var isClockwise = true
    /// いまの色（いろがえで選び直される）。
    public private(set) var activeColor: RelayColor = .red
    /// いまの手番の人が引かされる枚数（+2 / いろがえ+4 の直後）。0 なら通常の手番。
    public private(set) var pendingDraw = 0
    /// この手番で山から 1 枚引いたか（引けるのは 1 手番 1 回）。
    public private(set) var hasDrawnThisTurn = false
    /// この手番で引いた札の ID。引いた札が出せるときは**その札だけ**出せる。
    public private(set) var drawnCardID: Int?
    public private(set) var phase: ColorRelayPhase = .idle
    /// 決着後の最終順位（1 位から順のプレイヤー番号）。対局中は空。
    public private(set) var ranking: [Int] = []
    /// 何ゲーム目か（1 始まり）。
    public private(set) var gameNumber = 0
    /// 各プレイヤーの直近の動き（「とばし！」「2枚引いた」など）。画面のバッジ表示用。
    public private(set) var lastActions: [String] = Array(repeating: "", count: playerCount)
    /// 手札で選択中の札の ID（1 枚だけ）。
    public private(set) var selectedID: Int?
    /// このゲームで引き札の免除（広告）を使ったか。1 ゲーム 1 回。
    public private(set) var isPenaltyWaived = false
    /// 手番の通し番号。番が動くたびに進む。広告の前後で同じ手番かの照合に使う（#729 の局ガード）。
    public private(set) var turnSerial = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 配ったばかりで 1 手も進んでいない局か（#240）。`startGame()` で立て、最初に札が動いた時点で下ろす。
    /// 枚数から推定すると、山の切り直し直後にたまたま配った直後と同じ枚数になる局面で誤判定する
    /// （CodeRabbit 指摘・PR #1339）ので、フラグで持つ。配ったばかりの局は保存しないため中断データには入れない。
    private var isUntouchedDeal = false

    private let services: GameServices?
    let gameID = ColorRelayModel.gameID
    private let cpuDelay: Duration
    private var seed: UInt64?
    /// ヒント表示のオン / オフ（#190）。対局中には変わらないので参照のたびに読む。
    private let hints: FeedbackPreference
    /// CPU の連続手番が二重に走らないようにする門番。テストが同期ゲートに使うので `internal`。
    var isRunningCPUTurns = false

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
        // 手書き・壊れた中断データで落ちないよう、配列の長さと番号の範囲を見てから戻す。
        if let snap = services?.snapshots.load(ColorRelaySnapshot.self, for: gameID),
           snap.hands.count == Self.playerCount, !snap.discardPile.isEmpty,
           (0..<Self.playerCount).contains(snap.currentPlayer), snap.pendingDraw >= 0 {
            hands            = snap.hands
            drawPile         = snap.drawPile
            discardPile      = snap.discardPile
            currentPlayer    = snap.currentPlayer
            isClockwise      = snap.isClockwise
            activeColor      = snap.activeColor
            pendingDraw      = snap.pendingDraw
            hasDrawnThisTurn = snap.hasDrawnThisTurn
            drawnCardID      = snap.drawnCardID
            gameNumber       = snap.gameNumber
            if snap.lastActions.count == Self.playerCount { lastActions = snap.lastActions }
            isPenaltyWaived  = snap.isPenaltyWaived
            turnSerial       = snap.turnSerial
            phase            = .playing
        }
    }

    // MARK: - 公開状態

    /// 人間の手札（並べ替え済み）。
    public var playerHand: [RelayCard] { hands[Self.humanIndex] }

    /// 場に見えている札。
    public var topCard: RelayCard? { discardPile.last }

    /// 人間の手番か。
    public var isPlayerTurn: Bool { phase == .playing && currentPlayer == Self.humanIndex }

    /// 人間が引き札を課されているか（+2 / いろがえ+4 の直後の自分の番）。
    public var isPlayerPenalized: Bool { isPlayerTurn && pendingDraw > 0 }

    /// 山から 1 枚引けるか（通常の手番で、まだ引いていないとき）。
    public var canDraw: Bool { isPlayerTurn && pendingDraw == 0 && !hasDrawnThisTurn }

    /// 引いた札を出さずに番を終えられるか（引いた札が出せるときだけこの操作が要る。
    /// 出せない札を引いたときは自動で次へ回る）。
    public var canEndTurn: Bool { isPlayerTurn && pendingDraw == 0 && hasDrawnThisTurn }

    /// 広告を見て引き札を免除できるか（#1320）。自分の番で引き札を課されていて、このゲームでまだ使っていないとき。
    public var canWaivePenalty: Bool { isPlayerPenalized && !isPenaltyWaived }

    /// 人間がいま出せる札の ID。引いた直後は引いた札だけ。
    public var playableCardIDs: Set<Int> {
        guard isPlayerTurn, pendingDraw == 0, let top = topCard else { return [] }
        let all = ColorRelayRules.playableCardIDs(hand: playerHand, top: top, activeColor: activeColor)
        guard let drawnCardID, hasDrawnThisTurn else { return all }
        return all.intersection([drawnCardID])
    }

    /// 選択中の札。
    public var selectedCard: RelayCard? {
        guard let selectedID else { return nil }
        return playerHand.first { $0.id == selectedID }
    }

    /// 選択中の札が万能札で、色を選ぶ必要があるか。
    public var needsColorChoice: Bool { selectedCard?.isWild == true && canPlaySelection }

    /// 選択中の札を出せるか。
    public var canPlaySelection: Bool {
        guard let selectedID else { return false }
        return playableCardIDs.contains(selectedID)
    }

    /// 手札のヒント（#190）。設定でオフ / 相手の番 / 手札が空 / 全部出せる のときは nil。
    /// 1 枚も出せないときは全札を暗く落とし、「引くしかない」ことを伝える。
    public var handHint: RelayHandHint? {
        guard hints.isEnabled, isPlayerTurn, pendingDraw == 0, !playerHand.isEmpty else { return nil }
        let playable = playableCardIDs
        guard playable.count < playerHand.count else { return nil }
        return RelayHandHint(
            playable: playable,
            unplayable: Set(playerHand.map(\.id)).subtracting(playable)
        )
    }

    /// 人間の最終順位（0 始まり）。決着していなければ nil。
    public var playerPlace: Int? { ranking.firstIndex(of: Self.humanIndex) }

    /// 評価リクエスト（#53）の判定用。上がれば勝ち、それ以外は負け。
    public var reviewOutcome: GameOutcome { playerPlace == 0 ? .win : .loss }

    public func playerName(_ index: Int) -> String {
        index == Self.humanIndex ? "あなた" : "CPU\(index)"
    }

    /// 番の向きで見た、`player` の次の人。
    public func nextPlayer(after player: Int) -> Int {
        let step = isClockwise ? 1 : Self.playerCount - 1
        return (player + step) % Self.playerCount
    }

    // MARK: - ゲーム開始

    /// 新しい 1 ゲームを始める。7 枚ずつ配り、山の 1 枚目を場に置く（数字札が出るまでめくる）。
    public func startGame() {
        var deck = RelayCard.makeDeck()
        shuffle(&deck)

        var dealt: [[RelayCard]] = Array(repeating: [], count: Self.playerCount)
        for _ in 0..<ColorRelayRules.initialHandCount {
            for player in 0..<Self.playerCount {
                dealt[player].append(deck.removeLast())
            }
        }
        hands = dealt.map { $0.sorted { $0.sortKey < $1.sortKey } }

        // 場の 1 枚目は数字札に限る（特殊札で始めると、最初の人だけが理由もなく損をする）。
        // 数字札でない札は山の底へ戻す。
        var opening = deck.removeLast()
        var attempts = 0
        while !isNumber(opening.kind), attempts < deck.count + 1 {
            deck.insert(opening, at: 0)
            opening = deck.removeLast()
            attempts += 1
        }
        discardPile = [opening]
        drawPile = deck
        activeColor = opening.color ?? .red

        isClockwise = true
        pendingDraw = 0
        hasDrawnThisTurn = false
        drawnCardID = nil
        selectedID = nil
        ranking = []
        lastActions = Array(repeating: "", count: Self.playerCount)
        isPenaltyWaived = false
        recordResult = nil
        isUntouchedDeal = true
        gameNumber += 1
        // 親はゲームごとに 1 人ずつ回す（1 ゲーム目は人間）。
        currentPlayer = (gameNumber - 1) % Self.playerCount
        turnSerial += 1
        phase = .playing

        services?.feedback.impact(.medium)   // 札が配られた
        // 配ったばかりの局は `persist()` 側のガードで保存されない（1 手目で改めて保存される）。
        persist()
        // 1 ゲーム = 1 プレイ。中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID)
    }

    private func isNumber(_ kind: RelayKind) -> Bool {
        if case .number = kind { return true }
        return false
    }

    private func shuffle(_ cards: inout [RelayCard]) {
        if let current = seed {
            var generator = SplitMix64(seed: current)
            cards.shuffle(using: &generator)
            seed = generator.next()   // 次のシャッフルで同じ並びにならないよう種を進める
        } else {
            cards.shuffle()
        }
    }

    // MARK: - 人間の操作

    /// 手札をタップ。同じ札をもう一度タップすると選択を外す。
    public func toggleSelection(_ card: RelayCard) {
        guard isPlayerTurn, pendingDraw == 0 else { return }
        selectedID = selectedID == card.id ? nil : card.id
        services?.feedback.impact(.rigid)
    }

    public func clearSelection() {
        selectedID = nil
    }

    /// 選択中の札を出す。万能札は `color` で次の色を指定する（無ければ何もしない）。
    public func playSelected(color: RelayColor? = nil) {
        guard isPlayerTurn, let card = selectedCard, canPlaySelection else {
            services?.feedback.notify(.warning)
            return
        }
        if card.isWild, color == nil {
            services?.feedback.notify(.warning)
            return
        }
        selectedID = nil
        services?.feedback.impact(.medium)
        play(card, by: Self.humanIndex, chosenColor: color)
    }

    /// 山から 1 枚引く。引いた札が出せなければ、そのまま次の人へ回る。
    public func drawCard() {
        guard canDraw else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.light)
        let drawn = draw(count: 1, for: Self.humanIndex)
        hasDrawnThisTurn = true
        drawnCardID = drawn.first?.id
        selectedID = nil
        lastActions[Self.humanIndex] = "1枚引いた"
        // 引いた = 盤面が動いた。配っただけの局面を捨てても離脱には数えない境目（#500）。
        services?.gameDidProgress(gameID: gameID)
        if playableCardIDs.isEmpty {
            advanceTurn(steps: 1)
        }
        persist()
    }

    /// 引いた札を出さずに番を終える。
    public func endTurn() {
        guard canEndTurn else { return }
        services?.feedback.impact(.light)
        selectedID = nil
        lastActions[Self.humanIndex] = "出さずに次へ"
        advanceTurn(steps: 1)
        persist()
    }

    /// 課された引き札を引いて、番を飛ばされる。
    public func takePenalty() {
        guard isPlayerPenalized else { return }
        services?.feedback.notify(.warning)
        applyPenalty(to: Self.humanIndex)
        persist()
    }

    /// 広告を見終えたあと、課された引き札を免除する（#1320）。
    ///
    /// - Parameter serial: 広告を出す**前**に控えた `turnSerial`。広告のあいだに番が動いていたら
    ///   免除を乗せずに false を返す（#729 の局ガード）。
    /// - Returns: 免除したか。
    public func waivePenaltyAfterAd(forTurn serial: Int) -> Bool {
        guard serial == turnSerial, canWaivePenalty else { return false }
        isPenaltyWaived = true
        pendingDraw = 0
        lastActions[Self.humanIndex] = "引き札を免除"
        services?.feedback.notify(.success)
        // 免除しても番は飛ばされる（引かなくて済むだけ）。
        advanceTurn(steps: 1)
        persist()
        return true
    }

    // MARK: - 進行

    private func play(_ card: RelayCard, by player: Int, chosenColor: RelayColor?) {
        isUntouchedDeal = false
        hands[player].removeAll { $0.id == card.id }
        discardPile.append(card)
        activeColor = card.color ?? chosenColor ?? activeColor
        // 札が出た = 盤面が動いた（#500）。
        services?.gameDidProgress(gameID: gameID)

        var note = card.kind.label
        if card.isWild, let chosenColor { note += " → \(chosenColor.name)" }

        if hands[player].isEmpty {
            lastActions[player] = note + " あがり！"
            concludeGame(winner: player)
            return
        }

        switch card.kind {
        case .number, .wild:
            advanceTurn(steps: 1)
        case .skip:
            note += "！"
            advanceTurn(steps: 2)
        case .reverse:
            note += "！"
            isClockwise.toggle()
            advanceTurn(steps: 1)
        case .drawTwo, .wildDrawFour:
            note += "！"
            advanceTurn(steps: 1)
            pendingDraw = card.kind.penalty
        }
        lastActions[player] = note
        persist()
    }

    /// `player` に課された引き札を引かせて、番を飛ばす。
    private func applyPenalty(to player: Int) {
        let count = pendingDraw
        pendingDraw = 0
        let drawn = draw(count: count, for: player)
        lastActions[player] = "\(drawn.count)枚引いた"
        services?.gameDidProgress(gameID: gameID)
        advanceTurn(steps: 1)
    }

    /// 番を `steps` 人ぶん進める（2 なら 1 人飛ばす）。手番の通し番号も進める。
    private func advanceTurn(steps: Int) {
        var next = currentPlayer
        for _ in 0..<steps { next = nextPlayer(after: next) }
        currentPlayer = next
        hasDrawnThisTurn = false
        drawnCardID = nil
        turnSerial += 1
    }

    /// 山から `count` 枚引いて `player` の手札に加える。山が尽きたら捨て札（場の 1 枚を除く）を切り直す。
    /// それでも足りなければ引ける枚数だけ引く。
    @discardableResult
    private func draw(count: Int, for player: Int) -> [RelayCard] {
        isUntouchedDeal = false
        var drawn: [RelayCard] = []
        for _ in 0..<count {
            if drawPile.isEmpty { refillDrawPile() }
            guard let card = drawPile.popLast() else { break }
            drawn.append(card)
            hands[player].append(card)
        }
        hands[player].sort { $0.sortKey < $1.sortKey }
        return drawn
    }

    private func refillDrawPile() {
        guard discardPile.count > 1, let top = discardPile.last else { return }
        var recycled = Array(discardPile.dropLast())
        discardPile = [top]
        shuffle(&recycled)
        drawPile = recycled
    }

    private func concludeGame(winner: Int) {
        ranking = ColorRelayRules.ranking(hands: hands, winner: winner)
        pendingDraw = 0
        selectedID = nil
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
    /// View から複数の契機で呼ばれても内部で 1 本に制限する（`withAITurnRunner`・#531）。
    public func runCPUTurnsIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            while phase == .playing, currentPlayer != Self.humanIndex {
                // 間合いが 0 の手番には suspend が無く、下の sleep 後の判定を通らない。ループ先頭でも見る（#287）。
                guard !Task.isCancelled else { return }
                if cpuDelay > .zero {
                    // sleep の直後にキャンセルを見る。見ないと画面を離れた瞬間に残りの手番が間合いゼロで走り抜ける（#287）。
                    guard await pauseCPUTurn(for: cpuDelay) else { return }
                    guard phase == .playing, currentPlayer != Self.humanIndex else { return }
                }
                performCPUTurn(currentPlayer)
            }
        }
    }

    /// CPU の 1 手。CPU の着手では触覚を鳴らさない（人間の操作と区別するため）。
    private func performCPUTurn(_ player: Int) {
        if pendingDraw > 0 {
            applyPenalty(to: player)
            persist()
            return
        }
        // 場が空になることは無いが、万一そうなっても番を回して `runCPUTurnsIfNeeded` のループを止めない。
        guard let top = topCard else {
            advanceTurn(steps: 1)
            return
        }
        let next = nextPlayer(after: player)
        if let card = ColorRelayRules.cpuPlay(
            hand: hands[player], top: top, activeColor: activeColor, nextHandCount: hands[next].count
        ) {
            play(card, by: player, chosenColor: card.isWild ? ColorRelayRules.dominantColor(in: hands[player]) : nil)
            return
        }
        // 出せる札が無ければ 1 枚引き、出せる札ならすぐ出す。
        let drawn = draw(count: 1, for: player)
        services?.gameDidProgress(gameID: gameID)
        if let card = drawn.first, ColorRelayRules.canPlay(card, onto: top, activeColor: activeColor) {
            play(card, by: player, chosenColor: card.isWild ? ColorRelayRules.dominantColor(in: hands[player]) : nil)
            return
        }
        lastActions[player] = "1枚引いた"
        advanceTurn(steps: 1)
        persist()
    }

    // MARK: - テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    /// `internal` なのでアプリからは呼べない（`@testable import` からのみ見える）。
    func configureForTesting(
        hands: [[RelayCard]],
        top: RelayCard,
        drawPile: [RelayCard] = [],
        discardBelowTop: [RelayCard] = [],
        currentPlayer: Int = ColorRelayModel.humanIndex,
        activeColor: RelayColor? = nil,
        isClockwise: Bool = true,
        pendingDraw: Int = 0,
        isPenaltyWaived: Bool = false,
        gameNumber: Int = 1
    ) {
        self.hands = hands.map { $0.sorted { $0.sortKey < $1.sortKey } }
        self.discardPile = discardBelowTop + [top]
        self.drawPile = drawPile
        self.currentPlayer = currentPlayer
        self.activeColor = activeColor ?? top.color ?? .red
        self.isClockwise = isClockwise
        self.pendingDraw = pendingDraw
        self.isPenaltyWaived = isPenaltyWaived
        self.gameNumber = gameNumber
        hasDrawnThisTurn = false
        drawnCardID = nil
        selectedID = nil
        ranking = []
        lastActions = Array(repeating: "", count: Self.playerCount)
        isUntouchedDeal = false
        turnSerial += 1
        phase = .playing
        persist()
    }

    #if DEBUG
    /// 撮影・動作確認用（Release には残らない）。`-colorRelayScenario <name>` で局面を差し替える。
    ///
    /// - `penalty`: 自分の番でいろがえ+4 を受けている（免除ボタンが出る）
    /// - `wild`: 自分の番でいろがえを選択済み（色を選ぶボタンが出る）
    /// - `result`: 自分が上がった直後のリザルト
    public func applyDebugScenario(_ name: String) {
        guard phase == .playing else { return }
        let deck = RelayCard.makeDeck()
        func card(_ color: RelayColor?, _ kind: RelayKind) -> RelayCard {
            deck.first { $0.color == color && $0.kind == kind }!
        }
        let sample: [RelayCard] = [
            card(.red, .number(3)), card(.red, .number(7)), card(.green, .number(5)), card(.green, .skip),
            card(.purple, .number(9)), card(.yellow, .drawTwo), card(nil, .wild), card(.yellow, .number(1)),
        ]
        let cpu: [[RelayCard]] = (1..<Self.playerCount).map { index in
            Array(deck.filter { c in !sample.contains(c) }.dropFirst(index * 6).prefix(5))
        }
        switch name {
        case "penalty":
            configureForTesting(
                hands: [sample] + cpu, top: card(nil, .wildDrawFour),
                drawPile: Array(deck.suffix(20)), activeColor: .green, pendingDraw: 4
            )
            lastActions[3] = "いろがえ+4 → みどり！"
        case "wild":
            configureForTesting(
                hands: [sample] + cpu, top: card(.purple, .number(4)), drawPile: Array(deck.suffix(20))
            )
            selectedID = card(nil, .wild).id
        case "result":
            configureForTesting(
                hands: [[card(.red, .number(3))]] + cpu, top: card(.red, .number(8)),
                drawPile: Array(deck.suffix(20))
            )
            selectedID = card(.red, .number(3)).id
            playSelected()
        default:
            break
        }
    }
    #endif

    // MARK: - 永続化

    private func persist() {
        // 配ったばかりの盤面は保存しない（#240）。開始してすぐ閉じただけでハブに「続きから」が付くと、
        // バッジが「途中の対局がある」という意味を持たなくなる。
        guard phase == .playing, !isUntouchedDeal else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = ColorRelaySnapshot(
            hands: hands,
            drawPile: drawPile,
            discardPile: discardPile,
            currentPlayer: currentPlayer,
            isClockwise: isClockwise,
            activeColor: activeColor,
            pendingDraw: pendingDraw,
            hasDrawnThisTurn: hasDrawnThisTurn,
            drawnCardID: drawnCardID,
            gameNumber: gameNumber,
            lastActions: lastActions,
            isPenaltyWaived: isPenaltyWaived,
            turnSerial: turnSerial
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
