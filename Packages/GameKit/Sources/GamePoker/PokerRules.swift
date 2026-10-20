import Foundation
import Core

// MARK: - 役の点数表

/// 役 1 つぶんの点数。
public struct PokerPointEntry: Identifiable, Equatable, Sendable {
    public let rank: PokerHandRank
    /// その役で勝ったときにもらえる点。
    public let points: Int

    public var id: Int { rank.rawValue }
}

/// 役の点数表（#2551）。1 回の勝負で、勝った回の**自分の役**に応じて点が入る。
///
/// 負け・引き分けは 0 点。刻みは強い役ほど急に伸びるようにしてあり（ノーペア勝ち 1 点〜ロイヤル 50 点）、
/// 「毎回ワンペアで勝つ」より「大きい役を狙う」ほうが合計点を伸ばせる。数値は仮置きで、QA で調整する。
public enum PokerPointTable {

    /// 強い役から順（画面の点数表もこの順で出す）。
    public static let entries: [PokerPointEntry] = [
        PokerPointEntry(rank: .royalFlush,    points: 50),
        PokerPointEntry(rank: .straightFlush, points: 40),
        PokerPointEntry(rank: .fourOfAKind,   points: 30),
        PokerPointEntry(rank: .fullHouse,     points: 18),
        PokerPointEntry(rank: .flush,         points: 12),
        PokerPointEntry(rank: .straight,      points: 10),
        PokerPointEntry(rank: .threeOfAKind,  points: 6),
        PokerPointEntry(rank: .twoPair,       points: 4),
        PokerPointEntry(rank: .onePair,       points: 2),
        PokerPointEntry(rank: .highCard,      points: 1),
    ]

    /// その役で勝ったときの点。
    public static func points(for rank: PokerHandRank) -> Int {
        entries.first { $0.rank == rank }?.points ?? 0
    }
}

// MARK: - 勝負の形

/// 1 回の勝負の形（#2551）。
public enum PokerMatch {
    /// 1 回の勝負で配る回数。
    public static let roundsPerMatch = 10

    /// 記録の区分キー（`GameScore.variant`）。
    ///
    /// チップ制だった頃の記録（`poker` / `poker#bonus`）とは**単位が違う**ので、同じ保存先に混ぜない。
    /// 旧記録は `PlayLog` が読み込み時に読み飛ばす。
    public static let recordVariant = "round10"
}
