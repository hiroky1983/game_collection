import Foundation
import CoreEngine

// MARK: - CPU の顔

/// あなたが CPU の札に指をかけたときの、その CPU の顔（「顔に出る」・#1577）。
///
/// ジョーカーを持っている CPU は、ジョーカーに触れられると**にやり**（引いてほしい）、
/// それ以外に触れられると**ひやり**（ジョーカーをよけられそう）と顔に出ることがある。
/// 顔に出る確率は CPU の強さで下がり、「むずかしい」は常にポーカーフェイス（`OldMaidTuning.tellChance`）。
/// ジョーカーを持っていない CPU は常にふつうの顔。
public enum OldMaidFace: String, Codable, Sendable, CaseIterable {
    case neutral
    case smile
    case worried
}

// MARK: - 直近の動き

/// 各プレイヤーの直近の動き。画面のバッジと読み上げに使う（文言は View 側で付ける）。
public enum OldMaidAction: Codable, Sendable, Equatable {
    case none
    /// 配ったあとにそろっていたペアを捨てた（組数）。
    case dealtPairs(Int)
    /// 引いた札でペアができて捨てた（その数字）。
    case drewPair(rank: Int)
    /// 引いたがペアにならず手札に入れた。
    case drewKept
}

/// 1 回の「引く」で動いた札。画面の演出と、あなたが引いた札の強調に使う。
public struct OldMaidTransfer: Codable, Sendable, Equatable {
    /// 引かれた人。
    public let from: Int
    /// 引いた人。
    public let to: Int
    public let card: OldMaidCard
    /// 引いた札でペアができて捨てたか。
    public let paired: Bool
}

// MARK: - CPU の強さの中身

/// CPU の強さ（`CPUStrength` の 4 段階）ごとの振る舞い。開始シートの説明文（#416）と一致させる。
public enum OldMaidTuning {
    /// ジョーカーを持つ CPU が、触れられた札に応じて顔に出す確率。
    public static func tellChance(_ strength: CPUStrength) -> Double {
        switch strength {
        case .novice: return 0.9
        case .easy:   return 0.6
        case .normal: return 0.3
        case .hard:   return 0
        }
    }

    /// あなたがジョーカーを引いて手札の右端に置いたまま並びを混ぜていないとき、
    /// あなたから引く CPU がその場所を覚えていてジョーカーをよける確率。
    public static func watchChance(_ strength: CPUStrength) -> Double {
        switch strength {
        case .novice: return 0
        case .easy:   return 0.3
        case .normal: return 0.6
        case .hard:   return 0.9
        }
    }
}

// MARK: - 1 ゲームの進行（純ロジック）

/// ババ抜き 1 ゲームぶんの状態と進行（#1577）。SwiftUI にも Core にも依存しない純粋な値。
///
/// - 53 枚（数字札 52 + ジョーカー 1）を 4 人に配り、それぞれ同じ数字の 2 枚（ペア）を捨てる。
/// - 番の人は、**次の人**（番号が 1 つ大きい人。抜けた人は飛ばす）の手札から伏せたまま 1 枚引く。
///   ペアができれば捨てる。番は引かれた人へ移る。
/// - 手札がなくなった人から順に抜け、最後にジョーカーを持って残った 1 人が負け。
///
/// ジョーカー以外の数字は全体で偶数枚あり、ペアで減るので、残る札の総数は常に奇数。最後に残るのは
/// ジョーカー 1 枚だけで、負けは必ず 1 人に決まる。進行（`Model`）は乱数を外から渡すだけにして、
/// 盤面の生成・合法な引き方・終局判定をこの型だけでテストできるようにしてある。
public struct OldMaidGame: Codable, Sendable, Equatable {
    /// 参加人数（あなた 1 + CPU 3）。
    public static let playerCount = 4
    /// あなたの番号。
    public static let humanIndex = 0
    /// 札の総数（数字札 52 + ジョーカー 1）。
    public static let deckCount = 53

