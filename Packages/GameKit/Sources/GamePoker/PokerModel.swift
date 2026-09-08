import Foundation
import Observation
import Core

// MARK: - Card

public enum PokerSuit: Int, CaseIterable, Codable, Sendable {
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

public struct PokerCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int           // 0–51
    public let suit: PokerSuit
    public let rank: Int         // 2–14 (A=14)

    public var rankLabel: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        case 10: return "10"
        default: return "\(rank)"
        }
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。
    /// 共通基盤は A=1 の表記なので、強さのために A=14 としている `rank` を戻して渡す。
    public var figure: PlayingCardFigure {
        .pip(suit: suit.playing, rank: rank == 14 ? 1 : rank)
    }
}

// MARK: - Hand Rank

public enum PokerHandRank: Int, Comparable, CustomStringConvertible, Sendable {
    case highCard = 0, onePair, twoPair, threeOfAKind,
         straight, flush, fullHouse, fourOfAKind, straightFlush, royalFlush

    public static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        switch self {
        case .highCard:      return "ハイカード"
        case .onePair:       return "ワンペア"
        case .twoPair:       return "ツーペア"
        case .threeOfAKind:  return "スリーカード"
        case .straight:      return "ストレート"
        case .flush:         return "フラッシュ"
        case .fullHouse:     return "フルハウス"
        case .fourOfAKind:   return "フォーカード"
        case .straightFlush: return "ストレートフラッシュ"
        case .royalFlush:    return "ロイヤルフラッシュ"
        }
    }
}

// MARK: - Hand Evaluator

struct HandEvaluator {
    static func evaluate(_ cards: [PokerCard]) -> (rank: PokerHandRank, tieBreaker: [Int]) {
        guard cards.count == 5 else { return (.highCard, []) }
        let ranks = cards.map(\.rank).sorted(by: >)
        let suits = cards.map(\.suit)
        let isFlush = Set(suits).count == 1

        // ストレート（A-2-3-4-5 含む）
        let isStraight: Bool
        if Set(ranks).count == 5 && ranks[0] - ranks[4] == 4 {
            isStraight = true
        } else if ranks == [14, 5, 4, 3, 2] {
            isStraight = true
        } else {
            isStraight = false
        }

        // グループ化
        var countMap: [Int: Int] = [:]
        for r in ranks { countMap[r, default: 0] += 1 }
        let groups = countMap.values.sorted(by: >)

        let isWheel = ranks == [14, 5, 4, 3, 2]
        let straightTieBreaker = isWheel ? [5, 4, 3, 2, 1] : ranks

        if isFlush && isStraight {
            return ranks[0] == 14 && ranks[1] == 13 ? (.royalFlush, ranks) : (.straightFlush, straightTieBreaker)
        }
        if groups == [4, 1] { return (.fourOfAKind, sortedTieBreaker(countMap)) }
        if groups == [3, 2] { return (.fullHouse, sortedTieBreaker(countMap)) }
        if isFlush          { return (.flush, ranks) }
        if isStraight       { return (.straight, straightTieBreaker) }
        if groups == [3, 1, 1] { return (.threeOfAKind, sortedTieBreaker(countMap)) }
        if groups == [2, 2, 1] { return (.twoPair, sortedTieBreaker(countMap)) }
        if groups == [2, 1, 1, 1] { return (.onePair, sortedTieBreaker(countMap)) }
        return (.highCard, ranks)
    }

