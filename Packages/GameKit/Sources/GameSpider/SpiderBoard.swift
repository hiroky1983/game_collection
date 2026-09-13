import Foundation

/// プレイヤーが選べる 1 手。UI・ソルバー・中断復元がすべてこの型を通す（#717）。
///
/// 添字は手そのものに全部書く（「空いている列へ」のような実行時に解決する手を混ぜない）。
/// 中断データは「種 + 手順」の再生で復元するので、同じ手順はいつ再生されても同じ盤面に
/// ならなければならない（フリーセル `FreeCellMove` と同じ設計方針）。
///
/// **札をめくる・完成した並びを取り除く手は無い。** どちらも `apply` の中で自動的に起きる
/// （プレイヤーの選択ではないため。手数にも数えない）。
public enum SpiderMove: Equatable, Sendable, Codable, Hashable {
    /// `from` 列の `cardIndex` から上を丸ごと `to` 列へ動かす。
    case move(from: Int, cardIndex: Int, to: Int)
    /// 山札から各列へ 1 枚ずつ配る。
    case deal
}

/// 場札の 1 列。下から `faceDownCount` 枚が伏せ札で、その上はすべて表向き。
public struct SpiderPile: Equatable, Sendable {
    public var cards: [SpiderCard]
    public var faceDownCount: Int

    public init(cards: [SpiderCard], faceDownCount: Int = 0) {
        self.cards = cards
        self.faceDownCount = min(max(0, faceDownCount), cards.count)
    }

    public var isEmpty: Bool { cards.isEmpty }
    public var top: SpiderCard? { cards.last }
    public var faceUpCount: Int { cards.count - faceDownCount }

    public func isFaceUp(_ index: Int) -> Bool { index >= faceDownCount }
}

/// スパイダーソリティアの盤面と規則を、乱数も UI も持たない値型として閉じ込めた層（#717）。
///
/// 採用ルール（標準スパイダー）: 2 組 104 枚・場札 10 列（左 4 列が 6 枚・右 6 列が 5 枚、
/// 一番上だけ表向き）・山札 50 枚（10 枚ずつ 5 回配る）。
///
/// - 場札には**ランクが 1 つ大きい札**の上なら**スートを問わず**置ける。空いた列にはどの札でも置ける。
/// - まとめて動かせるのは**同じスートで降順に揃った並び**だけ（枚数の上限は無い）。
/// - 同じスートで K〜A の 13 枚が揃うと、その並びは自動的に場から取り除かれる。8 組すべて揃えばクリア。
/// - 山札を配れるのは**空いた列が無いとき**だけ（配ると全列に 1 枚ずつ載る）。
public struct SpiderBoard: Equatable, Sendable {
    public static let pileCount = 10
    public static let deckSize = 104
    /// 1 組の並びの長さ（K〜A）。
    public static let sequenceLength = 13
    /// クリアに要する組数。
    public static let sequenceGoal = 8
    /// 山札から 1 回に配る枚数（各列に 1 枚）。
    public static let dealSize = pileCount

    public var piles: [SpiderPile]
    /// 残りの配り。先頭から順に配る。各 `dealSize` 枚。
    public var stock: [[SpiderCard]]
    /// 取り除いた並びのスート（取り除いた順）。
    public var completed: [SpiderSuit]

    public init(piles: [SpiderPile], stock: [[SpiderCard]] = [], completed: [SpiderSuit] = []) {
        self.piles = piles
        self.stock = stock
        self.completed = completed
    }

    // MARK: - 数え上げ

    public var isWon: Bool { completed.count >= Self.sequenceGoal }

    public var emptyPileCount: Int { piles.lazy.filter(\.isEmpty).count }

    public var dealsRemaining: Int { stock.count }

    public var faceDownTotal: Int { piles.reduce(0) { $0 + $1.faceDownCount } }

    /// 山札を配れるか（残りがあり、空いた列が無い）。
    public var canDeal: Bool { !stock.isEmpty && !piles.contains(where: \.isEmpty) }

    /// 山札は残っているのに、空いた列があって配れない状態か（画面の案内に使う）。
    public var isDealBlockedByEmptyPile: Bool { !stock.isEmpty && piles.contains(where: \.isEmpty) }

    // MARK: - 判定

    /// `piles[pile].cards[index...]` が「同じスートで降順」の並びとして丸ごと動かせるか。
    /// 伏せ札を含む位置からは動かせない。
    public func isMovableRun(pile: Int, from index: Int) -> Bool {
        guard piles.indices.contains(pile) else { return false }
        let column = piles[pile]
        guard column.cards.indices.contains(index), column.isFaceUp(index) else { return false }
        let run = column.cards[index...]
        for (upper, lower) in zip(run, run.dropFirst()) {
            if lower.rank != upper.rank - 1 || lower.suit != upper.suit { return false }
        }
        return true
    }

    /// `run`（下端が `first`）を `pile` の上に置けるか。**スートは問わない**（ランクだけ見る）。
    public func canPlace(_ run: [SpiderCard], onPile pile: Int) -> Bool {
        guard piles.indices.contains(pile), let bottom = run.first else { return false }
        guard let top = piles[pile].top else { return true }
        return bottom.rank == top.rank - 1
    }

