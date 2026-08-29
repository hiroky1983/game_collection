import Foundation
import MahjongTiles

/// 和了形の 1 ブロック（面子）。副露した面子もこの型で表し、`isConcealed` で暗と明を区別する。
public struct MahjongMeld: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 順子（3 枚の連番）。
        case run
        /// 刻子（同じ牌 3 枚）。
        case triplet
        /// 槓子（同じ牌 4 枚）。
        case kan
    }

    public let kind: Kind
    /// 順子なら最小の牌、刻子・槓子ならその牌。
    public let tile: MahjongTile
    /// 手の内で出来た面子か。**暗槓は true・鳴いた面子は false**。
    /// 符（明刻 2 符 / 暗刻 4 符）と三暗刻・四暗刻の数え方がここで変わる。
    public let isConcealed: Bool

    public init(kind: Kind, tile: MahjongTile, isConcealed: Bool = true) {
        self.kind = kind
        self.tile = tile
        self.isConcealed = isConcealed
    }

    /// 構成する牌（槓子は 4 枚）。
    public var tiles: [MahjongTile] {
        let index = MahjongTileOrder.index(of: tile)
        switch kind {
        case .triplet: return Array(repeating: tile, count: 3)
        case .kan:     return Array(repeating: tile, count: 4)
        case .run:     return (0..<3).map { MahjongTileOrder.tile(at: index + $0) }
        }
    }

    /// 刻子として数える面子か（槓子を含む）。対々和・三暗刻・役牌の判定に使う。
    public var isTripletLike: Bool { kind == .triplet || kind == .kan }

    /// 幺九牌を含むか（チャンタ・純チャンの判定に使う）。
    public var containsTerminalOrHonor: Bool {
        tiles.contains { MahjongTileOrder.isTerminalOrHonor(MahjongTileOrder.index(of: $0)) }
    }

    /// すべて中張牌（2〜8）か（断幺九の判定に使う）。
    public var isAllSimples: Bool {
        tiles.allSatisfy { !MahjongTileOrder.isTerminalOrHonor(MahjongTileOrder.index(of: $0)) }
    }
}

/// 和了形を 4 面子 + 雀頭に分けた 1 通りの解釈。
///
/// 同じ手牌でも解釈が複数ありうる（例: 三色同順とも一気通貫とも取れる形）ため、
/// 役の判定は**すべての解釈を試して最も高い点になるもの**を採る。
public struct MahjongDecomposition: Equatable, Sendable {
    public let melds: [MahjongMeld]
    public let pair: MahjongTile

    public init(melds: [MahjongMeld], pair: MahjongTile) {
        self.melds = melds
        self.pair = pair
    }
}

public enum MahjongDecomposer {

    /// 門前の手牌を「4 - 副露数」面子 + 雀頭に分ける全通り。通常形でなければ空を返す
    /// （七対子・国士無双はこの形にならないので、役の判定側で個別に扱う）。
    ///
    /// 副露した面子は分解の対象ではないが、役の判定では区別なく使うため戻り値には**含めて**返す。
    public static func decompositions(
        _ hand: MahjongHand, calls: [MahjongCall] = []
    ) -> [MahjongDecomposition] {
        let needed = 4 - calls.count
        guard needed >= 0, hand.total == needed * 3 + 2 else { return [] }
        let called = calls.map(\.meld)
        var results: [MahjongDecomposition] = []
        var counts = hand.counts
        for pairIndex in 0..<MahjongTileOrder.kindCount where counts[pairIndex] >= 2 {
            counts[pairIndex] -= 2
            var melds: [MahjongMeld] = []
            extract(&counts, from: 0, needed: needed, melds: &melds) { found in
                results.append(
                    MahjongDecomposition(
                        melds: found + called, pair: MahjongTileOrder.tile(at: pairIndex)
                    )
                )
            }
            counts[pairIndex] += 2
        }
        return results
    }

    /// 残りの牌をすべて面子に割り切る全通りを列挙する。
    /// 添字の小さい牌から順に消化するので、同じ組み合わせが順番違いで重複しない。
    private static func extract(
        _ counts: inout [Int],
        from index: Int,
        needed: Int,
        melds: inout [MahjongMeld],
        found: ([MahjongMeld]) -> Void
    ) {
        var index = index
        while index < MahjongTileOrder.kindCount, counts[index] == 0 { index += 1 }
        guard index < MahjongTileOrder.kindCount else {
            if melds.count == needed { found(melds) }
            return
        }
        guard melds.count < needed else { return }

        if counts[index] >= 3 {
            counts[index] -= 3
            melds.append(MahjongMeld(kind: .triplet, tile: MahjongTileOrder.tile(at: index)))
            extract(&counts, from: index, needed: needed, melds: &melds, found: found)
            melds.removeLast()
            counts[index] += 3
        }
        if let offset = MahjongTileOrder.numberOffset(index), offset <= 6,
           counts[index + 1] > 0, counts[index + 2] > 0 {
            counts[index] -= 1; counts[index + 1] -= 1; counts[index + 2] -= 1
            melds.append(MahjongMeld(kind: .run, tile: MahjongTileOrder.tile(at: index)))
            extract(&counts, from: index, needed: needed, melds: &melds, found: found)
            melds.removeLast()
            counts[index] += 1; counts[index + 1] += 1; counts[index + 2] += 1
        }
    }
}