    static func compare(_ a: [PokerCard], _ b: [PokerCard]) -> Int {
        let ra = evaluate(a); let rb = evaluate(b)
        if ra.rank != rb.rank { return ra.rank > rb.rank ? 1 : -1 }
        for (x, y) in zip(ra.tieBreaker, rb.tieBreaker) {
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    private static func sortedTieBreaker(_ countMap: [Int: Int]) -> [Int] {
        countMap.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key > rhs.key
        }.map(\.key)
    }

    /// CPU が「強い役を目指す」バイアスの分母（#443・2026-09-06 会長決裁「10回に1回は強い役を目指す」）。
    static let ambitionDenominator: UInt64 = 10

    /// 強い役を狙うときに拾う4枚。4フラッシュを優先し、無ければオープンエンドの4連続。
    /// どちらも無ければ nil。インサイドストレート（ガットショット）は期待値が低いので狙わない。
    static func strongDrawIndices(in hand: [PokerCard]) -> Set<Int>? {
        // フラッシュドロー（同スーツ4枚）
        var suitMap: [PokerSuit: [Int]] = [:]
        for (i, c) in hand.enumerated() { suitMap[c.suit, default: []].append(i) }
        if let flushDraw = suitMap.first(where: { $0.value.count == 4 }) {
            return Set(flushDraw.value)
        }
        // ストレートドロー（連続4枚）
        let sorted = hand.enumerated().sorted { $0.element.rank > $1.element.rank }
        let ranks = sorted.map(\.element.rank)
        guard ranks.count >= 4 else { return nil }
        for start in 0...(ranks.count - 4) {
            let seq = Array(ranks[start..<start+4])
            if Set(seq).count == 4 && seq[0] - seq[3] == 3 {
                return Set(sorted[start..<start+4].map(\.offset))
            }
        }
        return nil
    }

    // CPU の捨て牌選択: 残すカードのインデックスセットを返す
    static func cpuKeepIndices(from hand: [PokerCard]) -> Set<Int> {
        var rng = SystemRandomNumberGenerator()
        return cpuKeepIndices(from: hand, using: &rng)
    }

    /// 乱数生成器を注入できる版（テスト用。バイアスの当たり外れを固定できる）。
    static func cpuKeepIndices<G: RandomNumberGenerator>(from hand: [PokerCard], using rng: inout G) -> Set<Int> {
        let (rank, _) = evaluate(hand)
        var countMap: [Int: [Int]] = [:]
        for (i, c) in hand.enumerated() { countMap[c.rank, default: []].append(i) }

        switch rank {
        case .royalFlush, .straightFlush, .fourOfAKind, .fullHouse, .flush, .straight:
            return Set(0..<5)
        case .threeOfAKind:
            let trip = countMap.first { $0.value.count == 3 }!
            return Set(trip.value)
        case .twoPair:
            let pairs = countMap.filter { $0.value.count == 2 }
            return Set(pairs.flatMap(\.value))
        case .onePair:
            let pair = countMap.first { $0.value.count == 2 }!
            // ふだんはペアを残す（実測でこちらが強い）が、10回に1回だけペアを崩して
            // 強い役を狙う（#443・会長決裁 2026-09-06）。狙える形が無ければ賽は振らない
            if let draw = strongDrawIndices(in: hand), rng.next() % ambitionDenominator == 0 {
                return draw
            }
            return Set(pair.value)
        case .highCard:
            // フラッシュドロー・オープンエンドの4連続があればキープ
            if let draw = strongDrawIndices(in: hand) { return draw }
            // Aまたは高カード1枚だけキープ
            if let aceIdx = hand.firstIndex(where: { $0.rank == 14 }) { return [aceIdx] }
            let highIdx = hand.enumerated().max { $0.element.rank < $1.element.rank }!.offset
            return [highIdx]
        }
    }
}

// MARK: - Game Phase

public enum PokerPhase: String, Equatable, Sendable, Codable {
    case idle, dealing, betting1, exchange, cpuExchange, betting2, showdown, result
}

public enum PokerBetAction: Sendable {
    case check, bet(Int), call, raise(Int), fold
}

public enum PokerWinner: String, Sendable, Codable {
    case player, cpu, tie
}

// MARK: - Snapshot

struct PokerSnapshot: Codable {
    let playerHand: [PokerCard]
    let cpuHand: [PokerCard]
    let deck: [PokerCard]
    let playerChips: Int
    let cpuChips: Int
    let pot: Int
    let phase: PokerPhase
    let currentBet: Int
    let playerBetInRound: Int
    let cpuBetInRound: Int
    let cpuFolded: Bool
    let cpuAction: String
    /// その局に焼き込まれたルール（#496）。**旧データには鍵が無い**ので optional のまま置く
    /// （非 optional にすると旧データのデコードが丸ごと失敗し、中断が黙って消える）。
    /// 復元時に nil ならスタンダードとして扱う。既定値があるので既存の呼び出しは変わらない。
    var rules: PokerRuleSet? = nil
    /// チップ切れ復活（#499）をこのセッションで使い切ったか。中断を挟んでも
    /// 「1 セッション 1 回まで」を守るために持ち回る（麻雀のトビ復活 #338 と同じ方式）。
    /// `rules` と同じく**旧データには鍵が無い**ので optional のまま置き、nil は「まだ使っていない」に倒す。
    var hasRevivedThisSession: Bool? = nil
}

// MARK: - Model

@MainActor
@Observable
public final class PokerModel {
    public private(set) var playerHand: [PokerCard] = []
    public private(set) var cpuHand: [PokerCard] = []
    public private(set) var playerChips: Int
    public private(set) var cpuChips: Int
    public private(set) var pot: Int = 0
    public private(set) var phase: PokerPhase = .idle
    public private(set) var winner: PokerWinner? = nil
    public private(set) var playerHandRank: PokerHandRank = .highCard
    public private(set) var cpuHandRank: PokerHandRank = .highCard
    public private(set) var selectedForExchange: Set<Int> = []
    public private(set) var currentBet: Int = 0       // bet level this round
    public private(set) var playerBetInRound: Int = 0
    public private(set) var cpuBetInRound: Int = 0
    public private(set) var cpuFolded: Bool = false
    public private(set) var cpuAction: String = ""
    public private(set) var sessionOver: Bool = false   // チップ0で全体終了
    public private(set) var sessionWinner: PokerWinner? = nil
    /// 直近のラウンドで確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    // MARK: ルール分岐（#496）

