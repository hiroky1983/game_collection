import Foundation
import MahjongTiles

/// 四人打ち麻雀で実装済みの役（#501）。
///
/// **役早見表（`MahjongYakuSheet`）と役判定（`MahjongScoring`）の唯一の定義source**。
/// 判定側は名前も飜数もこの列挙子から取るので、片方だけ直して表と実装がズレることが起きない
/// （花札の `HanafudaYaku` と同じ作り）。役を足すときはここに 1 件足せば早見表にも自動で載る。
///
/// ドラ・裏ドラは厳密には役ではないが、和了の飜数に加わり早見表でも引かれるため同じ表に持つ
/// （`isDora` で区別し、早見表では別セクションに出す）。
public enum MahjongYaku: String, CaseIterable, Sendable, Equatable {
    // 1 飜
    case riichi
    case ippatsu
    case menzenTsumo
    case pinfu
    case tanyao
    case yakuhaiDragon
    case yakuhaiSeatWind
    case yakuhaiRoundWind
    case iipeikou
    case haitei
    case houtei
    case rinshan
    case chankan
    // 2 飜
    case chiitoitsu
    case toitoi
    case sanankou
    case sankantsu
    case sanshokuDoujun
    case ittsuu
    case chanta
    case honroutou
    // 3 飜
    case ryanpeikou
    case junchan
    case honitsu
    // 6 飜
    case chinitsu
    // 役満
    case kokushi
    case suuankou
    case daisangen
    case shousuushii
    case daisuushii
    case tsuuiisou
    case chinroutou
    case suukantsu
    // 飜だけ増えるもの
    case dora
    case uraDora

    /// 役の表記。**判定側が付ける名前もこれ**（役牌だけは牌の名前を足すので `MahjongYakuEntry` 側で上書きする）。
    public var name: String {
        switch self {
        case .riichi:          return "立直"
        case .ippatsu:         return "一発"
        case .menzenTsumo:     return "門前清自摸和"
        case .pinfu:           return "平和"
        case .tanyao:          return "断幺九"
        case .yakuhaiDragon:   return "役牌"
        case .yakuhaiSeatWind: return "役牌 自風"
        case .yakuhaiRoundWind: return "役牌 場風"
        case .iipeikou:        return "一盃口"
        case .haitei:          return "海底摸月"
        case .houtei:          return "河底撈魚"
        case .rinshan:         return "嶺上開花"
        case .chankan:         return "槍槓"
        case .chiitoitsu:      return "七対子"
        case .toitoi:          return "対々和"
        case .sanankou:        return "三暗刻"
        case .sankantsu:       return "三槓子"
        case .sanshokuDoujun:  return "三色同順"
        case .ittsuu:          return "一気通貫"
        case .chanta:          return "混全帯幺九"
        case .honroutou:       return "混老頭"
        case .ryanpeikou:      return "二盃口"
        case .junchan:         return "純全帯幺九"
        case .honitsu:         return "混一色"
        case .chinitsu:        return "清一色"
        case .kokushi:         return "国士無双"
        case .suuankou:        return "四暗刻"
        case .daisangen:       return "大三元"
        case .shousuushii:     return "小四喜"
        case .daisuushii:      return "大四喜"
        case .tsuuiisou:       return "字一色"
        case .chinroutou:      return "清老頭"
        case .suukantsu:       return "四槓子"
        case .dora:            return "ドラ"
        case .uraDora:         return "裏ドラ"
        }
    }