    /// 各プレイヤーの手札。あなたの手札は表示順（引いた札は右端に入り、「シャッフル」で混ざる）。
    /// CPU の手札の並びは伏せた札の並びそのもの（引くたびに混ぜ直す）。
    public private(set) var hands: [[OldMaidCard]]
    /// 抜けた順（1 位から）。
    public private(set) var finishOrder: [Int]
    /// 番の人（引く人）。
    public private(set) var currentPlayer: Int
    /// 捨てたペア（古い順）。捨て札は全員に見えている。
    public private(set) var discardedPairs: [[OldMaidCard]]
    /// 各プレイヤーの直近の動き。
    public private(set) var lastActions: [OldMaidAction]
    /// 直近の「引く」。
    public private(set) var lastTransfer: OldMaidTransfer?
    /// あなたが引いて右端に置いたジョーカーの場所を、あなたから引く CPU が見ているか。
    /// あなたがジョーカーを引くと立ち、「シャッフル」かジョーカーが手札から出ていくと下りる。
    public private(set) var humanJokerWatched: Bool
    /// 「引く」の通し番号。顔の出方の種と、広告・待ちの前後で同じ番かの照合に使う。
    public private(set) var turnSerial: Int
    /// CPU の強さ（`CPUStrength.rawValue`）。1 ゲームの途中では変わらない（「1局=1RuleSet」）。
    public let aiLevel: Int
    /// 顔の出方を決める種。同じ番・同じ札なら何度触れても同じ顔になる（選び直しで顔を引き直せない）。
    public let tellSeed: UInt64

    public var strength: CPUStrength { CPUStrength.strength(for: aiLevel) }

    // MARK: 配り

    /// `deck` の順に `firstPlayer` から 1 枚ずつ配り、全員がペアを捨てた状態で始める。
    ///
    /// - Parameter deck: シャッフル済みの 53 枚。
    /// - Parameter firstPlayer: 最初に配られ、最初に引く人。
    public init(deck: [OldMaidCard], firstPlayer: Int, aiLevel: Int, tellSeed: UInt64) {
        precondition(deck.count == Self.deckCount, "ババ抜きは 53 枚で配る")
        let first = ((firstPlayer % Self.playerCount) + Self.playerCount) % Self.playerCount
        var dealt: [[OldMaidCard]] = Array(repeating: [], count: Self.playerCount)
        for (index, card) in deck.enumerated() {
            dealt[(first + index) % Self.playerCount].append(card)
        }
        // あなたの手札だけは数字順に並べて見せる（CPU の伏せ札は配られた順＝ばらばらのまま）。
        dealt[Self.humanIndex].sort { $0.sortKey < $1.sortKey }

        var pairs: [[OldMaidCard]] = []
        var actions: [OldMaidAction] = Array(repeating: .none, count: Self.playerCount)
        for player in 0..<Self.playerCount {
            let result = Self.removingPairs(from: dealt[player])
            dealt[player] = result.kept
            pairs += result.pairs
            actions[player] = .dealtPairs(result.pairs.count)
        }

        hands = dealt
        discardedPairs = pairs
        lastActions = actions
        lastTransfer = nil
        humanJokerWatched = false
        turnSerial = 0
        self.aiLevel = aiLevel
        self.tellSeed = tellSeed
        currentPlayer = first
        // ペアを捨てただけで手札が空になった人（14 枚がすべてペアだったとき）は、配った順にそのまま抜ける。
        finishOrder = (0..<Self.playerCount).map { (first + $0) % Self.playerCount }.filter { dealt[$0].isEmpty }
        if hands[first].isEmpty, let next = nextActive(after: first) {
            currentPlayer = next
        }
    }

    /// あなたが 1 度でも引いたか（#3000）。2 ゲーム目以降は CPU が先に引くので、手札や手番では見分けられない。
    /// 「引いた」動き（`lastActions`）はその人が引いたときだけ書き換わるので、あなたの欄が配り直後のままなら未着手。
    public var humanHasDrawn: Bool {
        switch lastActions[Self.humanIndex] {
        case .drewPair, .drewKept: true
        case .none, .dealtPairs: false
        }
    }

    /// 手札から同じ数字の 2 枚を順に抜き出す。3 枚ある数字は 1 枚残る。ジョーカーはペアにならない。
    /// 残す札の並びは元のまま。
    public static func removingPairs(from hand: [OldMaidCard]) -> (kept: [OldMaidCard], pairs: [[OldMaidCard]]) {
        var kept: [OldMaidCard] = []
        var pairs: [[OldMaidCard]] = []
        for card in hand {
            if !card.isJoker, let index = kept.firstIndex(where: { !$0.isJoker && $0.rank == card.rank }) {
                pairs.append([kept.remove(at: index), card])
            } else {
                kept.append(card)
            }
        }
        return (kept, pairs)
    }