    /// **その局に焼き込まれた**ルール。`startGame(rules:)` でだけ変わり、局中は動かない。
    public private(set) var rules: PokerRuleSet = .standard
    /// 直近の勝負でプレイヤーに配当された役ボーナス（0 なら無し）。リザルトに1行出す。
    public private(set) var playerBonus: Int = 0
    /// 直近の勝負で CPU に配当された役ボーナス。
    public private(set) var cpuBonus: Int = 0
    /// ダブルアップに賭けられるチップ（この局でプレイヤーが勝ち取った額）。
    public private(set) var pendingWinnings: Int = 0
    /// ダブルアップの進行状態。挑戦していなければ nil。
    public private(set) var doubleUp: PokerDoubleUp?
    /// ダブルアップの決着待ちで、まだこの局の記録を確定していない。
    public private(set) var awaitsDoubleUp: Bool = false

    /// ダブルアップの連続上限。ここに達したら自動的に受け取って打ち止めにする。
    public static let maxDoubleUpStreak = 5

    /// ダブルアップに挑戦できるか。
    ///
    /// 山札を 2 枚（見せ札 + めくり札）使うので、残りが足りない局では出さない。
    public var canStartDoubleUp: Bool {
        awaitsDoubleUp && doubleUp == nil && pendingWinnings > 0 && deck.count >= 2
    }

    public var canStartRound: Bool { !sessionOver && playerChips >= anteAmount && cpuChips >= anteAmount }

    // MARK: チップ切れ復活（#499）

    /// 復活で戻るプレイヤーのチップ。初期チップの**半分**。導線の文言もこの値から作る
    /// （数え違いを1か所に閉じる）。
    public static let reviveChips = PokerModel.initialChips / 2

    /// このセッションで復活を既に使ったか。1 セッション 1 回までの制限に使う。
    private var hasRevivedThisSession = false