    /// 読み。役名は漢字だけでは読めないものが多く、読めないと早見表を引く気にならない（#501 の前提）。
    public var reading: String {
        switch self {
        case .riichi:          return "リーチ"
        case .ippatsu:         return "イッパツ"
        case .menzenTsumo:     return "メンゼンツモ"
        case .pinfu:           return "ピンフ"
        case .tanyao:          return "タンヤオ"
        case .yakuhaiDragon:   return "ヤクハイ"
        case .yakuhaiSeatWind: return "ヤクハイ ジカゼ"
        case .yakuhaiRoundWind: return "ヤクハイ バカゼ"
        case .iipeikou:        return "イーペーコー"
        case .haitei:          return "ハイテイラオユエ"
        case .houtei:          return "ホウテイラオユイ"
        case .rinshan:         return "リンシャンカイホウ"
        case .chankan:         return "チャンカン"
        case .chiitoitsu:      return "チートイツ"
        case .toitoi:          return "トイトイ"
        case .sanankou:        return "サンアンコー"
        case .sankantsu:       return "サンカンツ"
        case .sanshokuDoujun:  return "サンショクドウジュン"
        case .ittsuu:          return "イッキツウカン"
        case .chanta:          return "ホンチャンタ"
        case .honroutou:       return "ホンロウトウ"
        case .ryanpeikou:      return "リャンペーコー"
        case .junchan:         return "ジュンチャン"
        case .honitsu:         return "ホンイツ"
        case .chinitsu:        return "チンイツ"
        case .kokushi:         return "コクシムソウ"
        case .suuankou:        return "スーアンコー"
        case .daisangen:       return "ダイサンゲン"
        case .shousuushii:     return "ショウスーシー"
        case .daisuushii:      return "ダイスーシー"
        case .tsuuiisou:       return "ツーイーソー"
        case .chinroutou:      return "チンロウトウ"
        case .suukantsu:       return "スーカンツ"
        case .dora:            return "ドラ"
        case .uraDora:         return "ウラドラ"
        }
    }

    /// 成立条件（早見表に出す 1 行）。
    public var requirement: String {
        switch self {
        case .riichi:
            return "門前で聴牌したら1000点を供託して宣言。以後は手牌を変えられない"
        case .ippatsu:
            return "立直の宣言から1巡以内（誰にも鳴かれずに）和了する"
        case .menzenTsumo:
            return "門前のままツモ和了する"
        case .pinfu:
            return "門前で、4組すべて順子・雀頭が役牌でない・両面待ち"
        case .tanyao:
            return "1と9と字牌を1枚も使わない"
        case .yakuhaiDragon:
            return "白・發・中のどれかを3枚そろえる（鳴いても付く）"
        case .yakuhaiSeatWind:
            return "自分の風（東家なら東）を3枚そろえる（鳴いても付く）"
        case .yakuhaiRoundWind:
            return "場の風（東風戦は常に東）を3枚そろえる（鳴いても付く）"
        case .iipeikou:
            return "門前で、同じ順子を2組そろえる"
        case .haitei:
            return "山の最後の牌をツモって和了する"
        case .houtei:
            return "最後に捨てられた牌でロンする"
        case .rinshan:
            return "カンの直後に引いた牌（嶺上牌）で和了する"
        case .chankan:
            return "他家が加槓した牌でロンする"
        case .chiitoitsu:
            return "門前で、対子を7組そろえる（同じ牌4枚は2組に数えない）"
        case .toitoi:
            return "4組すべてを刻子（槓子）でそろえる"
        case .sanankou:
            return "鳴かずに作った刻子（槓子）を3組そろえる"
        case .sankantsu:
            return "カンを3回する"
        case .sanshokuDoujun:
            return "萬子・筒子・索子で同じ並びの順子をそろえる"
        case .ittsuu:
            return "同じ種類の数牌で123・456・789をそろえる"
        case .chanta:
            return "すべての組に1・9・字牌のどれかが入る（字牌を1枚以上使う）"
        case .honroutou:
            return "1・9・字牌だけで作る"
        case .ryanpeikou:
            return "門前で、同じ順子2組を2種類そろえる"
        case .junchan:
            return "すべての組に1か9が入る（字牌は使わない）"
        case .honitsu:
            return "1種類の数牌と字牌だけで作る"
        case .chinitsu:
            return "1種類の数牌だけで作る（字牌も使わない）"
        case .kokushi:
            return "1・9・字牌の13種を1枚ずつ集め、どれか1種をもう1枚"
        case .suuankou:
            return "鳴かずに作った刻子（槓子）を4組そろえる"
        case .daisangen:
            return "白・發・中をすべて3枚ずつそろえる"
        case .shousuushii:
            return "東南西北のうち3種を刻子、残り1種を雀頭にする"
        case .daisuushii:
            return "東南西北をすべて3枚ずつそろえる"
        case .tsuuiisou:
            return "字牌だけで作る"
        case .chinroutou:
            return "1と9だけで作る（字牌も使わない）"
        case .suukantsu:
            return "カンを4回する"
        case .dora:
            return "ドラ表示牌の次の牌1枚につき1飜。単独では和了できない"
        case .uraDora:
            return "立直して和了したときだけ、裏ドラ表示牌の次の牌1枚につき1飜"
        }
    }