    // MARK: 状態

    /// まだ手札が残っている人（番号順）。
    public var activePlayers: [Int] { (0..<Self.playerCount).filter { !hands[$0].isEmpty } }

    /// 決着したか（手札が残っているのが 1 人以下）。
    public var isOver: Bool { activePlayers.count <= 1 }

    /// 負け（ジョーカーを持って最後まで残った人）。決着前は nil。
    public var loser: Int? { isOver ? activePlayers.first : nil }

    /// 最終順位（1 位から。負けが最後）。決着前は抜けた人まで。
    public var ranking: [Int] { finishOrder + (loser.map { [$0] } ?? []) }

    /// ジョーカーを持っている人。
    public var jokerHolder: Int? { (0..<Self.playerCount).first { hands[$0].contains(where: \.isJoker) } }

    /// `player` の次の、手札が残っている人（`player` 自身は含めない）。
    public func nextActive(after player: Int) -> Int? {
        for step in 1..<Self.playerCount {
            let candidate = (player + step) % Self.playerCount
            if !hands[candidate].isEmpty { return candidate }
        }
        return nil
    }

    /// `drawer` が引く相手（次の、手札が残っている人）。
    public func target(of drawer: Int) -> Int? { nextActive(after: drawer) }

    /// いまの番の人が引く相手。決着後は nil。
    public var currentTarget: Int? { isOver ? nil : target(of: currentPlayer) }

    /// 手札と捨て札の合計。札が増えも減りもしていないことの検査用（常に 53）。
    public var totalCardCount: Int { hands.reduce(0) { $0 + $1.count } + discardedPairs.count * 2 }

    // MARK: 引く

    /// いまの番の人が、引く相手の手札から `cardID` の札を引く。
    ///
    /// - Parameter insertAt: ペアにならなかったとき手札のどこに入れるか。nil なら右端
    ///   （あなたは常に右端。CPU は Model が乱数で決めて渡す）。
    /// - Returns: 引けたか。決着後・相手の手札に無い札のときは何もしない。
    @discardableResult
    public mutating func draw(cardID: Int, insertAt: Int? = nil) -> Bool {
        guard !isOver, let from = currentTarget,
              let index = hands[from].firstIndex(where: { $0.id == cardID }) else { return false }
        let drawer = currentPlayer
        let card = hands[from].remove(at: index)

        var paired = false
        if !card.isJoker, let match = hands[drawer].firstIndex(where: { !$0.isJoker && $0.rank == card.rank }) {
            let partner = hands[drawer].remove(at: match)
            discardedPairs.append([partner, card])
            lastActions[drawer] = .drewPair(rank: card.rank)
            paired = true
        } else {
            let position = min(max(insertAt ?? hands[drawer].count, 0), hands[drawer].count)
            hands[drawer].insert(card, at: position)
            lastActions[drawer] = .drewKept
        }

        if card.isJoker {
            // あなたが引いたジョーカーは右端に置かれるのを全員が見ている。あなたから出ていけば見張りは要らない。
            humanJokerWatched = drawer == Self.humanIndex
        }
        lastTransfer = OldMaidTransfer(from: from, to: drawer, card: card, paired: paired)

        // 最後の 1 枚を引かれた人が先に抜け、引いてペアで手札が尽きた人が続く。
        if hands[from].isEmpty { finishOrder.append(from) }
        if hands[drawer].isEmpty { finishOrder.append(drawer) }

        turnSerial += 1
        if !isOver, let next = nextActive(after: drawer) {
            currentPlayer = next
        }
        return true
    }

    /// `player` の手札の並びを混ぜる。あなたが混ぜると、ジョーカーの置き場所は見張られなくなる。
    public mutating func shuffleHand<G: RandomNumberGenerator>(of player: Int, using generator: inout G) {
        guard (0..<Self.playerCount).contains(player) else { return }
        hands[player].shuffle(using: &generator)
        if player == Self.humanIndex { humanJokerWatched = false }
    }

    // MARK: CPU

