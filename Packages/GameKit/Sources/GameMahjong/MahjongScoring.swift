import Foundation
import MahjongTiles

/// 和了したときの状況。役の判定と符計算に必要な情報だけを持つ。
public struct MahjongWinContext: Equatable, Sendable {
    /// 和了牌（手牌 14 枚にはこの牌も含めて渡す）。
    public var winningTile: MahjongTile
    /// ツモ和了か（false ならロン）。
    public var isTsumo: Bool
    /// 立直しているか。
    public var isRiichi: Bool
    /// 一発か（立直の宣言直後 1 巡以内）。
    public var isIppatsu: Bool
    /// 海底摸月 / 河底撈魚（山の最後の牌での和了）。
    public var isLastTile: Bool
    /// 嶺上開花（カンの直後に引いた牌での和了）。
    public var isRinshan: Bool
    /// 槍槓（他家の加槓の牌でのロン）。
    public var isChankan: Bool
    /// 自風。0 = 東 / 1 = 南 / 2 = 西 / 3 = 北。
    public var seatWind: Int
    /// 場風。東風戦なので常に 0（東）。
    public var roundWind: Int
    /// ドラ表示牌。
    public var doraIndicators: [MahjongTile]
    /// 裏ドラ表示牌。立直しているときだけ数える。
    public var uraIndicators: [MahjongTile]

    public init(
        winningTile: MahjongTile,
        isTsumo: Bool,
        isRiichi: Bool = false,
        isIppatsu: Bool = false,
        isLastTile: Bool = false,
        isRinshan: Bool = false,
        isChankan: Bool = false,
        seatWind: Int = 0,
        roundWind: Int = 0,
        doraIndicators: [MahjongTile] = [],
        uraIndicators: [MahjongTile] = []
    ) {
        self.winningTile = winningTile
        self.isTsumo = isTsumo
        self.isRiichi = isRiichi
        self.isIppatsu = isIppatsu
        self.isLastTile = isLastTile
        self.isRinshan = isRinshan
        self.isChankan = isChankan
        self.seatWind = seatWind
        self.roundWind = roundWind
        self.doraIndicators = doraIndicators
        self.uraIndicators = uraIndicators
    }

    /// 親か。
    public var isDealer: Bool { seatWind == 0 }
}

/// 成立した役 1 つ。
public struct MahjongYakuEntry: Equatable, Sendable {
    public let name: String
    /// 飜数。役満は 13 を入れる。
    public let han: Int
    public let isYakuman: Bool

    public init(name: String, han: Int, isYakuman: Bool = false) {
        self.name = name
        self.han = han
        self.isYakuman = isYakuman
    }
}

/// 和了の点数。本場と供託（立直棒）は局の情報なので含めない。
public struct MahjongScore: Equatable, Sendable {
    public let yaku: [MahjongYakuEntry]
    public let han: Int
    public let fu: Int
    /// 満貫以上の呼び名（「満貫」「跳満」…）。それ未満は nil。
    public let limitName: String?
    /// ロン和了で放銃者が払う点。ツモなら 0。
    public let ronPayment: Int
    /// ツモ和了で親が払う点。自分が親なら 0。
    public let tsumoFromDealer: Int
    /// ツモ和了で子ひとりが払う点。
    public let tsumoFromNonDealer: Int
    /// 和了で動く合計点。
    public let total: Int
}

/// 役の判定と点数計算。副露（#263）に対応し、門前限定役の除外と食い下がりを扱う。
///
/// **役満の扱い**: #106 の決裁 A は「役満は次版」としているが、国士無双・四暗刻のように
/// **自然に出来てしまう**形は判定を入れてある。入れないと「和了形なのに役が無く上がれない」
/// という壊れた挙動になるため（例: 国士無双を完成させても和了できない）。
public enum MahjongScoring {