    /// チップ切れをリワード広告で 1 回だけ取り消せる状態か（#499）。
    ///
    /// **自分のチップが尽きて終わった**ときにだけ立てる。CPU が尽きた（＝こちらの勝ち）・
    /// 相打ちの回に出しても続ける動機が無く、麻雀のトビ復活（#338）が「自分がトビたときだけ」に
    /// 絞っているのと同じ判断。1 セッション 1 回まで。
    public var canReviveAfterBust: Bool {
        sessionOver && sessionWinner == .cpu && !hasRevivedThisSession
    }

    /// ラウンドの決着の種類（評価リクエスト #53 の判定用。リザルト表示時に参照する）。
    public var reviewOutcome: GameOutcome {
        switch winner {
        case .player: return .win
        case .tie:    return .draw
        default:      return .loss
        }
    }

    private var deck: [PokerCard] = []
    /// セッション開始時の持ちチップ（プレイヤー・CPU 共通）。
    static let initialChips = 100
    private let anteAmount = 10
    private let betAmount = 20
    private let services: GameServices?

    private let gameID = "poker"

    public init(services: GameServices? = nil) {
        self.services = services
        if let snap = services?.snapshots.load(PokerSnapshot.self, for: "poker") {
            self.playerHand      = snap.playerHand
            self.cpuHand         = snap.cpuHand
            self.deck            = snap.deck
            self.playerChips     = snap.playerChips
            self.cpuChips        = snap.cpuChips
            self.pot             = snap.pot
            self.phase           = snap.phase
            self.currentBet      = snap.currentBet
            self.playerBetInRound = snap.playerBetInRound
            self.cpuBetInRound   = snap.cpuBetInRound
            self.cpuFolded       = snap.cpuFolded
            self.cpuAction       = snap.cpuAction
            // 旧データには鍵が無い。中断前の局はスタンダードしか存在しなかったのでそれに倒す。
            self.rules           = snap.rules ?? .standard
            // 同じく旧データには鍵が無い。復活が存在しなかった頃の中断なので「未使用」に倒す。
            self.hasRevivedThisSession = snap.hasRevivedThisSession ?? false
        } else {
            self.playerChips = PokerModel.initialChips
            self.cpuChips    = PokerModel.initialChips
        }
    }

    private func persist() {
        let savablePhases: [PokerPhase] = [.betting1, .exchange, .cpuExchange, .betting2]
        guard savablePhases.contains(phase) else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            playerChips: playerChips, cpuChips: cpuChips, pot: pot,
            phase: phase, currentBet: currentBet,
            playerBetInRound: playerBetInRound, cpuBetInRound: cpuBetInRound,
            cpuFolded: cpuFolded, cpuAction: cpuAction, rules: rules,
            hasRevivedThisSession: hasRevivedThisSession
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - Start

    /// 1 局を始める。
    ///
    /// - Parameter rules: この局に**焼き込む**ルール。nil なら直前の局と同じものを使い続ける
    ///   （リザルトの「次のゲーム」は開始シートを出さないため）。ここでしかルールは変わらない。
    public func startGame(rules: PokerRuleSet? = nil) {
        // 決着待ちのダブルアップが残っていたら、賭け金を受け取ってこの局を閉じてから次へ進む
        // （持ち点が確定してからでないと `canStartRound` を正しく判定できない）。
        concludeRoundIfNeeded()
        guard canStartRound else { return }
        if let rules { self.rules = rules }
        playerBonus = 0
        cpuBonus = 0
        pendingWinnings = 0
        doubleUp = nil
        awaitsDoubleUp = false
        cpuFolded = false
        winner = nil
        cpuAction = ""
        selectedForExchange = []
        currentBet = 0
        playerBetInRound = 0
        cpuBetInRound = 0
        playerHandRank = .highCard
        cpuHandRank = .highCard
        sessionOver = false
        sessionWinner = nil

        // アンティ
        let playerAnte = min(anteAmount, playerChips)
        let cpuAnte    = min(anteAmount, cpuChips)
        playerChips -= playerAnte
        cpuChips    -= cpuAnte
        pot = playerAnte + cpuAnte

        deck = makeDeck().shuffled()
        playerHand = Array(deck.prefix(5))
        cpuHand = Array(deck.dropFirst(5).prefix(5))
        deck = Array(deck.dropFirst(10))

        phase = .betting1
        services?.feedback.impact(.medium) // カードを配る
        persist()
        // 1 ラウンド = 1 プレイ（`gameDidFinish` もラウンドごとに呼んでいる）。
        // 中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID)
    }

    /// ラウンドの決着。触覚で伝え、ダブルアップの決着待ちでなければその場で記録を確定する。
    ///
    /// ボーナスルールでプレイヤーが勝ち取ったチップはダブルアップで増減しうるので、
    /// **記録（自己ベスト・GC 送信）はダブルアップが終わってから**確定させる（`concludeRound`）。
    /// 触覚だけは勝敗が決まった瞬間に返す。
    private func settleRound() {
        switch winner {
        case .player: services?.feedback.notify(.success)
        case .cpu:    services?.feedback.notify(.error)
        default:      services?.feedback.notify(.warning)
        }
        if rules == .bonus, winner == .player, pendingWinnings > 0, deck.count >= 2 {
            awaitsDoubleUp = true
            return
        }
        concludeRound()
    }

    /// この局の記録を確定する（1 局につき 1 回だけ呼ばれる）。
    private func concludeRound() {
        awaitsDoubleUp = false
        // チップは pot・ボーナス・ダブルアップの精算後なので、この時点の残高が局終了時の持ち点。
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: reviewOutcome,
            score: GameScore(
                metric: .points,
                points: playerChips,
                variant: rules.recordVariant,
                variantLabel: rules.recordVariantLabel,
                // 復活（#499）を使ったセッションは順位表へ送らない（ソリティアのジョーカー #406 と
                // 同じ思想。送ると「広告を何回見たか」の表になる）。ローカルの自己ベストには残す。
                isLeaderboardEligible: rules.isLeaderboardEligible && !hasRevivedThisSession
            )
        )
        checkSessionOver()
    }

