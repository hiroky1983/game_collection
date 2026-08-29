import Foundation
import MahjongTiles

/// シャンテン数・和了判定・待ち牌。すべて純粋関数で、乱数も状態も持たない。
///
/// シャンテン数は「あと何枚入れ替えれば聴牌になるか」で、**聴牌 = 0 / 和了 = -1**。
/// 通常形（4 面子 + 雀頭）・七対子・国士無双の 3 通りを別々に数え、最小値を採る。
public enum MahjongShanten {

    // MARK: - 公開 API

    /// 手牌のシャンテン数。13 枚でも 14 枚でも受け取れる。
    ///
    /// `meldCount` は副露した面子の数。渡す `hand` は**門前の部分だけ**（副露 1 つにつき 3 枚少ない）。
    /// 副露していると七対子・国士無双は成立しないので、通常形だけを数える。
    public static func shanten(_ hand: MahjongHand, meldCount: Int = 0) -> Int {
        let normal = standard(hand.counts, meldCount: meldCount)
        guard meldCount == 0 else { return normal }
        return min(normal, sevenPairs(hand.counts), thirteenOrphans(hand.counts))
    }

    /// 和了形か（14 枚で 4 面子 + 雀頭 / 七対子 / 国士無双）。
    public static func isWinningHand(_ hand: MahjongHand, meldCount: Int = 0) -> Bool {
        hand.total % 3 == 2 && shanten(hand, meldCount: meldCount) == -1
    }

    /// 聴牌か（あと 1 枚で和了）。
    public static func isTenpai(_ hand: MahjongHand, meldCount: Int = 0) -> Bool {
        shanten(hand, meldCount: meldCount) == 0
    }

    /// 待ち牌（この牌が来れば和了になる牌）。13 枚の手牌に対して使う。
    ///
    /// 自分が既に 4 枚使っている牌は入りようがないので候補から外す。山や他家の河に
    /// 残っているかまでは見ない（待ちの形そのものを表すため）。
    public static func waits(_ hand: MahjongHand, meldCount: Int = 0) -> [MahjongTile] {
        guard hand.total % 3 == 1 else { return [] }
        // 聴牌していなければ待ちは無い。1 回の判定で 34 通りの試行を丸ごと省ける
        // （フリテン判定が打牌のたびに全員ぶん走るため、ここの枝刈りが効く）。
        guard shanten(hand, meldCount: meldCount) == 0 else { return [] }
        return (0..<MahjongTileOrder.kindCount).compactMap { index in
            guard hand.counts[index] < 4 else { return nil }
            let tile = MahjongTileOrder.tile(at: index)
            return isWinningHand(hand.adding(tile), meldCount: meldCount) ? tile : nil
        }
    }

    /// 1 枚加えたときにシャンテン数が進む牌（受け入れ牌）。CPU の打牌選択に使う。
    public static func acceptedTiles(_ hand: MahjongHand, meldCount: Int = 0) -> [MahjongTile] {
        let current = shanten(hand, meldCount: meldCount)
        return (0..<MahjongTileOrder.kindCount).compactMap { index in
            guard hand.counts[index] < 4 else { return nil }
            let tile = MahjongTileOrder.tile(at: index)
            return shanten(hand.adding(tile), meldCount: meldCount) < current ? tile : nil
        }
    }

    // MARK: - 通常形（4 面子 + 雀頭）

