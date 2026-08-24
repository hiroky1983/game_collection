import Foundation
import MahjongTiles

/// CPU の打牌選択。**乱数を使わない決定的な牌効率**で選ぶ（同じ手牌なら常に同じ牌を切る）。
///
/// 決裁 A の範囲では鳴きが無いため、CPU の判断は「何を切るか」と「立直するか」の 2 つだけ。
/// 相手の河を読む・危険牌を避けるといった守備は次版以降（`docs/ai-devops.md` の段階実装）。
public enum MahjongAI {

    /// 打牌の評価結果。テストから中身を確かめられるよう公開する。
    public struct Choice: Equatable, Sendable {
        public let tile: MahjongTile
        /// 切ったあとのシャンテン数。
        public let shanten: Int
        /// 切ったあとの受け入れ枚数（種類ではなく残り枚数の合計）。
        public let acceptance: Int
    }

    /// 14 枚の手牌から切る牌を選ぶ。
    ///
    /// 優先順位は ①シャンテンが最も進む ②受け入れが最も広い ③孤立した幺九牌から切る、の順。
    /// - Parameters:
    ///   - hand: 自分の手牌（ツモ牌を含む 14 枚）。
    ///   - visible: 場に見えている牌の枚数（自分の手牌・全員の河・ドラ表示牌）。
    ///     受け入れ枚数の計算で「もう残っていない牌」を数えないために使う。
    public static func chooseDiscard(from hand: MahjongHand, visible: [Int]? = nil) -> Choice {
        let seen = visible ?? hand.counts

        // 1 巡目: 切ったあとのシャンテン数だけを見て、最も進む候補に絞る。
        // 受け入れ計算は 1 候補につき 34 通りの再判定が要るため、ここで絞らないと
        // CPU 1 手あたりの計算量が跳ね上がる（実測で通しテストが 3 倍遅くなった）。
        var candidates: [(index: Int, rest: MahjongHand)] = []
        var bestShanten = Int.max
        for index in 0..<MahjongTileOrder.kindCount where hand.counts[index] > 0 {
            let rest = hand.removing(MahjongTileOrder.tile(at: index))
            let shanten = MahjongShanten.shanten(rest)
            if shanten < bestShanten {
                bestShanten = shanten
                candidates = [(index, rest)]
            } else if shanten == bestShanten {
                candidates.append((index, rest))
            }
        }

        // 2 巡目: 同じシャンテンなら受け入れの広さ、それも同じなら切っても痛まない牌。
        var best: Choice?
        var bestIsolation = Int.min
        for (index, rest) in candidates {
            let acceptance = acceptanceCount(of: rest, seen: seen)
            let isolation = isolationScore(index: index, counts: rest.counts)
            let isBetter = best.map { (acceptance, isolation) > ($0.acceptance, bestIsolation) } ?? true
            if isBetter {
                best = Choice(
                    tile: MahjongTileOrder.tile(at: index), shanten: bestShanten, acceptance: acceptance
                )
                bestIsolation = isolation
            }
        }
        // 手牌が空になることは進行上ありえないが、型の都合で既定値を返しておく。
        return best ?? Choice(tile: MahjongTileOrder.tile(at: 0), shanten: 8, acceptance: 0)
    }

    /// 立直するか。聴牌していて点棒があり、山に牌が残っていれば必ず宣言する
    /// （守備を持たない段階なので、打点を最大化する側に倒す）。
    public static func shouldDeclareRiichi(hand: MahjongHand) -> Bool {
        MahjongShanten.isTenpai(hand)
    }

    // MARK: - 評価の部品

    /// この手牌が受け入れられる牌の**残り枚数**の合計。
    static func acceptanceCount(of hand: MahjongHand, seen: [Int]) -> Int {
        MahjongShanten.acceptedTiles(hand).reduce(0) { total, tile in
            let index = MahjongTileOrder.index(of: tile)
            return total + max(0, 4 - seen[index])
        }
    }

    /// 「切っても手が痛まない度合い」。大きいほど先に切ってよい牌。
    ///
    /// 同じ牌の重なりと、数牌の周辺（±2 の範囲）に仲間がいるかで決める。字牌は伸びないぶん
    /// 孤立しやすく、幺九牌は 1 方向にしか伸びないので自然と先に切られる。
    static func isolationScore(index: Int, counts: [Int]) -> Int {
        var neighbours = counts[index] * 4
        if let offset = MahjongTileOrder.numberOffset(index) {
            for distance in 1...2 {
                if offset - distance >= 0 { neighbours += counts[index - distance] * (3 - distance) }
                if offset + distance <= 8 { neighbours += counts[index + distance] * (3 - distance) }
            }
        }
        // 仲間が少ないほど「切ってよい」ので符号を反転する。
        return -neighbours
    }
}
