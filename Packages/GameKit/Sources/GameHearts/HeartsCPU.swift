import Foundation
import CoreEngine

/// ハーツの CPU（Issue #1884）。4 段階の強さ（`CPUStrength`）で考え方を変える。**状態を持たない**純粋な型で、
/// 選ぶ札は必ず `HeartsRules.legalPlays` の中から返す（テストで全段・多数局を回して確かめる）。
///
/// 段ごとの中身（開始シートの説明と一致させる・#416）:
/// - 入門: 出せる札・渡す札をでたらめに選ぶ
/// - かんたん: 小さい札から出し、出せないスートが来たら大きい札を捨てる
/// - ふつう: 取らないように「勝てない範囲で最大の札」を出し、点の札（スペードのクイーン・ハート）を押し付ける
/// - むずかしい: 出た札を覚えて、スペードのクイーンが残っているうちはスペードで追い出しにかかる。渡す札でスートを空ける
public struct HeartsCPU: Sendable {
    public let strength: CPUStrength

    public init(strength: CPUStrength) {
        self.strength = strength
    }

    /// CPU が知っている局面（自分の手札と、場に出た札）。
    public struct Situation: Sendable {
        public let hand: [HeartsCard]
        public let trick: [HeartsPlay]
        public let heartsBroken: Bool
        public let isFirstTrick: Bool
        /// これまでの巡で場に出て片付いた札の ID（いまの巡の札は含めない）。
        public let playedIDs: Set<Int>

        public init(hand: [HeartsCard], trick: [HeartsPlay], heartsBroken: Bool, isFirstTrick: Bool, playedIDs: Set<Int>) {
            self.hand = hand
            self.trick = trick
            self.heartsBroken = heartsBroken
            self.isFirstTrick = isFirstTrick
            self.playedIDs = playedIDs
        }

        var legal: [HeartsCard] {
            HeartsRules.legalPlays(hand: hand, trick: trick, heartsBroken: heartsBroken, isFirstTrick: isFirstTrick)
        }

        /// スペードのクイーンが、自分以外の誰かの手にまだ残っている（または出たかどうか分からない）か。
        var queenIsOut: Bool {
            !hand.contains(.queenOfSpades)
                && !playedIDs.contains(HeartsCard.queenOfSpades.id)
                && !trick.contains { $0.card.isQueenOfSpades }
        }
    }

    // MARK: - 渡す札

    /// 左隣へ渡す 3 枚。手札が 3 枚未満なら持っているぶんだけ。
    public func choosePass(hand: [HeartsCard], using rng: inout some RandomNumberGenerator) -> [HeartsCard] {
        let count = min(HeartsRules.passCount, hand.count)
        switch strength {
        case .novice:
            return Array(hand.shuffled(using: &rng).prefix(count))
        case .easy:
            return Array(hand.sorted { ($0.rank, $0.id) > ($1.rank, $1.id) }.prefix(count))
        case .normal:
            return Array(hand.sorted { (passRisk($0, hand: hand), $0.id) > (passRisk($1, hand: hand), $1.id) }.prefix(count))
        case .hard:
            return hardPass(hand: hand, count: count)
        }
    }

    /// 渡す場面のヒント（#3003）。対局中の CPU の強さには合わせず、常に「むずかしい」の考え方
    /// （危ない高い札・スペードのクイーン周り・少ないスートを空ける）で 3 枚を選ぶ。乱数は使わず、同じ手札なら同じ 3 枚。
    public static func recommendedPass(hand: [HeartsCard]) -> [HeartsCard] {
        HeartsCPU(strength: .hard).hardPass(hand: hand, count: min(HeartsRules.passCount, hand.count))
    }

    /// 持っていると危ない度合い（大きいほど先に渡す）。
    private func passRisk(_ card: HeartsCard, hand: [HeartsCard]) -> Int {
        if card.isQueenOfSpades { return 100 }
        if card.suit == .spade, card.rank > 12 { return 90 }
        if card.suit == .heart { return card.rank * 2 }
        return card.rank + 2
    }

    /// むずかしい: スペードのクイーンを低いスペード 3 枚以上で守れるなら持ち続ける。
    /// クラブ・ダイヤのうち 2 枚以下のスートは丸ごと渡して空け、残りは危ない札から埋める。
    private func hardPass(hand: [HeartsCard], count: Int) -> [HeartsCard] {
        let lowSpades = hand.filter { $0.suit == .spade && $0.rank < 12 }.count
        let keepQueen = hand.contains(.queenOfSpades) && lowSpades >= 3
        func risk(_ card: HeartsCard) -> Int {
            if card.isQueenOfSpades { return keepQueen ? -10 : 100 }
            return passRisk(card, hand: hand)
        }
        var chosen: [HeartsCard] = []
        let shortSuits = [HeartsSuit.club, .diamond]
            .map { suit in hand.filter { $0.suit == suit } }
            .filter { !$0.isEmpty && $0.count <= 2 }
            .sorted { $0.count < $1.count }
        // 危険な札（Q・A・K のスペード、高いハート）を先に確保してから、空けられるスートを足す。
        let urgent = hand.filter { risk($0) >= 90 }.sorted { (risk($0), $0.id) > (risk($1), $1.id) }
        chosen.append(contentsOf: urgent.prefix(count))
        for suit in shortSuits where chosen.count + suit.count <= count {
            chosen.append(contentsOf: suit.filter { !chosen.contains($0) })
        }
        let rest = hand.filter { !chosen.contains($0) }.sorted { (risk($0), $0.id) > (risk($1), $1.id) }
        chosen.append(contentsOf: rest.prefix(count - chosen.count))
        return Array(chosen.prefix(count))
    }