    public func isLegal(_ move: SpiderMove) -> Bool {
        switch move {
        case .move(let from, let cardIndex, let to):
            guard piles.indices.contains(from), piles.indices.contains(to), from != to else { return false }
            guard isMovableRun(pile: from, from: cardIndex) else { return false }
            return canPlace(Array(piles[from].cards[cardIndex...]), onPile: to)
        case .deal:
            return canDeal
        }
    }

    // MARK: - 適用

    /// 合法手を適用する。非合法な手は無視して false を返す。
    ///
    /// 動かしたあと、**揃った並びの取り除きと伏せ札のめくりを自動で行う**。
    @discardableResult
    public mutating func apply(_ move: SpiderMove) -> Bool {
        guard isLegal(move) else { return false }
        switch move {
        case .move(let from, let cardIndex, let to):
            let run = Array(piles[from].cards[cardIndex...])
            piles[from].cards.removeSubrange(cardIndex...)
            piles[to].cards.append(contentsOf: run)
            settle(pile: to)
            settle(pile: from)
        case .deal:
            let cards = stock.removeFirst()
            for (index, card) in cards.enumerated() where piles.indices.contains(index) {
                piles[index].cards.append(card)
            }
            for pile in piles.indices { settle(pile: pile) }
        }
        return true
    }

    /// 列の後始末: 上に K〜A の同スート並びが揃っていれば取り除き、一番上が伏せ札なら表にする。
    private mutating func settle(pile: Int) {
        if let suit = completedRunSuit(pile: pile) {
            piles[pile].cards.removeLast(Self.sequenceLength)
            completed.append(suit)
        }
        if piles[pile].faceDownCount > 0, piles[pile].faceDownCount == piles[pile].cards.count {
            piles[pile].faceDownCount -= 1
        }
    }

    /// 列の上に K〜A の同スート並びが揃っていればそのスート。
    func completedRunSuit(pile: Int) -> SpiderSuit? {
        let column = piles[pile]
        guard column.faceUpCount >= Self.sequenceLength else { return nil }
        let start = column.cards.count - Self.sequenceLength
        guard column.cards[start].rank == 13, isMovableRun(pile: pile, from: start) else { return nil }
        return column.cards[start].suit
    }

    // MARK: - 詰み検知

    /// 指せる手が 1 つも無い状態（配ることもできない）。
    ///
    /// 配札は勝ち筋のある種だけを出すが、**途中の局面から必ず勝てるわけではない**
    /// （フリーセルと同じ）。告知して「戻す」へ導く。
    public var isDeadEnd: Bool { !isWon && legalMoves.isEmpty }

    /// 合法手の全量。詰み検知と、テストからの網羅に使う。
    ///
    /// 空いた列への置き手は**最初の空列だけ**を挙げる（存在の有無は同じなので、詰み検知には十分）。
    public var legalMoves: [SpiderMove] {
        var moves: [SpiderMove] = []
        let firstEmpty = piles.firstIndex(where: \.isEmpty)
        for from in piles.indices {
            let column = piles[from]
            for index in column.cards.indices.reversed() where index >= column.faceDownCount {
                guard isMovableRun(pile: from, from: index) else { break }
                let run = Array(column.cards[index...])
                for to in piles.indices where to != from {
                    if piles[to].isEmpty, to != firstEmpty { continue }
                    if canPlace(run, onPile: to) {
                        moves.append(.move(from: from, cardIndex: index, to: to))
                    }
                }
            }
        }
        if canDeal { moves.append(.deal) }
        return moves
    }

    // MARK: - 探索用のキー

    /// 同一局面の判定に使う正準表現。
    ///
    /// - 同じスート・同じランクの札は区別しない（`id` ではなく種別で符号化する）。2 組使うため、
    ///   これをしないと「どちらの ♠5 か」だけが違う局面を別物として掘る。
    /// - 伏せ札は**枚数だけ**を書く。伏せ札はその位置から動かないので、列の番号と枚数で中身が決まる。
    /// - 山札が尽きたあとは、**伏せ札の無い列を並べ替えても同じ局面**（合法手の集合が一致する）
    ///   なので辞書順に揃える。山札が残っているあいだは、次の配りでどの列に何が載るかが
    ///   列の番号で決まるため並べ替えない。伏せ札の残る列は中身が列の番号に紐づくので常に位置で持つ。
    public var stateKey: Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.deckSize + 24)
        bytes.append(UInt8(completed.count))
        bytes.append(UInt8(stock.count))
        func encode(_ column: SpiderPile) -> [UInt8] {
            var out: [UInt8] = [UInt8(column.faceDownCount)]
            for card in column.cards[column.faceDownCount...] {
                out.append(UInt8(card.suit.rawValue * 13 + card.rank))
            }
            return out
        }
        if stock.isEmpty {
            var free: [[UInt8]] = []
            for (index, column) in piles.enumerated() {
                if column.faceDownCount > 0 {
                    bytes.append(0xF0 | UInt8(index))
                    bytes.append(contentsOf: encode(column))
                    bytes.append(0xFF)
                } else {
                    free.append(encode(column))
                }
            }
            for column in free.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                bytes.append(contentsOf: column)
                bytes.append(0xFF)
            }
        } else {
            for column in piles {
                bytes.append(contentsOf: encode(column))
                bytes.append(0xFF)
            }
        }
        return Data(bytes)
    }
}
