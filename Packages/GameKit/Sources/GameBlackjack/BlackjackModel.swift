import Foundation
import Observation
import Core

// MARK: - Card

public enum BlackjackSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs
    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var isRed: Bool { self == .hearts || self == .diamonds }

    /// トランプ共通基盤（#397）の描画用スート。`rawValue` の一致に頼らず明示的に対応させる。
    public var playing: PlayingCardSuit {
        switch self {
        case .spades:   return .spade
        case .hearts:   return .heart
        case .diamonds: return .diamond
        case .clubs:    return .club
        }
    }
}

public struct BlackjackCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let suit: BlackjackSuit
    public let rank: Int  // 1–13 (1=A, 11=J, 12=Q, 13=K)

    public var rankLabel: String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    public var value: Int {
        switch rank {
        case 1:       return 11  // Aは最初11として扱い、バストなら1に下げる
        case 11, 12, 13: return 10
        default:      return rank
        }
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。`rank` は既に A=1 表記なのでそのまま渡す。
    public var figure: PlayingCardFigure {
        .pip(suit: suit.playing, rank: rank)
    }
}

// MARK: - Hand Value

func handValue(_ hand: [BlackjackCard]) -> Int {
    var total = hand.reduce(0) { $0 + $1.value }
    var aces = hand.filter { $0.rank == 1 }.count
    while total > 21 && aces > 0 {
        total -= 10
        aces -= 1
    }
    return total
}

func isBlackjack(_ hand: [BlackjackCard]) -> Bool {
    hand.count == 2 && handValue(hand) == 21
}

// MARK: - Settlement

/// 勝敗の判定表（#413）。`resolveResult` から切り出した純関数。
///
/// ナチュラル（2枚21）は両者について対称に扱う。**ディーラーのみナチュラルなら、
/// プレイヤーが3枚以上で21に届いていてもディーラーの勝ち**（標準ルール。以前は
/// 同値としてプッシュに落ちていた）。
/// プレイヤーのバストは呼び出し側（`settleHand`）で先に弾くためここには到達しない。
///
/// - Parameter allowsPlayerNatural: プレイヤー側の2枚21をナチュラルとして扱うか。
///   **スプリットで作った21はナチュラルにしない**という標準ルールのため false を渡す（#439）。
func blackjackSettlement(
    player: [BlackjackCard],
    dealer: [BlackjackCard],
    allowsPlayerNatural: Bool = true
) -> BlackjackOutcome {
    let pVal = handValue(player)
    let dVal = handValue(dealer)
    let playerNatural = allowsPlayerNatural && isBlackjack(player)
    let dealerNatural = isBlackjack(dealer)

    if playerNatural && dealerNatural { return .push }
    if playerNatural { return .playerBlackjack }
    if dealerNatural { return .lose }
    if dVal > 21 || pVal > dVal { return .win }
    if pVal == dVal { return .push }
    return .lose
}

// MARK: - Game Phase

public enum BlackjackPhase: String, Equatable, Sendable, Codable {
    case idle, ready, playerTurn, dealerTurn, result
}

public enum BlackjackOutcome: String, Sendable, Codable {
    case playerBlackjack, win, push, lose, bust

    /// この勝敗で入る点（#2552）。勝ち 1 点、ブラックジャックで勝てば 2 点、引き分け・負けは 0 点。
    var points: Int {
        switch self {
        case .playerBlackjack: return BlackjackModel.blackjackWinPoints
        case .win:             return BlackjackModel.winPoints
        case .push, .lose, .bust: return 0
        }
    }
}

// MARK: - Player Hand

/// プレイヤーの1手（#439）。スプリットすると2つに増え、それぞれ独立に勝敗を決める。
struct BlackjackHand: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    var cards: [BlackjackCard]
    /// スプリットで生まれた手か。**この手の2枚21はナチュラル扱いしない**（標準ルール）。
    var isFromSplit: Bool = false
    /// プレイヤーの操作が終わった手か（スタンド・バスト・スプリットしたA）。
    var isDone: Bool = false
    /// 勝敗。`resolveAll()` で入る。
    var outcome: BlackjackOutcome? = nil

    var value: Int { handValue(cards) }
    var isBusted: Bool { value > 21 }
}