    /// ダブルアップの決着待ちなら、賭け金を受け取って局を閉じる。待っていなければ何もしない。
    private func concludeRoundIfNeeded() {
        guard awaitsDoubleUp else { return }
        if doubleUp != nil { collectDoubleUpStake() }
        concludeRound()
    }

    // MARK: - Betting Round 1 (before exchange)

    public func bet1Action(_ action: PokerBetAction) {
        guard phase == .betting1 else { return }
        switch action {
        case .check:
            playerBetInRound = 0
            cpuBet1Response(playerBet: 0)
        case .bet(let amount):
            guard playerChips >= amount else {
                services?.feedback.notify(.warning) // チップ不足でベットできない
                return
            }
            playerChips -= amount
            pot += amount
            playerBetInRound = amount
            services?.feedback.impact(.medium)
            cpuBet1Response(playerBet: amount)
        default: break
        }
    }

    private func cpuBet1Response(playerBet: Int) {
        let (cpuRank, _) = HandEvaluator.evaluate(cpuHand)
        if playerBet == 0 {
            cpuAction = "チェック"
            cpuBetInRound = 0
            phase = .exchange
        } else {
            if cpuRank >= .twoPair {
                let callAmount = min(playerBet, cpuChips)
                cpuChips -= callAmount
                pot += callAmount
                cpuBetInRound = callAmount
                cpuAction = "コール"
                phase = .exchange
            } else {
                cpuFolded = true
                cpuAction = "フォールド"
                endRound()
            }
        }
        persist()
    }

    // MARK: - Exchange

    public func toggleCardSelection(_ card: PokerCard) {
        guard phase == .exchange else { return }
        if selectedForExchange.contains(card.id) {
            selectedForExchange.remove(card.id)
        } else {
            selectedForExchange.insert(card.id)
        }
        services?.feedback.impact(.rigid)
    }

    public func confirmExchange() {
        guard phase == .exchange else { return }
        // プレイヤー交換
        for i in playerHand.indices where selectedForExchange.contains(playerHand[i].id) {
            if let newCard = deck.first {
                deck.removeFirst()
                playerHand[i] = newCard
            }
        }
        selectedForExchange = []
        phase = .cpuExchange
        services?.feedback.impact(.medium) // 交換成立
        performCPUExchange()
        persist()
    }