    /// いまの番の CPU が引く札の ID（合法な札だけ）。相手の手札が空・決着後は nil。
    ///
    /// 相手があなたで、ジョーカーの置き場所を見ていた（`humanJokerWatched`）ときは、強さに応じた確率で
    /// ジョーカー以外から選ぶ。それ以外はでたらめに選ぶ（伏せ札は見えないので、読みようがない）。
    public func cpuChoice<G: RandomNumberGenerator>(using generator: inout G) -> Int? {
        guard let from = currentTarget, !hands[from].isEmpty else { return nil }
        let hand = hands[from]
        if from == Self.humanIndex, humanJokerWatched, hand.count > 1, hand.contains(where: \.isJoker),
           Double.random(in: 0..<1, using: &generator) < OldMaidTuning.watchChance(strength) {
            let safe = hand.filter { !$0.isJoker }
            return safe.randomElement(using: &generator)?.id
        }
        return hand.randomElement(using: &generator)?.id
    }

    /// いまの番の CPU の 1 手（引いて、手札の好きな場所に混ぜる）。あなたの番・決着後は何もしない。
    @discardableResult
    public mutating func performCPUTurn<G: RandomNumberGenerator>(using generator: inout G) -> Bool {
        guard !isOver, currentPlayer != Self.humanIndex, let cardID = cpuChoice(using: &generator) else { return false }
        let position = Int.random(in: 0...hands[currentPlayer].count, using: &generator)
        return draw(cardID: cardID, insertAt: position)
    }

    // MARK: 顔

    /// あなたが `player` の札 `cardID` に指をかけたときの、`player` の顔。
    ///
    /// 同じ番（`turnSerial`）・同じ札なら必ず同じ顔を返す（触り直しで顔を引き直せない）。
    public func face(of player: Int, touching cardID: Int?) -> OldMaidFace {
        guard let cardID, (0..<Self.playerCount).contains(player), player != Self.humanIndex,
              hands[player].contains(where: \.isJoker),
              hands[player].contains(where: { $0.id == cardID }) else { return .neutral }
        var generator = SplitMix64(
            seed: tellSeed ^ (UInt64(turnSerial) &* SplitMix64.goldenGamma) ^ (UInt64(cardID) &* 0xD1B5_4A32_D192_ED03)
        )
        let roll = Double(generator.next() >> 11) / Double(UInt64(1) << 53)
        guard roll < OldMaidTuning.tellChance(strength) else { return .neutral }
        return cardID == OldMaidCard.jokerID ? .smile : .worried
    }

    // MARK: 中断データの検査

    /// 中断データから戻した値が壊れていないか（手書き・壊れたデータで落ちないため）。
    public var isConsistent: Bool {
        guard hands.count == Self.playerCount, lastActions.count == Self.playerCount,
              (0..<Self.playerCount).contains(currentPlayer),
              totalCardCount == Self.deckCount else { return false }
        let ids = hands.flatMap { $0 }.map(\.id) + discardedPairs.flatMap { $0 }.map(\.id)
        guard Set(ids).count == Self.deckCount, ids.allSatisfy({ (0..<Self.deckCount).contains($0) }) else { return false }
        guard discardedPairs.allSatisfy({ $0.count == 2 && $0[0].rank == $0[1].rank && !$0[0].isJoker }) else { return false }
        guard Set(finishOrder).count == finishOrder.count,
              finishOrder.allSatisfy({ hands[$0].isEmpty }) else { return false }
        return isOver || !hands[currentPlayer].isEmpty
    }

    // MARK: テスト用

    /// テスト専用: 配りの乱数に依存せず任意の局面から検証するための組み立て口。
    init(hands: [[OldMaidCard]], discardedPairs: [[OldMaidCard]] = [], finishOrder: [Int] = [],
         currentPlayer: Int = humanIndex, aiLevel: Int = CPUStrength.standard.rawValue,
         tellSeed: UInt64 = 1, humanJokerWatched: Bool = false) {
        self.hands = hands
        self.discardedPairs = discardedPairs
        self.finishOrder = finishOrder
        self.currentPlayer = currentPlayer
        self.aiLevel = aiLevel
        self.tellSeed = tellSeed
        self.humanJokerWatched = humanJokerWatched
        lastActions = Array(repeating: .none, count: Self.playerCount)
        lastTransfer = nil
        turnSerial = 0
    }
}