    /// 和了点。役が 1 つも無ければ nil（役なしでは和了できない）。
    ///
    /// - Parameters:
    ///   - hand: **門前部分**の手牌（和了牌を含む）。副露 1 つにつき 3 枚少ない。
    ///   - calls: 副露した面子。
    public static func score(
        hand: MahjongHand, calls: [MahjongCall] = [], context: MahjongWinContext
    ) -> MahjongScore? {
        let meldCount = calls.count
        guard hand.total == 14 - meldCount * 3,
              MahjongShanten.isWinningHand(hand, meldCount: meldCount) else { return nil }

        var candidates: [MahjongScore] = []
        // 七対子・国士無双は 1 つでも鳴くと成立しない（暗槓も 4 枚使うので同じ）。
        if meldCount == 0 {
            if let kokushi = scoreThirteenOrphans(hand: hand, context: context) {
                candidates.append(kokushi)
            }
            if let chiitoi = scoreSevenPairs(hand: hand, context: context) {
                candidates.append(chiitoi)
            }
        }
        for decomposition in MahjongDecomposer.decompositions(hand, calls: calls) {
            // 和了牌をどのブロックに置くかで符と暗刻の数が変わる。全通り試して高いほうを採る。
            let placements = placements(
                of: context.winningTile, in: decomposition, concealedCount: 4 - meldCount
            )
            for placement in placements {
                if let score = scoreStandard(
                    hand: hand, calls: calls, decomposition: decomposition,
                    winningPlacement: placement, context: context
                ) {
                    candidates.append(score)
                }
            }
        }
        // 同じ点なら飜数の高いほうを見せる（見た目の納得感のため）。
        return candidates.max { lhs, rhs in
            (lhs.total, lhs.han) < (rhs.total, rhs.han)
        }
    }

    // MARK: - 和了牌の置き場所

    /// 和了牌が属しうるブロック。`nil` は雀頭（単騎待ち）。
    private enum Placement: Equatable {
        case meld(Int)
        case pair
    }

    /// 和了牌は**門前部分**にしか入らないので、副露した面子（配列の後ろ側）は候補から外す。
    private static func placements(
        of tile: MahjongTile, in decomposition: MahjongDecomposition, concealedCount: Int
    ) -> [Placement] {
        var result: [Placement] = []
        for (index, meld) in decomposition.melds.prefix(concealedCount).enumerated()
        where meld.tiles.contains(tile) {
            result.append(.meld(index))
        }
        if decomposition.pair == tile { result.append(.pair) }
        return result
    }

    // MARK: - 通常形