// MARK: - Snapshot

/// 中断データ（#2552 で賭けのない 10 回勝負に作り直した）。
///
/// **`roundsPlayed` / `score` / `streak` は非 optional**にしてある。チップ制だった頃の中断データには
/// これらの鍵が無いのでデコードが失敗し、`SnapshotStore.load` が nil を返して読み飛ばされる
/// （チップの残高を点数として読み違えない）。
struct BlackjackSnapshot: Codable {
    let dealerHand: [BlackjackCard]
    let deck: [BlackjackCard]
    let phase: BlackjackPhase
    let hands: [BlackjackHand]
    let activeHandIndex: Int
    /// 終えた回数（0〜10）。
    let roundsPlayed: Int
    /// この勝負の合計点。
    let score: Int
    /// いまの連勝。
    let streak: Int
    /// 広告での「やり直し」をこの勝負で使ったか。中断を挟んでも 1 回までを守る。
    let retryUsed: Bool
}

// MARK: - Model

@MainActor
@Observable
public final class BlackjackModel {
    /// プレイヤーの手。通常は1つで、スプリットしたときだけ2つになる（#439）。
    private(set) var hands: [BlackjackHand] = []
    /// いま操作している手の位置。スプリット時は 0 → 1 の順に進む。
    private(set) var activeHandIndex: Int = 0

    /// いま操作している手の手札。手が1つのときは従来どおり「プレイヤーの手札」そのもの。
    public var playerHand: [BlackjackCard] {
        hands.indices.contains(activeHandIndex) ? hands[activeHandIndex].cards : []
    }
    public private(set) var dealerHand: [BlackjackCard] = []
    public private(set) var phase: BlackjackPhase = .ready
    public private(set) var outcome: BlackjackOutcome? = nil
    /// 直近のラウンドで入った点。決着の表示に使う。
    public private(set) var roundPoints: Int?
    /// 直近のラウンドで確定した自己ベスト（#115）。10 回目の決着のときだけ入る。
    public private(set) var recordResult: RecordResult?

    // MARK: 10 回勝負（#2552）

    /// 記録の区分。チップ制だった頃の記録（区分なし）と自己ベストを混ぜないために分ける。
    nonisolated static let recordVariant = "match10"
    /// 1 回の勝負で遊ぶ回数。
    public static let roundsPerMatch = 10
    /// ふつうに勝ったときの点。
    nonisolated static let winPoints = 1
    /// 最初の 2 枚で 21（ブラックジャック）をつくって勝ったときの点。
    nonisolated static let blackjackWinPoints = 2

    /// 終えた回数（0〜`roundsPerMatch`）。
    public private(set) var roundsPlayed = 0
    /// この勝負の合計点。
    public private(set) var score = 0
    /// いまの連勝（引き分けは続きも切れもせず、負けで 0 に戻る）。
    public private(set) var streak = 0
    /// この勝負で一番長かった連勝。
    public private(set) var bestStreakInMatch = 0

    /// 直前のラウンドが始まる前の連勝。広告で負けをやり直すときに戻す。
    private var streakBeforeRound = 0
    /// 広告で「負けた 1 回」をやり直すのは 1 回の勝負につき 1 回まで。
    private var retryUsed = false

    /// 10 回を終えたか。決着の画のまま、次の勝負（`restartSession`）を待つ。
    public var isMatchOver: Bool { roundsPlayed >= BlackjackModel.roundsPerMatch }

    /// 画面に出す「第N回」。決着後は終えた回、それ以外は遊んでいる（これから遊ぶ）回。
    public var roundNumber: Int {
        phase == .result ? roundsPlayed : min(roundsPlayed + 1, BlackjackModel.roundsPerMatch)
    }

    /// 直前の負けをリワード広告で取り消せる状態か。1 回の勝負につき 1 回まで。
    /// 10 回目の負けも対象（取り消すと 9 回目の終わりに戻る）。
    public var canRetryLoss: Bool {
        phase == .result && !retryUsed && (outcome == .lose || outcome == .bust)
    }

    /// 広告のロード中に別の勝負へ入れ替わっていないかの照合用（#727 と同じ）。
    private var sessionSerial = 0