    /// 通常形（4 面子 + 雀頭）のシャンテン数。
    ///
    /// `8 - 2×面子 - 搭子 - 雀頭` が通常形のシャンテン数。面子 + 搭子は 4 を超えられない
    /// （5 ブロック目は雀頭で埋まるため）。
    ///
    /// **面子・搭子は色をまたがない**ので、萬子・筒子・索子・字牌の 4 グループを別々に分解し、
    /// あとから足し合わせる。34 種を一度に総当たりすると 1 回 0.3ms かかり、CPU の打牌選択
    /// （1 手あたり百数十回呼ぶ）が実用にならなかった。
    ///
    /// `meldCount`（副露数）は「既に出来ている面子」として最後の集計に足す。門前の枚数が
    /// 副露 1 つにつき 3 枚少ないため、分解側が数えられる面子は自然と `4 - meldCount` で頭打ちになる。
    static func standard(_ counts: [Int], meldCount: Int = 0) -> Int {
        // dp[面子][搭子][雀頭を使ったか] = 到達可能か。面子・搭子は 4 で頭打ちにしてよい
        // （5 ブロック目は式に効かないため）。
        var reachable = [Bool](repeating: false, count: 5 * 5 * 2)
        func index(_ melds: Int, _ partials: Int, _ hasPair: Bool) -> Int {
            (melds * 5 + partials) * 2 + (hasPair ? 1 : 0)
        }
        reachable[index(0, 0, false)] = true

        for group in 0..<4 {
            let start = group * 9
            let end = group == 3 ? MahjongTileOrder.kindCount : start + 9
            let table = groupTable(counts, from: start, to: end, allowsRuns: group < 3)
            var next = [Bool](repeating: false, count: reachable.count)
            for melds in 0...4 {
                for partials in 0...4 {
                    for hasPair in [false, true] where reachable[index(melds, partials, hasPair)] {
                        for groupPair in [false, true] where !(hasPair && groupPair) {
                            for groupMelds in 0...4 {
                                let groupPartials = table[(groupPair ? 1 : 0) * 5 + groupMelds]
                                guard groupPartials >= 0 else { continue }
                                next[index(
                                    min(4, melds + groupMelds),
                                    min(4, partials + groupPartials),
                                    hasPair || groupPair
                                )] = true
                            }
                        }
                    }
                }
            }
            reachable = next
        }

        var best = 8
        for melds in 0...4 {
            for partials in 0...4 {
                for hasPair in [false, true] where reachable[index(melds, partials, hasPair)] {
                    // 5 ブロック目（雀頭の分）は搭子として数えられないので、面子と合わせて 4 で頭打ち。
                    let total = min(4, melds + meldCount)
                    let usable = min(partials, 4 - total)
                    best = min(best, 8 - 2 * total - usable - (hasPair ? 1 : 0))
                }
            }
        }
        return best
    }

    /// 1 グループ（1 色 9 種、または字牌 7 種）を分解したときに取れる搭子の最大数。
    /// 戻り値は `[雀頭を使ったか(0/1) * 5 + 面子数]` の一次元表で、-1 はその組み合わせが作れないこと。
    private static func groupTable(_ counts: [Int], from start: Int, to end: Int, allowsRuns: Bool) -> [Int] {
        var table = [Int](repeating: -1, count: 10)
        var work = Array(counts[start..<end])
        groupSearch(&work, 0, allowsRuns: allowsRuns, melds: 0, partials: 0, hasPair: false, table: &table)
        return table
    }

    private static func groupSearch(
        _ counts: inout [Int],
        _ position: Int,
        allowsRuns: Bool,
        melds: Int,
        partials: Int,
        hasPair: Bool,
        table: inout [Int]
    ) {
        let slot = (hasPair ? 1 : 0) * 5 + min(4, melds)
        if partials > table[slot] { table[slot] = min(4, partials) }
        guard position < counts.count else { return }

        if counts[position] == 0 {
            groupSearch(
                &counts, position + 1, allowsRuns: allowsRuns,
                melds: melds, partials: partials, hasPair: hasPair, table: &table
            )
            return
        }
        let canAddBlock = melds + partials < 4

        if canAddBlock, counts[position] >= 3 {
            counts[position] -= 3
            groupSearch(
                &counts, position, allowsRuns: allowsRuns,
                melds: melds + 1, partials: partials, hasPair: hasPair, table: &table
            )
            counts[position] += 3
        }
        if canAddBlock, allowsRuns, position + 2 < counts.count,
           counts[position + 1] > 0, counts[position + 2] > 0 {
            counts[position] -= 1; counts[position + 1] -= 1; counts[position + 2] -= 1
            groupSearch(
                &counts, position, allowsRuns: allowsRuns,
                melds: melds + 1, partials: partials, hasPair: hasPair, table: &table
            )
            counts[position] += 1; counts[position + 1] += 1; counts[position + 2] += 1
        }
        if !hasPair, counts[position] >= 2 {
            counts[position] -= 2
            groupSearch(
                &counts, position, allowsRuns: allowsRuns,
                melds: melds, partials: partials, hasPair: true, table: &table
            )
            counts[position] += 2
        }
        if canAddBlock, counts[position] >= 2 {
            counts[position] -= 2
            groupSearch(
                &counts, position, allowsRuns: allowsRuns,
                melds: melds, partials: partials + 1, hasPair: hasPair, table: &table
            )
            counts[position] += 2
        }
        if canAddBlock, allowsRuns {
            if position + 1 < counts.count, counts[position + 1] > 0 {
                counts[position] -= 1; counts[position + 1] -= 1
                groupSearch(
                    &counts, position, allowsRuns: allowsRuns,
                    melds: melds, partials: partials + 1, hasPair: hasPair, table: &table
                )
                counts[position] += 1; counts[position + 1] += 1
            }
            if position + 2 < counts.count, counts[position + 2] > 0 {
                counts[position] -= 1; counts[position + 2] -= 1
                groupSearch(
                    &counts, position, allowsRuns: allowsRuns,
                    melds: melds, partials: partials + 1, hasPair: hasPair, table: &table
                )
                counts[position] += 1; counts[position + 2] += 1
            }
        }
        counts[position] -= 1
        groupSearch(
            &counts, position, allowsRuns: allowsRuns,
            melds: melds, partials: partials, hasPair: hasPair, table: &table
        )
        counts[position] += 1
    }