    private static func scoreStandard(
        hand: MahjongHand,
        calls: [MahjongCall],
        decomposition: MahjongDecomposition,
        winningPlacement: Placement,
        context: MahjongWinContext
    ) -> MahjongScore? {
        var yaku: [MahjongYakuEntry] = []
        let melds = decomposition.melds
        let pair = decomposition.pair
        let runs = melds.filter { $0.kind == .run }
        // 刻子と槓子は「同じ牌の組」としてまとめて数える（対々和・役牌・三暗刻はどちらも同じ扱い）。
        let triplets = melds.filter(\.isTripletLike)
        let kanCount = melds.filter { $0.kind == .kan }.count
        /// 門前か。**暗槓だけは門前を崩さない**。
        let isConcealedHand = calls.allSatisfy { !$0.breaksConcealment }

        // ロンで完成した刻子は明刻扱い（暗刻の数に入れない）。
        let ronCompletedTripletIndex: Int? = {
            guard !context.isTsumo, case .meld(let index) = winningPlacement,
                  melds[index].isTripletLike else { return nil }
            return index
        }()
        let concealedTripletCount = melds.enumerated().filter { index, meld in
            meld.isTripletLike && meld.isConcealed && index != ronCompletedTripletIndex
        }.count

        // --- 役満 ---
        var yakumanCount = 0
        if concealedTripletCount == 4 {
            yaku.append(MahjongYakuEntry(name: "四暗刻", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        let dragonTriplets = triplets.filter { if case .dragon = $0.tile { return true } else { return false } }
        if dragonTriplets.count == 3 {
            yaku.append(MahjongYakuEntry(name: "大三元", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        let windTriplets = triplets.filter { if case .wind = $0.tile { return true } else { return false } }
        let pairIsWind: Bool = { if case .wind = pair { return true } else { return false } }()
        if windTriplets.count == 4 {
            yaku.append(MahjongYakuEntry(name: "大四喜", han: 13, isYakuman: true))
            yakumanCount += 1
        } else if windTriplets.count == 3 && pairIsWind {
            yaku.append(MahjongYakuEntry(name: "小四喜", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        // 副露した牌も一色・字一色・ドラの判定に数える。
        let allTiles = hand.tiles + calls.flatMap(\.tiles)
        if allTiles.allSatisfy({ isHonor($0) }) {
            yaku.append(MahjongYakuEntry(name: "字一色", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        if allTiles.allSatisfy({ isTerminalNumber($0) }) {
            yaku.append(MahjongYakuEntry(name: "清老頭", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        if kanCount == 4 {
            yaku.append(MahjongYakuEntry(name: "四槓子", han: 13, isYakuman: true))
            yakumanCount += 1
        }
        if yakumanCount > 0 {
            return makeScore(
                yaku: yaku, han: 13 * yakumanCount, fu: 0, yakumanCount: yakumanCount, context: context
            )
        }

        // --- 通常役 ---
        // 立直・一発・門前清自摸和・平和・一盃口は門前限定。鳴いた手では付かない。
        if context.isRiichi && isConcealedHand {
            yaku.append(MahjongYakuEntry(name: "立直", han: 1))
            if context.isIppatsu { yaku.append(MahjongYakuEntry(name: "一発", han: 1)) }
        }
        if context.isTsumo && isConcealedHand {
            yaku.append(MahjongYakuEntry(name: "門前清自摸和", han: 1))
        }
        if context.isLastTile {
            yaku.append(MahjongYakuEntry(name: context.isTsumo ? "海底摸月" : "河底撈魚", han: 1))
        }
        if context.isRinshan { yaku.append(MahjongYakuEntry(name: "嶺上開花", han: 1)) }
        if context.isChankan { yaku.append(MahjongYakuEntry(name: "槍槓", han: 1)) }

        let waitKind = self.waitKind(
            placement: winningPlacement, decomposition: decomposition, winningTile: context.winningTile
        )
        let isPinfu = isConcealedHand
            && runs.count == 4
            && !isYakuhaiPair(pair, context: context)
            && waitKind == .twoSided
        if isPinfu { yaku.append(MahjongYakuEntry(name: "平和", han: 1)) }

        if allTiles.allSatisfy({ !isTerminalOrHonor($0) }) {
            yaku.append(MahjongYakuEntry(name: "断幺九", han: 1))
        }
        for triplet in dragonTriplets {
            yaku.append(MahjongYakuEntry(name: "役牌 \(triplet.tile.displayName)", han: 1))
        }
        for triplet in windTriplets {
            guard case .wind(let wind) = triplet.tile else { continue }
            if wind == context.seatWind {
                yaku.append(MahjongYakuEntry(name: "役牌 自風", han: 1))
            }
            if wind == context.roundWind {
                yaku.append(MahjongYakuEntry(name: "役牌 場風", han: 1))
            }
        }

        if isConcealedHand {
            let identicalRunPairs = countIdenticalRunPairs(runs)
            if identicalRunPairs >= 2 {
                yaku.append(MahjongYakuEntry(name: "二盃口", han: 3))
            } else if identicalRunPairs == 1 {
                yaku.append(MahjongYakuEntry(name: "一盃口", han: 1))
            }
        }
        if hasThreeColorRuns(runs) {
            yaku.append(MahjongYakuEntry(name: "三色同順", han: isConcealedHand ? 2 : 1))
        }
        if hasStraight(runs) {
            yaku.append(MahjongYakuEntry(name: "一気通貫", han: isConcealedHand ? 2 : 1))
        }
        if triplets.count == 4 {
            yaku.append(MahjongYakuEntry(name: "対々和", han: 2))
        }
        if concealedTripletCount == 3 {
            yaku.append(MahjongYakuEntry(name: "三暗刻", han: 2))
        }
        if kanCount == 3 {
            yaku.append(MahjongYakuEntry(name: "三槓子", han: 2))
        }

        let allTerminalOrHonor = allTiles.allSatisfy { isTerminalOrHonor($0) }
        if allTerminalOrHonor {
            yaku.append(MahjongYakuEntry(name: "混老頭", han: 2))
        } else {
            let blocksHaveTerminal = melds.allSatisfy(\.containsTerminalOrHonor)
                && isTerminalOrHonor(pair)
            if blocksHaveTerminal {
                let hasHonor = allTiles.contains { isHonor($0) }
                yaku.append(
                    hasHonor
                        ? MahjongYakuEntry(name: "混全帯幺九", han: isConcealedHand ? 2 : 1)
                        : MahjongYakuEntry(name: "純全帯幺九", han: isConcealedHand ? 3 : 2)
                )
            }
        }
        appendFlushYaku(&yaku, tiles: allTiles, isConcealedHand: isConcealedHand)

        guard !yaku.isEmpty else { return nil }
        appendDora(&yaku, tiles: allTiles, context: context)

        let fu = isPinfu
            ? (context.isTsumo ? 20 : 30)
            : standardFu(
                melds: melds, pair: pair, waitKind: waitKind,
                ronCompletedTripletIndex: ronCompletedTripletIndex,
                isConcealedHand: isConcealedHand, context: context
            )
        return makeScore(yaku: yaku, han: yaku.reduce(0) { $0 + $1.han }, fu: fu, yakumanCount: 0, context: context)
    }

    // MARK: - 七対子

    private static func scoreSevenPairs(hand: MahjongHand, context: MahjongWinContext) -> MahjongScore? {
        guard MahjongShanten.sevenPairs(hand.counts) == -1 else { return nil }
        var yaku: [MahjongYakuEntry] = [MahjongYakuEntry(name: "七対子", han: 2)]
        if context.isRiichi {
            yaku.append(MahjongYakuEntry(name: "立直", han: 1))
            if context.isIppatsu { yaku.append(MahjongYakuEntry(name: "一発", han: 1)) }
        }
        if context.isTsumo { yaku.append(MahjongYakuEntry(name: "門前清自摸和", han: 1)) }
        if context.isLastTile {
            yaku.append(MahjongYakuEntry(name: context.isTsumo ? "海底摸月" : "河底撈魚", han: 1))
        }
        let tiles = hand.tiles
        if tiles.allSatisfy({ !isTerminalOrHonor($0) }) {
            yaku.append(MahjongYakuEntry(name: "断幺九", han: 1))
        }
        if tiles.allSatisfy({ isTerminalOrHonor($0) }) {
            yaku.append(MahjongYakuEntry(name: "混老頭", han: 2))
        }
        appendFlushYaku(&yaku, tiles: tiles, isConcealedHand: true)
        appendDora(&yaku, tiles: tiles, context: context)
        // 七対子は 25 符固定。
        return makeScore(yaku: yaku, han: yaku.reduce(0) { $0 + $1.han }, fu: 25, yakumanCount: 0, context: context)
    }

    // MARK: - 国士無双

    private static func scoreThirteenOrphans(hand: MahjongHand, context: MahjongWinContext) -> MahjongScore? {
        guard MahjongShanten.thirteenOrphans(hand.counts) == -1 else { return nil }
        let yaku = [MahjongYakuEntry(name: "国士無双", han: 13, isYakuman: true)]
        return makeScore(yaku: yaku, han: 13, fu: 0, yakumanCount: 1, context: context)
    }

    // MARK: - 役の部品

    private static func appendFlushYaku(
        _ yaku: inout [MahjongYakuEntry], tiles: [MahjongTile], isConcealedHand: Bool
    ) {
        let suits = Set(tiles.compactMap { suitIndex($0) })
        guard suits.count == 1 else { return }
        let hasHonor = tiles.contains { isHonor($0) }
        yaku.append(
            hasHonor
                ? MahjongYakuEntry(name: "混一色", han: isConcealedHand ? 3 : 2)
                : MahjongYakuEntry(name: "清一色", han: isConcealedHand ? 6 : 5)
        )
    }

    private static func appendDora(
        _ yaku: inout [MahjongYakuEntry], tiles: [MahjongTile], context: MahjongWinContext
    ) {
        // 枚数は飜数がそのまま表すので、名前には入れない
        // （"ドラ1" + " 1飜" で「ドラ11飜」と読める表示になっていた）。
        let dora = countDora(tiles: tiles, indicators: context.doraIndicators)
        if dora > 0 { yaku.append(MahjongYakuEntry(name: "ドラ", han: dora)) }
        guard context.isRiichi else { return }
        let ura = countDora(tiles: tiles, indicators: context.uraIndicators)
        if ura > 0 { yaku.append(MahjongYakuEntry(name: "裏ドラ", han: ura)) }
    }

    private static func countDora(tiles: [MahjongTile], indicators: [MahjongTile]) -> Int {
        indicators.reduce(0) { total, indicator in
            let doraIndex = MahjongTileOrder.doraIndex(after: MahjongTileOrder.index(of: indicator))
            let dora = MahjongTileOrder.tile(at: doraIndex)
            return total + tiles.filter { $0 == dora }.count
        }
    }

    /// 同じ順子が 2 組そろっている数（1 = 一盃口 / 2 = 二盃口）。
    private static func countIdenticalRunPairs(_ runs: [MahjongMeld]) -> Int {
        var counts: [MahjongTile: Int] = [:]
        for run in runs { counts[run.tile, default: 0] += 1 }
        return counts.values.reduce(0) { $0 + $1 / 2 }
    }

    private static func hasThreeColorRuns(_ runs: [MahjongMeld]) -> Bool {
        for offset in 0...6 {
            let suits = Set(runs.compactMap { run -> Int? in
                let index = MahjongTileOrder.index(of: run.tile)
                guard MahjongTileOrder.numberOffset(index) == offset else { return nil }
                return index / 9
            })
            if suits.count == 3 { return true }
        }
        return false
    }

    private static func hasStraight(_ runs: [MahjongMeld]) -> Bool {
        for suit in 0..<3 {
            let offsets = Set(runs.compactMap { run -> Int? in
                let index = MahjongTileOrder.index(of: run.tile)
                guard index / 9 == suit, MahjongTileOrder.isNumber(index) else { return nil }
                return index % 9
            })
            if offsets.isSuperset(of: [0, 3, 6]) { return true }
        }
        return false
    }

    // MARK: - 待ちの形と符

    private enum WaitKind {
        /// 両面。
        case twoSided
        /// 嵌張・辺張・単騎（+2 符）。
        case closed
        /// 双碰（刻子待ち）。
        case pairWait
    }

    private static func waitKind(
        placement: Placement, decomposition: MahjongDecomposition, winningTile: MahjongTile
    ) -> WaitKind {
        switch placement {
        case .pair:
            return .closed   // 単騎
        case .meld(let index):
            let meld = decomposition.melds[index]
            guard meld.kind == .run else { return .pairWait }   // 双碰
            let start = MahjongTileOrder.index(of: meld.tile)
            let winning = MahjongTileOrder.index(of: winningTile)
            guard let startOffset = MahjongTileOrder.numberOffset(start) else { return .closed }
            if winning == start + 1 { return .closed }           // 嵌張
            if winning == start, startOffset == 6 { return .closed }      // 789 の 7 待ち = 辺張
            if winning == start + 2, startOffset == 0 { return .closed }  // 123 の 3 待ち = 辺張
            return .twoSided
        }
    }

    private static func standardFu(
        melds: [MahjongMeld],
        pair: MahjongTile,
        waitKind: WaitKind,
        ronCompletedTripletIndex: Int?,
        isConcealedHand: Bool,
        context: MahjongWinContext
    ) -> Int {
        var fu = 20
        // 門前ロンは +10 符。鳴いた手には付かない。
        if !context.isTsumo && isConcealedHand { fu += 10 }
        if context.isTsumo { fu += 2 }

        for (index, meld) in melds.enumerated() where meld.isTripletLike {
            // ロンで完成した刻子は明刻扱い。暗槓は鳴いていないので暗のまま。
            let isConcealed = meld.isConcealed && index != ronCompletedTripletIndex
            let isMajor = isTerminalOrHonor(meld.tile)
            let base = meld.kind == .kan ? (isConcealed ? 16 : 8) : (isConcealed ? 4 : 2)
            fu += base * (isMajor ? 2 : 1)
        }
        // 役牌の雀頭は +2 符。連風牌（自風 = 場風）は 2 つ分数える。
        if case .dragon = pair { fu += 2 }
        if case .wind(let wind) = pair {
            if wind == context.seatWind { fu += 2 }
            if wind == context.roundWind { fu += 2 }
        }
        if waitKind == .closed { fu += 2 }

        // 鳴いた手が 20 符ちょうど（= 全部順子・役牌でない雀頭・両面待ち = 喰い平和形）になる
        // ロンは、一般的なルールどおり 30 符として扱う。ツモは +2 符が付くので切り上げで 30 符になる。
        if !isConcealedHand && fu == 20 { fu = 30 }

        // 10 符単位に切り上げる。
        return (fu + 9) / 10 * 10
    }

    // MARK: - 点数

    private static func makeScore(
        yaku: [MahjongYakuEntry], han: Int, fu: Int, yakumanCount: Int, context: MahjongWinContext
    ) -> MahjongScore {
        let (base, limitName) = basePoints(han: han, fu: fu, yakumanCount: yakumanCount)
        let isDealer = context.isDealer
        if context.isTsumo {
            let fromNonDealer = roundUp(base * (isDealer ? 2 : 1))
            let fromDealer = isDealer ? 0 : roundUp(base * 2)
            let total = isDealer ? fromNonDealer * 3 : fromDealer + fromNonDealer * 2
            return MahjongScore(
                yaku: yaku, han: han, fu: fu, limitName: limitName,
                ronPayment: 0, tsumoFromDealer: fromDealer, tsumoFromNonDealer: fromNonDealer,
                total: total
            )
        }
        let payment = roundUp(base * (isDealer ? 6 : 4))
        return MahjongScore(
            yaku: yaku, han: han, fu: fu, limitName: limitName,
            ronPayment: payment, tsumoFromDealer: 0, tsumoFromNonDealer: 0,
            total: payment
        )
    }

    /// 基本点（子のロンならこの 4 倍が支払額）と、満貫以上の呼び名。
    private static func basePoints(han: Int, fu: Int, yakumanCount: Int) -> (Int, String?) {
        if yakumanCount > 0 {
            return (8000 * yakumanCount, yakumanCount > 1 ? "\(yakumanCount)倍役満" : "役満")
        }
        switch han {
        case 13...: return (8000, "数え役満")
        case 11...12: return (6000, "三倍満")
        case 8...10:  return (4000, "倍満")
        case 6...7:   return (3000, "跳満")
        case 5:       return (2000, "満貫")
        default:
            let base = fu * Int(pow(2.0, Double(2 + han)))
            return base >= 2000 ? (2000, "満貫") : (base, nil)
        }
    }

    /// 支払いは 100 点単位に切り上げる。
    private static func roundUp(_ points: Int) -> Int {
        (points + 99) / 100 * 100
    }

    // MARK: - 牌の分類

    private static func isHonor(_ tile: MahjongTile) -> Bool {
        tile.rank == nil
    }

    private static func isTerminalOrHonor(_ tile: MahjongTile) -> Bool {
        MahjongTileOrder.isTerminalOrHonor(MahjongTileOrder.index(of: tile))
    }

    /// 1 と 9（字牌は含まない）。
    private static func isTerminalNumber(_ tile: MahjongTile) -> Bool {
        guard let rank = tile.rank else { return false }
        return rank == 1 || rank == 9
    }

    /// 数牌なら 0（萬子）/ 1（筒子）/ 2（索子）、字牌なら nil。
    private static func suitIndex(_ tile: MahjongTile) -> Int? {
        let index = MahjongTileOrder.index(of: tile)
        return MahjongTileOrder.isNumber(index) ? index / 9 : nil
    }

    private static func isYakuhaiPair(_ pair: MahjongTile, context: MahjongWinContext) -> Bool {
        switch pair {
        case .dragon: return true
        case .wind(let wind): return wind == context.seatWind || wind == context.roundWind
        default: return false
        }
    }
}