    /// 門前のときの飜数（役満は 13）。
    public var closedHan: Int {
        switch self {
        case .riichi, .ippatsu, .menzenTsumo, .pinfu, .tanyao,
             .yakuhaiDragon, .yakuhaiSeatWind, .yakuhaiRoundWind, .iipeikou,
             .haitei, .houtei, .rinshan, .chankan:
            return 1
        case .chiitoitsu, .toitoi, .sanankou, .sankantsu, .honroutou:
            return 2
        case .sanshokuDoujun, .ittsuu, .chanta:
            return 2
        case .ryanpeikou, .junchan, .honitsu:
            return 3
        case .chinitsu:
            return 6
        case .kokushi, .suuankou, .daisangen, .shousuushii, .daisuushii,
             .tsuuiisou, .chinroutou, .suukantsu:
            return 13
        case .dora, .uraDora:
            // 枚数で決まるので固定値を持たない。表示は `hanText` が「1枚 1飜」と書く。
            return 1
        }
    }

    /// 鳴いたときの飜数。門前限定の役は nil。
    public var openHan: Int? {
        switch self {
        case .riichi, .ippatsu, .menzenTsumo, .pinfu, .iipeikou, .ryanpeikou, .chiitoitsu:
            return nil
        case .sanshokuDoujun, .ittsuu, .chanta:
            return closedHan - 1
        case .junchan, .honitsu:
            return closedHan - 1
        case .chinitsu:
            return 5
        default:
            return closedHan
        }
    }

    public var isYakuman: Bool { closedHan == 13 && !isDora }

    /// 役ではなく飜だけが増えるもの（早見表では別セクションに出す）。
    public var isDora: Bool { self == .dora || self == .uraDora }

    /// 門前限定か（鳴くと消える）。
    public var isConcealedOnly: Bool { openHan == nil }

    /// 状況で決まる飜数。
    public func han(isConcealed: Bool) -> Int {
        isConcealed ? closedHan : (openHan ?? closedHan)
    }

    /// 早見表の飜数欄の表記。
    public var hanText: String {
        if isDora { return "1枚 1飜" }
        if isYakuman { return "役満" }
        guard let open = openHan else { return "\(closedHan)飜（門前のみ）" }
        return open == closedHan ? "\(closedHan)飜" : "\(closedHan)飜（鳴き\(open)飜）"
    }

