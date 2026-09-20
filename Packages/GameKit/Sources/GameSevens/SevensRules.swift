import Foundation

/// あるスートの場の開通状況。7 がまだ出ていなければ両方 nil。
/// 7 が出れば `low = high = 7` になり、以後は `low - 1` か `high + 1` だけが出せる
/// （七並べは常に連続した範囲でしか開通しないため、置かれた札の集合ではなく
/// 両端の2値だけで場の状態を再現できる）。
public struct SevensSuitRange: Equatable, Codable, Sendable {
    public let low: Int?
    public let high: Int?

    public init(low: Int? = nil, high: Int? = nil) {
        self.low = low
        self.high = high
    }

    /// このスートで既に場に出ているランク（ヒント表示・進行表示に使う）。
    public var placedRanks: Set<Int> {
        guard let low, let high else { return [] }
        return Set(low...high)
    }
}

/// 七並べのルールを**乱数も状態も持たない純粋関数**として閉じ込めた層（#1198）。
///
/// CPU 思考は「出せる手の中から選ぶ」単純な優先順位ロジックで足り、将棋・大富豪のような
/// 探索基盤（CoreEngine）は不要なので、この Package は Core だけに依存する。
public enum SevensRules {
    /// 最初に出せるランク（起点）。
    public static let startRank = 7
    /// 参加人数（人間1 + CPU3）。
    public static let playerCount = 4
    /// 1人あたりの手札枚数（52 ÷ 4）。
    public static let handSize = 13

    // MARK: - 合法判定

    /// `card` を今の場に出せるか。そのスートがまだ着手されていなければ 7 のみ、
    /// 着手済みなら現在の下限の1つ下か上限の1つ上だけが出せる。
    public static func canPlay(_ card: SevensCard, board: [SevensSuitRange]) -> Bool {
        let range = board[card.suit.rawValue]
        guard let low = range.low, let high = range.high else {
            return card.rank == startRank
        }
        return card.rank == low - 1 || card.rank == high + 1
    }

    /// 手札の中で今出せる札の一覧。
    public static func playableCards(hand: [SevensCard], board: [SevensSuitRange]) -> [SevensCard] {
        hand.filter { canPlay($0, board: board) }
    }

    /// `card` を出した後の場。出せない札を渡した場合は元の場をそのまま返す
    /// （呼び出し側は必ず `canPlay` で確認してから使う想定）。
    public static func apply(_ card: SevensCard, to board: [SevensSuitRange]) -> [SevensSuitRange] {
        guard canPlay(card, board: board) else { return board }
        var board = board
        let index = card.suit.rawValue
        let range = board[index]
        if range.low == nil {
            board[index] = SevensSuitRange(low: card.rank, high: card.rank)
        } else if card.rank == range.low! - 1 {
            board[index] = SevensSuitRange(low: card.rank, high: range.high)
        } else {
            board[index] = SevensSuitRange(low: range.low, high: card.rank)
        }
        return board
    }

    /// 空の場（4スートとも未着手）。
    public static func emptyBoard() -> [SevensSuitRange] {
        Array(repeating: SevensSuitRange(), count: playerCount)
    }

    // MARK: - CPU の選択

    /// CPU の選択（貪欲法）: 出せる手の中から、**7 から最も離れたランク**を優先して出す。
    ///
    /// 両端に近い札（A・K 付近）は将来出せる機会が少ないので早めに処理するのが定石で、
    /// 大富豪のような役の強さ判定は不要なため「距離」だけの軽い優先度で足りる（#1198）。
    /// 同着はカード ID の昇順で機械的に決める（テストで固定するため）。
    public static func greedyPlay(hand: [SevensCard], board: [SevensSuitRange]) -> SevensCard? {
        let plays = playableCards(hand: hand, board: board)
        guard !plays.isEmpty else { return nil }
        // 距離は「大きいほど優先」・ID は「小さいほど優先」で向きが逆なので、
        // 距離を負にして両方とも `min` の「小さいほど優先」に揃える。
        func rankKey(_ card: SevensCard) -> (Int, Int) {
            let distance = abs(card.rank - startRank)
            return (-distance, card.id)
        }
        return plays.min { rankKey($0) < rankKey($1) }
    }

    // MARK: - 開始プレイヤー

    /// 最初の手番。標準ルールに合わせ、♦7 を持つ人から始める。
    /// 見つからない場合（配りの実装ミス以外では起きない）は人間を親にする。
    public static func openingPlayer(hands: [[SevensCard]]) -> Int {
        hands.firstIndex { hand in
            hand.contains { $0.suit == .diamonds && $0.rank == startRank }
        } ?? 0
    }
}
