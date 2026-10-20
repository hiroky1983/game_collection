import Foundation
import Core

// MARK: - 役の点数（#2551）

/// 役 1 つぶんの点数。
public struct PokerHandPoints: Identifiable, Equatable, Sendable {
    public let rank: PokerHandRank
    /// その役で勝ったときに入る点。
    public let points: Int

    public var id: Int { rank.rawValue }
}

/// 10 回勝負の役の点数表（#2551・会長決裁 2026-10-20。数値は仮置きで QA で調整する）。
///
/// v1.1.13 の審査で「疑似ギャンブル」と判断されたため、持ち点を出し入れする仕組みをやめ、
/// **勝った回に自分の役の点が入る**だけにした。負け・引き分けは 0 点。
/// 刻みは「1 段上がるごとにおおよそ 1.5〜2 倍」。ノーペア勝ちにも 1 点を付けるのは、
/// 弱い手でも勝てば前に進む手応えを残すため（0 点だと「勝ったのに何も起きない」回ができる）。
public enum PokerScoreTable {

    /// 強い役から順（画面の点数表もこの順で出す）。
    public static let table: [PokerHandPoints] = [
        PokerHandPoints(rank: .royalFlush,    points: 50),
        PokerHandPoints(rank: .straightFlush, points: 40),
        PokerHandPoints(rank: .fourOfAKind,   points: 30),
        PokerHandPoints(rank: .fullHouse,     points: 18),
        PokerHandPoints(rank: .flush,         points: 12),
        PokerHandPoints(rank: .straight,      points: 10),
        PokerHandPoints(rank: .threeOfAKind,  points: 6),
        PokerHandPoints(rank: .twoPair,       points: 4),
        PokerHandPoints(rank: .onePair,       points: 2),
        PokerHandPoints(rank: .highCard,      points: 1),
    ]

    /// その役で勝ったときの点。
    public static func points(for rank: PokerHandRank) -> Int {
        table.first { $0.rank == rank }?.points ?? 0
    }
}