    /// 決着の種類（評価リクエスト #53 の判定用。リザルト表示時に参照する）。
    /// プッシュは引き分け、バストは敗北として扱う。
    public var reviewOutcome: GameOutcome {
        switch outcome {
        case .playerBlackjack, .win: return .win
        case .push:                  return .draw
        default:                     return .loss
        }
    }

    public var playerValue: Int { handValue(playerHand) }
    public var dealerValue: Int { handValue(dealerHand) }
    public var dealerVisibleValue: Int {
        guard dealerHand.count >= 2 else { return handValue(dealerHand) }
        return handValue([dealerHand[0]])
    }

    private var deck: [BlackjackCard] = []
    let gameID = "blackjack"
    private let services: GameServices?
    private var seed: UInt64?

    /// ディーラーが1枚引くごとの間（#667）。`.zero` なら従来どおりその場で引き切る。
    private let dealerDrawInterval: Duration
    /// 1枚ずつ引いている最中の `Task`。「結果まで進める」とやり直しで止める。
    private(set) var dealerTask: Task<Void, Never>?

    /// - Parameters:
    ///   - seed: テスト用の固定種。nil ならシステムの乱数を使う。
    ///   - dealerDrawInterval: ディーラーの引きの間。画面は `BlackjackMotion.dealerDrawInterval` を渡す。
    ///     既定の `.zero` は待たずに引き切る（テストの決定性のため）。
    public init(services: GameServices? = nil, seed: UInt64? = nil, dealerDrawInterval: Duration = .zero) {
        self.services = services
        self.seed = seed
        self.dealerDrawInterval = dealerDrawInterval
        if let snap = services?.snapshots.load(BlackjackSnapshot.self, for: "blackjack"),
           snap.roundsPlayed >= 0, snap.roundsPlayed < BlackjackModel.roundsPerMatch {
            self.dealerHand = snap.dealerHand
            self.deck       = snap.deck
            self.phase      = snap.phase
            self.roundsPlayed = snap.roundsPlayed
            self.score      = max(0, snap.score)
            self.streak     = max(0, snap.streak)
            self.bestStreakInMatch = self.streak
            self.streakBeforeRound = self.streak
            self.retryUsed  = snap.retryUsed
            if !snap.hands.isEmpty {
                self.hands = snap.hands
                self.activeHandIndex = min(max(snap.activeHandIndex, 0), snap.hands.count - 1)
            }
            // 手を復元できなければ操作のしようがないので、配る前に戻す。
            if self.hands.isEmpty || (snap.phase != .playerTurn && snap.phase != .dealerTurn) {
                self.hands = []
                self.dealerHand = []
                self.phase = .ready
                // 戻った先は配る前で「続き」ではないので、中断のお知らせ（#663）の対象から外す（#1145）。
                // `persistBetween` の通知は**保存したプロセスの中**でしか効かない
                // （`ResumeReminder` の決着済みの印はメモリ上の集合で、再起動で空に戻る）。
                // 復元側でも伝えないと、アプリを起動し直してから開いて戻ったときだけ予約される。
                self.services?.gameDidRestoreFinished(gameID: gameID)
            }
        }
        // ディーラーが引いている途中で中断していたら、その続きから引く（#667）。
        // 選び直させることはしない。
        if phase == .dealerTurn {
            runDealer()
        }
    }

    private func persist() {
        // ディーラーが1枚ずつ引いているあいだ（#667）も保存する。保存しないと、途中で落ちたとき
        // スタンド前の中断データが残り、ディーラーの札を見てから選び直せてしまう。
        guard phase == .playerTurn || phase == .dealerTurn else {
            // 勝負が終わったら続きは無いので捨てる。途中なら、配る前の形で進み具合だけ残す。
            if isMatchOver {
                services?.snapshots.clear(for: gameID)
            } else {
                persistBetween()
            }
            return
        }
        save(hands: hands, dealerHand: dealerHand, deck: deck)
    }