    private func performCPUExchange() {
        let keepIdx = HandEvaluator.cpuKeepIndices(from: cpuHand)
        let discardCount = 5 - keepIdx.count
        cpuAction = discardCount == 0 ? "カード交換なし" : "\(discardCount)枚交換"
        var newHand = cpuHand
        for i in newHand.indices where !keepIdx.contains(i) {
            if let newCard = deck.first {
                deck.removeFirst()
                newHand[i] = newCard
            }
        }
        cpuHand = newHand

        currentBet = 0
        playerBetInRound = 0
        cpuBetInRound = 0
        phase = .betting2
        persist()
    }

    // MARK: - Betting Round 2 (after exchange)

    public func bet2Action(_ action: PokerBetAction) {
        guard phase == .betting2 else { return }
        switch action {
        case .check:
            playerBetInRound = 0
            cpuBet2Response(playerBet: 0)
        case .bet(let amount):
            guard playerChips >= amount else {
                services?.feedback.notify(.warning) // チップ不足でベットできない
                return
            }
            playerChips -= amount
            pot += amount
            playerBetInRound = amount
            services?.feedback.impact(.medium)
            cpuBet2Response(playerBet: amount)
        case .fold:
            cpuFolded = false
            playerHandRank = HandEvaluator.evaluate(playerHand).rank
            cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
            cpuChips += pot
            pot = 0
            winner = .cpu
            cpuAction = "プレイヤーフォールド"
            phase = .result
            settleRound()
            persist()
        default: break
        }
    }

    private func cpuBet2Response(playerBet: Int) {
        let (cpuRank, _) = HandEvaluator.evaluate(cpuHand)
        if playerBet == 0 {
            if cpuRank >= .twoPair && cpuChips >= betAmount {
                let amount = min(betAmount, cpuChips)
                cpuChips -= amount
                pot += amount
                cpuBetInRound = amount
                cpuAction = "ベット \(amount)"
                phase = .betting2
                currentBet = amount
            } else {
                cpuAction = "チェック"
                phase = .showdown
                resolveShowdown()
            }
        } else {
            if cpuRank >= .onePair {
                let callAmount = min(playerBet, cpuChips)
                cpuChips -= callAmount
                pot += callAmount
                cpuBetInRound = callAmount
                cpuAction = "コール"
                phase = .showdown
                resolveShowdown()
            } else {
                cpuFolded = true
                cpuAction = "フォールド"
                endRound()
            }
        }
        persist()
    }

    public func callCPUBet() {
        guard phase == .betting2, currentBet > 0 else { return }
        let amount = min(currentBet, playerChips)
        playerChips -= amount
        pot += amount
        playerBetInRound += amount
        currentBet = 0
        phase = .showdown
        resolveShowdown()
        persist()
    }

    public func foldToCPUBet() {
        guard phase == .betting2, currentBet > 0 else { return }
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        cpuChips += pot
        pot = 0
        winner = .cpu
        currentBet = 0
        phase = .result
        settleRound()
        persist()
    }

    // MARK: - Showdown

    private func resolveShowdown() {
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        let cmp = HandEvaluator.compare(playerHand, cpuHand)
        if cmp > 0 {
            winner = .player
            playerChips += pot
            pendingWinnings = pot
        } else if cmp < 0 {
            winner = .cpu
            cpuChips += pot
        } else {
            winner = .tie
            playerChips += pot / 2
            cpuChips += pot / 2
        }
        pot = 0
        // 役ボーナスは**手を見せ合って勝ったときだけ**（ショーダウン限定）。フォールド勝ちは
        // 相手の手が伏せられたままなので、役を作った見返りという建て付けが成り立たない。
        // 勝った側に等しく払う（プレイヤー側だけに払うと持ち点の増え方が非対称になり、
        // セッションの難易度がルール選択で変わってしまう）。
        if rules == .bonus {
            switch winner {
            case .player:
                playerBonus = PokerBonusTable.chips(for: playerHandRank)
                playerChips += playerBonus
                pendingWinnings += playerBonus
            case .cpu:
                cpuBonus = PokerBonusTable.chips(for: cpuHandRank)
                cpuChips += cpuBonus
            default:
                break
            }
        }
        phase = .result
        settleRound()
    }