    /// 34 種を一度に総当たりする素朴な実装。**遅いのでテストの照合用にだけ残す**
    /// （色ごとの分解に切り替えた `standard` が同じ値を返すことを無作為な手牌で確かめる）。
    static func standardReference(_ counts: [Int]) -> Int {
        var work = counts
        var best = 8
        search(&work, 0, melds: 0, partials: 0, hasPair: false, best: &best)
        return best
    }

    private static func search(
        _ counts: inout [Int],
        _ index: Int,
        melds: Int,
        partials: Int,
        hasPair: Bool,
        best: inout Int
    ) {
        // 残りをすべて捨てた場合の値。ここで確定させれば途中打ち切りでも取りこぼさない。
        let current = 8 - 2 * melds - partials - (hasPair ? 1 : 0)
        if current < best { best = current }
        // これ以上ブロックを作れないなら、残りを見ても良くならない。
        if melds + partials >= 4 && hasPair { return }
        guard index < MahjongTileOrder.kindCount else { return }

        if counts[index] == 0 {
            search(&counts, index + 1, melds: melds, partials: partials, hasPair: hasPair, best: &best)
            return
        }

        let canAddBlock = melds + partials < 4

        // 暗刻
        if canAddBlock, counts[index] >= 3 {
            counts[index] -= 3
            search(&counts, index, melds: melds + 1, partials: partials, hasPair: hasPair, best: &best)
            counts[index] += 3
        }
        // 順子
        if canAddBlock, let offset = MahjongTileOrder.numberOffset(index), offset <= 6,
           counts[index + 1] > 0, counts[index + 2] > 0 {
            counts[index] -= 1; counts[index + 1] -= 1; counts[index + 2] -= 1
            search(&counts, index, melds: melds + 1, partials: partials, hasPair: hasPair, best: &best)
            counts[index] += 1; counts[index + 1] += 1; counts[index + 2] += 1
        }
        // 雀頭
        if !hasPair, counts[index] >= 2 {
            counts[index] -= 2
            search(&counts, index, melds: melds, partials: partials, hasPair: true, best: &best)
            counts[index] += 2
        }
        // 対子（雀頭ではなく刻子の種として数える）
        if canAddBlock, counts[index] >= 2 {
            counts[index] -= 2
            search(&counts, index, melds: melds, partials: partials + 1, hasPair: hasPair, best: &best)
            counts[index] += 2
        }
        // 両面・辺張・嵌張
        if canAddBlock, let offset = MahjongTileOrder.numberOffset(index) {
            if offset <= 7, counts[index + 1] > 0 {
                counts[index] -= 1; counts[index + 1] -= 1
                search(&counts, index, melds: melds, partials: partials + 1, hasPair: hasPair, best: &best)
                counts[index] += 1; counts[index + 1] += 1
            }
            if offset <= 6, counts[index + 2] > 0 {
                counts[index] -= 1; counts[index + 2] -= 1
                search(&counts, index, melds: melds, partials: partials + 1, hasPair: hasPair, best: &best)
                counts[index] += 1; counts[index + 2] += 1
            }
        }
        // この 1 枚は使わない
        counts[index] -= 1
        search(&counts, index, melds: melds, partials: partials, hasPair: hasPair, best: &best)
        counts[index] += 1
    }

    // MARK: - 七対子

    /// 七対子のシャンテン数。対子が 7 種そろえば和了。
    /// 種類が 7 未満だと、余った対子を割って新しい種類を作る手数が別途要る。
    static func sevenPairs(_ counts: [Int]) -> Int {
        guard counts.reduce(0, +) >= 13 else { return .max }
        let pairs = counts.filter { $0 >= 2 }.count
        let kinds = counts.filter { $0 >= 1 }.count
        return 6 - pairs + max(0, 7 - kinds)
    }

    // MARK: - 国士無双

    /// 国士無双のシャンテン数。幺九牌 13 種 + そのどれかの対子で和了。
    static func thirteenOrphans(_ counts: [Int]) -> Int {
        guard counts.reduce(0, +) >= 13 else { return .max }
        var kinds = 0
        var hasPair = false
        for index in MahjongTileOrder.terminalsAndHonors {
            if counts[index] >= 1 { kinds += 1 }
            if counts[index] >= 2 { hasPair = true }
        }
        return 13 - kinds - (hasPair ? 1 : 0)
    }
}