    // MARK: - 出す札

    /// 次に出す札。出せる札が無い局面（手札が空）では nil。
    public func choosePlay(_ view: Situation, using rng: inout some RandomNumberGenerator) -> HeartsCard? {
        let legal = view.legal
        guard let first = legal.first else { return nil }
        if legal.count == 1 { return first }
        switch strength {
        case .novice:
            return legal.randomElement(using: &rng)
        case .easy:
            return easyPlay(view, legal: legal)
        case .normal, .hard:
            return smartPlay(view, legal: legal)
        }
    }

    /// かんたん: 出だし・スートを合わせるときは小さい札、出せないスートなら大きい札を捨てる。
    private func easyPlay(_ view: Situation, legal: [HeartsCard]) -> HeartsCard {
        if let lead = view.trick.first?.card.suit, !legal.contains(where: { $0.suit == lead }) {
            return legal.max { ($0.rank, $0.id) < ($1.rank, $1.id) }!
        }
        return legal.min { ($0.rank, $0.id) < ($1.rank, $1.id) }!
    }

    /// ふつう・むずかしい。
    private func smartPlay(_ view: Situation, legal: [HeartsCard]) -> HeartsCard {
        let hard = strength == .hard
        guard let lead = view.trick.first?.card.suit else { return chooseLead(view, legal: legal, hard: hard) }

        // 出だしのスートが無い: 点の札・危ない札を押し付ける。
        guard legal.contains(where: { $0.suit == lead }) else {
            if let queen = legal.first(where: \.isQueenOfSpades) { return queen }
            // スペードの A・K はクイーンを引き寄せる。むずかしいはクイーンが残っているときだけ急いで捨てる。
            let highSpades = legal.filter { $0.suit == .spade && $0.rank > 12 }
            if let spade = highSpades.max(by: { $0.rank < $1.rank }), !hard || view.queenIsOut { return spade }
            if let heart = legal.filter({ $0.suit == .heart }).max(by: { $0.rank < $1.rank }) { return heart }
            return legal.max { ($0.rank, $0.id) < ($1.rank, $1.id) }!
        }

        // スートを合わせる。いま勝っている札より小さい札があれば、その中で最大を出す（取らずに大きい札を減らす）。
        let winningRank = view.trick.filter { $0.card.suit == lead }.map(\.card.rank).max() ?? 0
        let ducks = legal.filter { $0.rank < winningRank }
        if let duck = ducks.max(by: { $0.rank < $1.rank }) { return duck }

        // どれを出しても勝ってしまう。
        let isLast = view.trick.count == HeartsRules.playerCount - 1
        let notQueen = legal.filter { !$0.isQueenOfSpades }
        let pool = notQueen.isEmpty ? legal : notQueen
        if isLast {
            // 最後なら取るのは確定。いちばん大きい札で取って手札を軽くする（クイーンは自分に入れない）。
            return pool.max { $0.rank < $1.rank }!
        }
        if hard, lead == .spade, view.queenIsOut {
            // クイーンがまだ外にある: A・K で勝つと押し付けられるので、なるべく小さいスペードで。
            return pool.min { $0.rank < $1.rank }!
        }
        if hard, HeartsRules.points(view.trick.map(\.card)) == 0, lead != .heart, remainingOthers(of: lead, view) >= 6 {
            // むずかしい: まだそのスートが外に多く残る序盤は、点が乗る前に大きい札で取って手札を軽くする。
            return pool.max { $0.rank < $1.rank }!
        }
        return pool.min { $0.rank < $1.rank }!
    }

    /// 先頭に出す札。
    private func chooseLead(_ view: Situation, legal: [HeartsCard], hard: Bool) -> HeartsCard {
        func score(_ card: HeartsCard) -> Int {
            var s = card.rank * 2
            if card.isQueenOfSpades { s += 40 }
            // クイーンがまだ外にあるのに A・K のスペードで出ると、クイーンを乗せられる。
            if card.suit == .spade, card.rank > 12, view.queenIsOut || view.hand.contains(.queenOfSpades) { s += 40 }
            if card.suit == .heart { s += 6 }
            if hard {
                // クイーンを持っていないなら、小さいスペードで出てクイーンを追い出す。
                if card.suit == .spade, card.rank < 12, view.queenIsOut { s -= 12 }
                // 外にそのスートがほとんど残っていない（誰かが空いている）なら、点を乗せられやすいので避ける。
                if remainingOthers(of: card.suit, view) <= 2 { s += 15 }
            }
            return s
        }
        return legal.min { (score($0), $0.id) < (score($1), $1.id) }!
    }

    /// 自分の手札・片付いた札・いまの巡の札を除いた、`suit` の残り枚数（ほかの 3 人の手にある数）。
    private func remainingOthers(of suit: HeartsSuit, _ view: Situation) -> Int {
        let seen = Set(view.hand.map(\.id)).union(view.playedIDs).union(view.trick.map(\.card.id))
        return HeartsCard.makeDeck().filter { $0.suit == suit && !seen.contains($0.id) }.count
    }
}