    private func save(hands: [BlackjackHand], dealerHand: [BlackjackCard], deck: [BlackjackCard]) {
        let snap = BlackjackSnapshot(
            dealerHand: dealerHand,
            deck: deck,
            phase: hands.isEmpty ? .ready : phase,
            hands: hands,
            activeHandIndex: activeHandIndex,
            roundsPlayed: roundsPlayed,
            score: score,
            streak: streak,
            retryUsed: retryUsed
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    /// 局を持たない「ラウンドの合間」の中断データ。進み具合（回数・点・連勝・やり直しの使用）だけを持ち回る。
    ///
    /// 決着の画（`outcome` は中断データに持っていない）を復元しても読めないので、局は書かずに
    /// 配る前へ戻す。復元側は「手が無ければ配る前に戻す」既存の経路（`init`）がそのまま使える。
    private func persistBetween() {
        save(hands: [], dealerHand: [], deck: [])
        // 局を持たない中断データは「続きから戻れる」ではない（#1104。CodeRabbit の指摘）。
        // `GameServices.gameDidLeave` は中断データの有無だけで判定するため、伝えないと
        // 離脱が休憩として数えられ、続きの無い局に「途中のままです」のお知らせが予約される。
        // どちらも次のラウンドを配った時点（`gameDidRestart` → `gameDidBeginPlay`）で元へ戻る。
        services?.gameWillNotResume(gameID: gameID)
        services?.gameDidRestoreFinished(gameID: gameID)
    }

    // MARK: - Deal

    /// 次のラウンドを配る。
    public func deal() {
        guard phase == .ready, !isMatchOver else { return }
        streakBeforeRound = streak
        deck = shuffledDeck()
        hands = [BlackjackHand(id: 0, cards: [drawCard(), drawCard()])]
        activeHandIndex = 0
        dealerHand = [drawCard(), drawCard()]
        phase = .playerTurn
        // 1 ラウンド = 1 プレイ（`gameDidFinish` もラウンドごとに呼んでいる）。
        // 決着が即決まるブラックジャックでも `game_start` が先に立つよう、判定より前に数える（#158）。
        services?.gameDidRestart(gameID: gameID)
        // 配った時点で途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)

        // ディーラーのナチュラルも配った時点で見る（標準ルール）。見ないまま続行させると、
        // スプリットで増やした手まで負けにされる。プレイヤーもナチュラルならプッシュ。
        if isBlackjack(playerHand) || isBlackjack(dealerHand) {
            resolveAll()
            return
        }
        services?.feedback.impact(.medium) // カードを配る
        persist()
    }

    // MARK: - Player Actions

    public func hit() {
        guard phase == .playerTurn, hands.indices.contains(activeHandIndex) else { return }
        hands[activeHandIndex].cards.append(drawCard())
        guard hands[activeHandIndex].isBusted else {
            services?.feedback.impact(.light) // 1枚引く
            persist()
            return
        }
        hands[activeHandIndex].isDone = true
        // スプリットで次の手が残っているなら、この手だけが飛んだことを伝える
        // （ラウンド全体の決着音は `resolveAll()` が鳴らすので二重に鳴らさない）。
        if hasPendingHand { services?.feedback.notify(.error) }
        advanceHand()
    }

    public func stand() {
        guard phase == .playerTurn, hands.indices.contains(activeHandIndex) else { return }
        hands[activeHandIndex].isDone = true
        advanceHand()
    }

    // MARK: - Split (#439)

    /// 手の形としてスプリットできるか（同じ点数の2枚。**再スプリットは不可**）。
    ///
    /// 判定はランクではなく**点数**で行う（#497）。10・J・Q・K はどれも 10 点なので、
    /// 10 と K のような組み合わせも割れる（標準カジノルール）。A は 11 点で他と重ならないため、
    /// この判定でも「A のペア」だけが A のスプリットになる。
    public var isSplitApplicable: Bool {
        guard phase == .playerTurn, hands.count == 1, let hand = activeHand else { return false }
        return hand.cards.count == 2 && !hand.isDone && hand.cards[0].value == hand.cards[1].value
    }

    /// 同じ点数の2枚を2つの手に分け、それぞれに1枚ずつ配る。
    ///
    /// 標準的な簡略化として **スプリットしたAは1枚だけで強制スタンド**（引き直せない）、
    /// **再スプリット不可**（`isSplitApplicable` が `hands.count == 1` を要求する）とする。
    /// 分けた手で作った21はナチュラルにならない（判定は `settleHand` が担う）。
    /// 点は手ごとに数える（2 手とも勝てば 2 点）。
    public func split() {
        guard isSplitApplicable, let source = activeHand else { return }
        let splittingAces = source.cards[0].rank == 1
        var first = BlackjackHand(id: 0, cards: [source.cards[0], drawCard()], isFromSplit: true)
        var second = BlackjackHand(id: 1, cards: [source.cards[1], drawCard()], isFromSplit: true)
        if splittingAces {
            first.isDone = true
            second.isDone = true
        }
        hands = [first, second]
        activeHandIndex = 0
        services?.feedback.impact(.medium)
        if hands[0].isDone {
            advanceHand()
        } else {
            persist()
        }
    }

    // MARK: - Hand Progression

    private var activeHand: BlackjackHand? {
        hands.indices.contains(activeHandIndex) ? hands[activeHandIndex] : nil
    }

    /// いまの手より後ろに、まだ操作していない手が残っているか。
    private var hasPendingHand: Bool {
        hands.indices.contains { $0 > activeHandIndex && !hands[$0].isDone }
    }

    /// 次の手へ進む。全部終わっていればディーラーの番（全滅していれば即決着）へ移る。
    private func advanceHand() {
        if let next = hands.indices.first(where: { $0 > activeHandIndex && !hands[$0].isDone }) {
            activeHandIndex = next
            persist()
            return
        }
        // どの手も残っていなければディーラーは引く必要がない（従来のバストと同じ扱い）。
        guard hands.contains(where: { !$0.isBusted }) else {
            resolveAll()
            return
        }
        phase = .dealerTurn
        runDealer()
    }

    // MARK: - Dealer AI (17以上でスタンド)

    private func runDealer() {
        guard dealerDrawInterval > .zero else {
            drawDealerToStand()
            resolveAll()
            return
        }
        persist()
        startDealerDraws()
    }

    /// ディーラーを1枚ずつ引かせる（#667）。一気に引き切ると結果だけが瞬間的に出て、勝った実感が残らない。
    ///
    /// 伏せカードの公開 → 間 → 1枚 → 間 → … → 間 → 決着、の順に進む。17 以上で最初から止まる手でも
    /// 1回ぶん間を置き、公開の直後に勝敗が出ないようにする。決着（記録の送信）は従来どおり
    /// `resolveAll()` の1か所だけで、引き終わってから1回だけ走る。
    ///
    /// ディーラーの引きは CPU の手番なので触覚は鳴らさない（指が触れていない間の振動を避ける規約。
    /// `FeedbackCPUSilentTests`）。決着の notify は `resolveAll()` が従来どおり鳴らす。
    private func startDealerDraws() {
        let interval = dealerDrawInterval
        dealerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: interval)
                // 「結果まで進める」・やり直しで止められたか、画面ごと捨てられた。
                guard !Task.isCancelled, let self, self.phase == .dealerTurn else { return }
                guard handValue(self.dealerHand) < 17 else {
                    self.dealerTask = nil
                    self.resolveAll()
                    return
                }
                self.dealerHand.append(self.drawCard())
                self.persist()
            }
        }
    }

    /// 「結果まで進める」（#667）。ディーラーの残りを待たずに引き切って決着する。
    /// 引く札は待った場合と同じ（山札の順に引くだけ）なので、飛ばしても結果は変わらない。
    public func skipDealerDraws() {
        guard phase == .dealerTurn else { return }
        dealerTask?.cancel()
        dealerTask = nil
        drawDealerToStand()
        resolveAll()
    }

    private func drawDealerToStand() {
        while handValue(dealerHand) < 17 {
            dealerHand.append(drawCard())
        }
    }

    // MARK: - Result

    /// 手1つぶんの判定。バストは相手を見るまでもなく負け。
    private func settleHand(_ hand: BlackjackHand) -> BlackjackOutcome {
        if hand.isBusted { return .bust }
        return blackjackSettlement(player: hand.cards, dealer: dealerHand,
                                   allowsPlayerNatural: !hand.isFromSplit)
    }

    private func resolveAll() {
        var total = 0
        for index in hands.indices {
            let handOutcome = settleHand(hands[index])
            hands[index].outcome = handOutcome
            total += handOutcome.points
        }
        score += total
        roundPoints = total
        roundsPlayed += 1
        // 手が1つならその結果をそのまま出す。スプリットしたラウンドは手ごとに勝敗が割れるので、
        // まとめは点で決める（1 点でも入れば勝ち、全部引き分けなら引き分け、それ以外は負け）。
        if hands.count == 1 {
            outcome = hands.first?.outcome
        } else if total > 0 {
            outcome = .win
        } else if hands.allSatisfy({ $0.outcome == .push }) {
            outcome = .push
        } else {
            outcome = .lose
        }

        // 連勝は勝ちで伸び、負けで切れる。引き分けは続きも切れもしない。
        switch outcome {
        case .playerBlackjack, .win:
            streak += 1
            bestStreakInMatch = max(bestStreakInMatch, streak)
        case .lose, .bust:
            streak = 0
        default:
            break
        }

        phase = .result
        switch outcome {
        case .playerBlackjack, .win: services?.feedback.notify(.success)
        case .push:                  services?.feedback.notify(.warning)
        default:                     services?.feedback.notify(.error)
        }
        // 評価リクエストの見せ場は、最初の 2 枚で 21 のブラックジャックで勝ったとき（#1471）。
        // 合計点は 10 回目の決着のときだけ渡す。毎回渡すと、記録を更新中の勝負では勝つたびに
        // 「自己ベスト更新」が出てしまう。連勝は毎回の勝敗から `PlayRecord` が数える。
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: reviewOutcome,
            score: GameScore(
                metric: .points, points: isMatchOver ? score : nil,
                variant: Self.recordVariant,
                variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: Self.recordVariant)
            ),
            isReviewHighlight: outcome == .playerBlackjack
        )
        // 終わった勝負は保存しない。途中なら進み具合だけ残す。判断は `persist()` の1か所に寄せる。
        persist()
    }

    // MARK: - 決着の表示（#1754）

    /// 決着したラウンドの、卓の中央に出す結果。`.result` でなければ nil。
    ///
    /// 見出しと理由は `outcome` / `roundPoints`（どちらも `resolveAll` が同じ判定から出した値）だけで決めるので、
    /// スプリットで手ごとに勝敗が割れても、表示と実際の点は食い違わない。理由の行に手ごとの内訳を出す。
    public var handResult: HandResult? {
        guard phase == .result, let outcome else { return nil }
        let kind: HandResult.Kind
        let headline: String
        switch outcome {
        case .playerBlackjack: (kind, headline) = (.win, tr("ブラックジャック！"))
        case .win:             (kind, headline) = (.win, tr("勝ち！"))
        case .push:            (kind, headline) = (.draw, tr("引き分け"))
        case .lose, .bust:     (kind, headline) = (.lose, tr("負け"))
        }
        var reason: String
        if hands.count > 1 {
            reason = hands.enumerated().map { index, hand in
                tr("ハンド%lld %@", index + 1, hand.outcome.map(Self.shortLabel) ?? "")
            }.joined(separator: " / ")
        } else {
            reason = singleHandReason(outcome)
        }
        if let points = roundPoints, points > 0 {
            reason = tr("%1$@（+%2$lld点）", reason, points)
        }
        return HandResult(
            kind: kind, headline: headline, reason: reason, chipDelta: nil,
            spokenResult: BlackjackAccessibility.outcomeAnnouncement(outcome: outcome, isSplit: hands.count > 1)
        )
    }

    private static func shortLabel(_ outcome: BlackjackOutcome) -> String {
        switch outcome {
        case .playerBlackjack: return tr("ブラックジャック")
        case .win:             return tr("勝ち")
        case .push:            return tr("引き分け")
        case .lose:            return tr("負け")
        case .bust:            return tr("バスト")
        }
    }

    /// 手が 1 つのときの理由 1 行（例: "21 対 19" / "バスト（24）"）。
    private func singleHandReason(_ outcome: BlackjackOutcome) -> String {
        switch outcome {
        case .bust:
            return tr("バスト（%lld）", playerValue)
        case .playerBlackjack:
            return tr("最初の2枚で21")
        case .win where dealerValue > 21:
            return tr("ディーラーがバスト（%lld）", dealerValue)
        case .lose where isBlackjack(dealerHand):
            return tr("ディーラーがブラックジャック")
        default:
            return tr("あなた%1$lld 対 ディーラー%2$lld", playerValue, dealerValue)
        }
    }

    // MARK: - Next Round

    public func nextRound() {
        guard phase == .result, !isMatchOver else { return }
        outcome = nil
        roundPoints = nil
        clearHands()
        dealerHand = []
        phase = .ready
    }

    private func clearHands() {
        hands = []
        activeHandIndex = 0
    }

    // MARK: - Reward Ad Retry

    /// リワード広告を表示し、**視聴完了したときだけ**直前の負けをなかったことにして、その回を配り直す（#2552）。
    ///
    /// - 負け（バストを含む）の直後だけ効く。**1 回の勝負につき 1 回まで**（中断を挟んでも戻らない。
    ///   `retryUsed` を中断データに持ち回る）。戻るのは新しい勝負（`restartSession`）だけ。
    /// - 回数・連勝は負ける前に戻る（点は負けでは入らないので動かない）。記録に積んだ負けも `cancelLoss` で
    ///   取り消す（広告を見るほど通算成績が増える抜け道にしない。2048 のコンティニューと同じ扱い）。
    /// - 視聴中断・ロード失敗時は何も変更せず `.notEarned` を返す（呼び出し側でユーザーに通知する）。
    /// - 広告のあいだに別の勝負へ入れ替わっていたら適用しない（#727。`.unavailable`）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおりやり直させる。
    public func retryLossAfterAd() async -> RewardedModelOutcome {
        guard canRetryLoss else { return .unavailable }
        let serialBeforeAd = sessionSerial
        let roundBeforeAd = roundsPlayed
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .undo) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        // 広告のロード〜視聴のあいだも画面は操作できる。別の勝負が始まっていたら、そこへ乗せない。
        guard sessionSerial == serialBeforeAd, roundsPlayed == roundBeforeAd, canRetryLoss else { return .unavailable }
        retryUsed = true
        services?.playLog?.cancelLoss(gameID: gameID, variant: Self.recordVariant)
        roundsPlayed -= 1
        score -= roundPoints ?? 0
        streak = streakBeforeRound
        outcome = nil
        roundPoints = nil
        recordResult = nil
        clearHands()
        dealerHand = []
        phase = .ready
        // 配る前にハブへ戻られても、使い切った印が消えて広告をもう一度見られないよう、この時点で書き出す。
        persist()
        return .granted
    }

    // MARK: - Restart

    /// 新しい 10 回勝負を始める。
    public func restartSession() {
        // ディーラーが引いている途中なら止める（#667。新しい勝負の卓に前の局の札が足されない）。
        dealerTask?.cancel()
        dealerTask = nil
        recordResult = nil
        sessionSerial += 1
        roundsPlayed = 0
        score = 0
        streak = 0
        bestStreakInMatch = 0
        streakBeforeRound = 0
        retryUsed = false
        outcome = nil
        roundPoints = nil
        clearHands()
        dealerHand = []
        phase = .ready
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - Deck

    private func makeDeck() -> [BlackjackCard] {
        var cards: [BlackjackCard] = []
        var id = 0
        for suit in BlackjackSuit.allCases {
            for rank in 1...13 {
                cards.append(BlackjackCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }

    /// 山札を切る。`seed` があるときは決定的に切り、次の配りが同じにならないよう種を進める。
    private func shuffledDeck() -> [BlackjackCard] {
        var cards = makeDeck()
        if let current = seed {
            var generator = BlackjackSeededGenerator(seed: current)
            cards.shuffle(using: &generator)
            seed = generator.next()
        } else {
            cards.shuffle()
        }
        return cards
    }

    private func drawCard() -> BlackjackCard {
        if deck.isEmpty { deck = shuffledDeck() }
        return deck.removeFirst()
    }
}

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（CoreEngine の `SplitMix64`・#1074）。本番は `seed` を渡さないので system の乱数を使う。
typealias BlackjackSeededGenerator = SplitMix64