    // MARK: - End Round (fold by CPU or player)

    private func endRound() {
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        if cpuFolded {
            winner = .player
            playerChips += pot
            // フォールド勝ちは役ボーナスもダブルアップも付かない（上記 `resolveShowdown` の理由）。
        }
        pot = 0
        phase = .result
        settleRound()
    }

    // MARK: - ダブルアップ（#496・ボーナスルールのみ）

    /// 勝ち取ったチップを賭けてダブルアップに挑戦する。
    ///
    /// 賭け金はいったん手持ちから引く（外したときにその場で消えるのが自然に見えるため）。
    /// 受け取り・上限到達で戻し、外したら戻さない。
    public func startDoubleUp() {
        guard canStartDoubleUp, let base = deck.first else { return }
        deck.removeFirst()
        playerChips -= pendingWinnings
        doubleUp = PokerDoubleUp(
            stake: pendingWinnings, baseCard: base, drawnCard: nil, streak: 0, result: nil
        )
        services?.feedback.impact(.medium)
    }

    /// 見せ札より上か下かを予想して 1 枚めくる。
    ///
    /// 同じ数字は引き分け。賭け金も挑戦回数もそのままで引き直す（`continueDoubleUp`）。
    public func guessDoubleUp(_ guess: PokerHighLow) {
        guard var state = doubleUp, state.isAwaitingGuess, let drawn = deck.first else { return }
        deck.removeFirst()
        state.drawnCard = drawn

        if drawn.rank == state.baseCard.rank {
            state.result = .push
            doubleUp = state
            services?.feedback.notify(.warning)
            return
        }

        let isHigher = drawn.rank > state.baseCard.rank
        if isHigher == (guess == .high) {
            state.stake *= 2
            state.streak += 1
            state.result = .success
            doubleUp = state
            services?.feedback.notify(.success)
            // 上限まで当てたら打ち止め。賭け金は自動で受け取る。
            if state.streak >= Self.maxDoubleUpStreak { takeDoubleUpWinnings() }
        } else {
            state.stake = 0
            state.result = .failure
            state.isSettled = true
            state.payout = 0
            doubleUp = state
            services?.feedback.notify(.error)
            concludeRound()
        }
    }

    /// 当たり（または引き分け）のあと、めくった札を新しい見せ札にして続ける。
    public func continueDoubleUp() {
        guard var state = doubleUp, let drawn = state.drawnCard,
              state.result == .success || state.result == .push,
              state.streak < Self.maxDoubleUpStreak, !deck.isEmpty
        else { return }
        state.baseCard = drawn
        state.drawnCard = nil
        state.result = nil
        doubleUp = state
        services?.feedback.impact(.rigid)
    }

    /// 賭け金を受け取ってダブルアップを終える。
    public func takeDoubleUpWinnings() {
        guard let state = doubleUp, !state.isSettled else { return }
        collectDoubleUpStake()
        services?.feedback.impact(.medium)
        concludeRound()
    }

    /// 挑戦せずに（または挑戦を終えて）この局を閉じる。
    public func declineDoubleUp() {
        guard awaitsDoubleUp else { return }
        concludeRoundIfNeeded()
    }

    /// 賭け金を手持ちへ戻す。挑戦の経過は表示のために残す。
    private func collectDoubleUpStake() {
        guard var state = doubleUp, !state.isSettled else { return }
        playerChips += state.stake
        state.payout = state.stake
        state.stake = 0
        state.isSettled = true
        doubleUp = state
    }

