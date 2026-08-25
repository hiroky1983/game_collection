import Foundation
import MahjongTiles

/// CPU の打牌選択と鳴きの判断。**乱数を使わない決定的な牌効率**で選ぶ（同じ局面なら常に同じ手）。
///
/// 判断は「何を切るか」「立直するか」「鳴くか」の 3 つ。
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
    ///   - meldCount: 副露した面子の数（`hand` はその分だけ枚数が少ない）。
    ///   - visible: 場に見えている牌の枚数（自分の手牌・全員の河・ドラ表示牌）。
    ///     受け入れ枚数の計算で「もう残っていない牌」を数えないために使う。
    public static func chooseDiscard(
        from hand: MahjongHand, meldCount: Int = 0, visible: [Int]? = nil
    ) -> Choice {
        let seen = visible ?? hand.counts

        // 1 巡目: 切ったあとのシャンテン数だけを見て、最も進む候補に絞る。
        // 受け入れ計算は 1 候補につき 34 通りの再判定が要るため、ここで絞らないと
        // CPU 1 手あたりの計算量が跳ね上がる（実測で通しテストが 3 倍遅くなった）。
        var candidates: [(index: Int, rest: MahjongHand)] = []
        var bestShanten = Int.max
        for index in 0..<MahjongTileOrder.kindCount where hand.counts[index] > 0 {
            let rest = hand.removing(MahjongTileOrder.tile(at: index))
            let shanten = MahjongShanten.shanten(rest, meldCount: meldCount)
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
            let acceptance = acceptanceCount(of: rest, seen: seen, meldCount: meldCount)
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

    // MARK: - 鳴きの判断

    /// 他家の打牌を鳴くか。鳴かないなら nil。
    ///
    /// 「明らかに損な鳴き」を避けるため、次の 2 つを**両方**満たすときだけ鳴く:
    /// 1. 鳴くとシャンテンが進む（形が良くならない鳴きはしない）
    /// 2. 鳴いた後の手に役が見込める（役牌・一色手・断幺九・対々和のいずれか）。
    ///    鳴くと立直・門前清自摸和・平和が消えるため、これを見ないと「和了形にはなるが
    ///    役が無くて上がれない手」を作ってしまう
    ///
    /// さらにチーだけは「鳴けば聴牌になる」場合に限る。チーは打点に結びつきにくく、
    /// 遠い巡目から仕掛けると手が安く狭くなるだけで終わりやすいため。
    ///
    /// - Parameters:
    ///   - options: `MahjongCallFinder.claimOptions` が返した候補（優先度の高い順）。
    ///   - hand: 鳴く人の門前の手牌。
    ///   - melds: すでに鳴いている面子。
    public static func chooseCall(
        options: [MahjongCall],
        hand: MahjongHand,
        melds: [MahjongCall],
        seatWind: Int,
        roundWind: Int
    ) -> MahjongCall? {
        let before = MahjongShanten.shanten(hand, meldCount: melds.count)
        var best: (call: MahjongCall, shanten: Int)?
        for option in options {
            var rest = hand
            for tile in option.tilesFromHand { rest.remove(tile) }
            let after = MahjongShanten.shanten(
                rest, meldCount: melds.count + (option.addsMeld ? 1 : 0)
            )
            guard after < before else { continue }
            if option.kind == .chi && after > 0 { continue }
            guard hasYakuPotential(
                hand: rest, melds: melds + [option], seatWind: seatWind, roundWind: roundWind
            ) else { continue }
            if best == nil || after < best!.shanten { best = (option, after) }
        }
        return best?.call
    }

    /// 自分の手番でカン（暗槓・加槓）するか。**シャンテンが悪くならないときだけ**行う。
    ///
    /// カンは牌を 4 枚固定してしまうため、手が広いうちに切ると受けを狭める。
    /// 逆に形が変わらないなら、新ドラと符が増えるぶん得なので鳴いてよい。
    public static func chooseSelfKan(
        options: [MahjongCall], hand: MahjongHand, drawnTile: MahjongTile?, melds: [MahjongCall]
    ) -> MahjongCall? {
        var full = hand
        if let drawnTile { full.add(drawnTile) }
        let before = MahjongShanten.shanten(full, meldCount: melds.count)
        for option in options {
            var rest = full
            for tile in option.tilesFromHand { rest.remove(tile) }
            let after = MahjongShanten.shanten(
                rest, meldCount: melds.count + (option.addsMeld ? 1 : 0)
            )
            if after <= before { return option }
        }
        return nil
    }

    /// 鳴いた後の手に役が見込めるか。
    static func hasYakuPotential(
        hand: MahjongHand, melds: [MahjongCall], seatWind: Int, roundWind: Int
    ) -> Bool {
        // 役牌の刻子・槓子があれば、それだけで役が確定する。
        for meld in melds where meld.kind != .chi {
            switch meld.tile {
            case .dragon:
                return true
            case .wind(let wind):
                if wind == seatWind || wind == roundWind { return true }
            default:
                break
            }
        }
        let all = hand.tiles + melds.flatMap(\.tiles)
        // 断幺九。
        if all.allSatisfy({ !MahjongTileOrder.isTerminalOrHonor(MahjongTileOrder.index(of: $0)) }) {
            return true
        }
        // 混一色・清一色（数牌が 1 色に収まっている）。
        let suits = Set(all.compactMap { tile -> Int? in
            let index = MahjongTileOrder.index(of: tile)
            return MahjongTileOrder.isNumber(index) ? index / 9 : nil
        })
        if suits.count <= 1 { return true }
        // 対々和（鳴いた面子がすべて刻子系で、手の内にも対子が 2 組以上残っている）。
        if melds.allSatisfy({ $0.kind != .chi }), hand.counts.filter({ $0 >= 2 }).count >= 2 {
            return true
        }
        return false
    }

    // MARK: - 評価の部品

    /// この手牌が受け入れられる牌の**残り枚数**の合計。
    static func acceptanceCount(of hand: MahjongHand, seen: [Int], meldCount: Int = 0) -> Int {
        MahjongShanten.acceptedTiles(hand, meldCount: meldCount).reduce(0) { total, tile in
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