    /// 早見表に出す牌例。面子ごとに区切った並び。
    ///
    /// 立直・一発のように**牌の形では決まらない役**は空にする（無理に牌を並べると、
    /// その形でないと成立しないという誤解を生むため）。
    public var example: [[MahjongTile]] {
        switch self {
        case .riichi, .ippatsu, .menzenTsumo, .haitei, .houtei, .rinshan, .chankan,
             .dora, .uraDora:
            return []
        case .pinfu:
            return [[.characters(2), .characters(3), .characters(4)],
                    [.circles(3), .circles(4), .circles(5)],
                    [.bamboos(6), .bamboos(7), .bamboos(8)],
                    [.characters(7), .characters(8), .characters(9)],
                    [.circles(2), .circles(2)]]
        case .tanyao:
            return [[.characters(2), .characters(3), .characters(4)],
                    [.circles(5), .circles(6), .circles(7)],
                    [.bamboos(3), .bamboos(4), .bamboos(5)],
                    [.bamboos(6), .bamboos(7), .bamboos(8)],
                    [.circles(8), .circles(8)]]
        case .yakuhaiDragon:
            return [[.dragon(0), .dragon(0), .dragon(0)]]
        case .yakuhaiSeatWind, .yakuhaiRoundWind:
            return [[.wind(0), .wind(0), .wind(0)]]
        case .iipeikou:
            return [[.characters(2), .characters(3), .characters(4)],
                    [.characters(2), .characters(3), .characters(4)]]
        case .chiitoitsu:
            return [[.characters(1), .characters(1)], [.characters(4), .characters(4)],
                    [.circles(7), .circles(7)], [.circles(9), .circles(9)],
                    [.bamboos(3), .bamboos(3)], [.bamboos(6), .bamboos(6)],
                    [.wind(0), .wind(0)]]
        case .toitoi:
            return [[.characters(3), .characters(3), .characters(3)],
                    [.circles(7), .circles(7), .circles(7)],
                    [.bamboos(2), .bamboos(2), .bamboos(2)],
                    [.dragon(2), .dragon(2), .dragon(2)],
                    [.characters(5), .characters(5)]]
        case .sanankou:
            return [[.characters(3), .characters(3), .characters(3)],
                    [.circles(7), .circles(7), .circles(7)],
                    [.bamboos(2), .bamboos(2), .bamboos(2)]]
        case .sankantsu:
            return [[.characters(1), .characters(1), .characters(1), .characters(1)],
                    [.circles(5), .circles(5), .circles(5), .circles(5)],
                    [.bamboos(9), .bamboos(9), .bamboos(9), .bamboos(9)]]
        case .sanshokuDoujun:
            return [[.characters(3), .characters(4), .characters(5)],
                    [.circles(3), .circles(4), .circles(5)],
                    [.bamboos(3), .bamboos(4), .bamboos(5)]]
        case .ittsuu:
            return [[.characters(1), .characters(2), .characters(3)],
                    [.characters(4), .characters(5), .characters(6)],
                    [.characters(7), .characters(8), .characters(9)]]
        case .chanta:
            return [[.characters(1), .characters(2), .characters(3)],
                    [.circles(7), .circles(8), .circles(9)],
                    [.bamboos(9), .bamboos(9), .bamboos(9)],
                    [.wind(0), .wind(0), .wind(0)],
                    [.circles(1), .circles(1)]]
        case .honroutou:
            return [[.characters(1), .characters(1), .characters(1)],
                    [.circles(9), .circles(9), .circles(9)],
                    [.wind(0), .wind(0), .wind(0)],
                    [.dragon(2), .dragon(2), .dragon(2)],
                    [.bamboos(9), .bamboos(9)]]
        case .ryanpeikou:
            return [[.characters(2), .characters(3), .characters(4)],
                    [.characters(2), .characters(3), .characters(4)],
                    [.circles(6), .circles(7), .circles(8)],
                    [.circles(6), .circles(7), .circles(8)],
                    [.bamboos(5), .bamboos(5)]]
        case .junchan:
            return [[.characters(1), .characters(2), .characters(3)],
                    [.circles(7), .circles(8), .circles(9)],
                    [.bamboos(9), .bamboos(9), .bamboos(9)],
                    [.bamboos(1), .bamboos(2), .bamboos(3)],
                    [.characters(9), .characters(9)]]
        case .honitsu:
            return [[.characters(2), .characters(3), .characters(4)],
                    [.characters(6), .characters(7), .characters(8)],
                    [.characters(9), .characters(9), .characters(9)],
                    [.wind(0), .wind(0), .wind(0)],
                    [.dragon(0), .dragon(0)]]
        case .chinitsu:
            return [[.circles(1), .circles(2), .circles(3)],
                    [.circles(4), .circles(5), .circles(6)],
                    [.circles(7), .circles(8), .circles(9)],
                    [.circles(2), .circles(3), .circles(4)],
                    [.circles(5), .circles(5)]]
        case .kokushi:
            // 面子で作らない唯一の役。1・9・字牌の13種を並べ、最後の1枚（どれか1種の重なり）を
            // 別の組として置く。
            return [[.characters(1), .characters(9)],
                    [.circles(1), .circles(9)],
                    [.bamboos(1), .bamboos(9)],
                    [.wind(0), .wind(1), .wind(2), .wind(3)],
                    [.dragon(2), .dragon(1), .dragon(0)],
                    [.characters(1)]]
        case .suuankou:
            return [[.characters(3), .characters(3), .characters(3)],
                    [.circles(7), .circles(7), .circles(7)],
                    [.bamboos(2), .bamboos(2), .bamboos(2)],
                    [.wind(0), .wind(0), .wind(0)],
                    [.bamboos(5), .bamboos(5)]]
        case .daisangen:
            return [[.dragon(2), .dragon(2), .dragon(2)],
                    [.dragon(1), .dragon(1), .dragon(1)],
                    [.dragon(0), .dragon(0), .dragon(0)]]
        case .shousuushii:
            return [[.wind(0), .wind(0), .wind(0)],
                    [.wind(1), .wind(1), .wind(1)],
                    [.wind(2), .wind(2), .wind(2)],
                    [.wind(3), .wind(3)]]
        case .daisuushii:
            return [[.wind(0), .wind(0), .wind(0)],
                    [.wind(1), .wind(1), .wind(1)],
                    [.wind(2), .wind(2), .wind(2)],
                    [.wind(3), .wind(3), .wind(3)]]
        case .tsuuiisou:
            return [[.wind(0), .wind(0), .wind(0)],
                    [.wind(1), .wind(1), .wind(1)],
                    [.dragon(2), .dragon(2), .dragon(2)],
                    [.dragon(0), .dragon(0), .dragon(0)],
                    [.dragon(1), .dragon(1)]]
        case .chinroutou:
            return [[.characters(1), .characters(1), .characters(1)],
                    [.characters(9), .characters(9), .characters(9)],
                    [.circles(1), .circles(1), .circles(1)],
                    [.bamboos(9), .bamboos(9), .bamboos(9)],
                    [.bamboos(1), .bamboos(1)]]
        case .suukantsu:
            return [[.characters(1), .characters(1), .characters(1), .characters(1)],
                    [.circles(5), .circles(5), .circles(5), .circles(5)],
                    [.bamboos(9), .bamboos(9), .bamboos(9), .bamboos(9)],
                    [.bamboos(3), .bamboos(3), .bamboos(3), .bamboos(3)]]
        }
    }