    #if DEBUG
    /// 撮影用（#496）: ボーナスルールでツーペアの勝ちを作り、ダブルアップの提示まで進める。
    ///
    /// 盤面を直接書き換えるのは配りだけで、決着は通常の `bet2Action` 経路に通す
    /// （撮れた画面が実際の進行と食い違わないようにするため）。`.result` は中断データに
    /// 載らない状態なので、起動引数以外にこの画面へ到達する手立てが無い。
    func debugPresentDoubleUp() {
        rules = .bonus
        playerHand = [
            PokerCard(id: 11, suit: .spades, rank: 13), PokerCard(id: 24, suit: .hearts, rank: 13),
            PokerCard(id: 33, suit: .diamonds, rank: 9), PokerCard(id: 46, suit: .clubs, rank: 9),
            PokerCard(id: 3, suit: .spades, rank: 5),
        ]
        cpuHand = [
            PokerCard(id: 27, suit: .diamonds, rank: 3), PokerCard(id: 15, suit: .hearts, rank: 4),
            PokerCard(id: 4, suit: .spades, rank: 6), PokerCard(id: 34, suit: .diamonds, rank: 10),
            PokerCard(id: 22, suit: .hearts, rank: 11),
        ]
        deck = [
            PokerCard(id: 5, suit: .spades, rank: 7), PokerCard(id: 18, suit: .hearts, rank: 7),
            PokerCard(id: 44, suit: .clubs, rank: 7),
        ]
        playerChips = 100
        cpuChips = 100
        pot = 40
        currentBet = 0
        cpuFolded = false
        winner = nil
        phase = .betting2
        bet2Action(.check)
    }
    #endif

    private func checkSessionOver() {
        if playerChips < anteAmount {
            sessionOver = true
            sessionWinner = .cpu
            services?.snapshots.clear(for: gameID)
        } else if cpuChips < anteAmount {
            sessionOver = true
            sessionWinner = .player
            services?.snapshots.clear(for: gameID)
        }
    }

    // MARK: - Reward Ad / Session Reset

    /// リワード広告を表示し、**視聴完了したときだけ**チップ切れから復活する（#499）。
    ///
    /// - **自分のチップが尽きて終わったときだけ**効く（`canReviveAfterBust`）。
    ///   まだ遊べる残高で呼んでも広告は出さない（プレイヤーが明示的に選んだ救済であって、
    ///   いつでも押せる増量ボタンではない）。
    /// - **1 セッション 1 回まで**。中断を挟んでも回数は戻らない（`hasRevivedThisSession` を
    ///   スナップショットに持ち回る）。回数が戻るのは `restartSession()` の新しいセッションだけ。
    /// - 戻すのは**プレイヤーだけ初期チップの半分**で、CPU は初期チップに戻す。
    ///   CPU の持ち点は勝ち取った資産ではなく卓の設定値なので、そのまま（勝ち越したぶん）残すと
    ///   50 対 250 の卓になって復活の意味が消える。半分の手持ちで対等な卓に戻る、が復活の価値。
    /// - 視聴中断・ロード失敗時は何も変更せず false を返す（呼び出し側でユーザーに通知する）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり回復させる。
    @discardableResult
    public func recoverChipsAfterAd() async -> Bool {
        guard canReviveAfterBust else { return false }
        guard await services?.ads.showRewardedAd() ?? true else { return false }
        hasRevivedThisSession = true
        playerChips = PokerModel.reviveChips
        cpuChips    = PokerModel.initialChips
        sessionOver = false
        sessionWinner = nil
        return true
    }

    public func restartSession() {
        recordResult  = nil
        playerChips   = PokerModel.initialChips
        cpuChips      = PokerModel.initialChips
        // 新しいセッションなので復活の回数も戻る（#499）。
        hasRevivedThisSession = false
        sessionOver   = false
        sessionWinner = nil
        phase         = .idle
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - Deck

    private func makeDeck() -> [PokerCard] {
        var cards: [PokerCard] = []
        var id = 0
        for suit in PokerSuit.allCases {
            for rank in 2...14 {
                cards.append(PokerCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }
}