    /// 早見表に並べる順（飜数の小さい順 → 役満 → ドラ）。
    public static let displayOrder: [MahjongYaku] = [
        // 1 飜
        .riichi, .ippatsu, .menzenTsumo, .pinfu, .tanyao,
        .yakuhaiDragon, .yakuhaiSeatWind, .yakuhaiRoundWind, .iipeikou,
        .haitei, .houtei, .rinshan, .chankan,
        // 2 飜
        .chiitoitsu, .toitoi, .sanankou, .sankantsu,
        .sanshokuDoujun, .ittsuu, .chanta, .honroutou,
        // 3 飜
        .ryanpeikou, .junchan, .honitsu,
        // 6 飜
        .chinitsu,
        // 役満
        .kokushi, .suuankou, .daisangen, .shousuushii, .daisuushii,
        .tsuuiisou, .chinroutou, .suukantsu,
        // ドラ
        .dora, .uraDora,
    ]

    /// 早見表のセクション見出しごとの区分け。`displayOrder` を並べ替えずにそのまま切る。
    public enum Section: String, CaseIterable, Sendable {
        case one = "1飜"
        case two = "2飜"
        case three = "3飜以上"
        case yakuman = "役満"
        case dora = "ドラ"
    }

    public var section: Section {
        if isDora { return .dora }
        if isYakuman { return .yakuman }
        switch closedHan {
        case 1: return .one
        case 2: return .two
        default: return .three
        }
    }

    public static func yaku(in section: Section) -> [MahjongYaku] {
        displayOrder.filter { $0.section == section }
    }
}
