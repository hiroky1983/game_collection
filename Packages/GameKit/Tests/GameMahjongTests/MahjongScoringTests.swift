import Testing
import Foundation
import MahjongTiles
@testable import GameMahjong

/// 期待値はすべて**実際の麻雀ルール**に照らした具体的な牌姿で書く（#106 の受け入れ条件）。
private func score(
    _ handText: String,
    win winText: String,
    tsumo: Bool = false,
    riichi: Bool = false,
    ippatsu: Bool = false,
    lastTile: Bool = false,
    seatWind: Int = 1,          // 既定は子（南家）。親の判定は個別に指定する。
    roundWind: Int = 0,
    dora: [String] = [],
    ura: [String] = []
) -> MahjongScore? {
    let context = MahjongWinContext(
        winningTile: MahjongNotation.tile(winText),
        isTsumo: tsumo,
        isRiichi: riichi,
        isIppatsu: ippatsu,
        isLastTile: lastTile,
        seatWind: seatWind,
        roundWind: roundWind,
        doraIndicators: dora.map(MahjongNotation.tile),
        uraIndicators: ura.map(MahjongNotation.tile)
    )
    return MahjongScoring.score(hand: MahjongNotation.hand(handText), context: context)
}

private func names(_ score: MahjongScore?) -> Set<String> {
    Set(score?.yaku.map(\.name) ?? [])
}

// MARK: - 役の判定

@Suite("役の判定")
struct MahjongYakuTests {

    @Test("役が 1 つも無ければ和了できない（nil を返す）")
    func noYakuCannotWin() {
        // 123m456m678m22p567s を 7m ロン（68m の嵌張待ち）。
        // 1m があるので断幺九にならず、嵌張なので平和にもならず、456m があるのでチャンタでもない。
        // 一気通貫（789m が無い）・三色・一盃口・役牌もすべて外れる正真正銘の役なし。
        let result = score("123m456m678m22p567s", win: "7m")
        #expect(result == nil, "役なしの手で点が付いてしまっている: \(names(result))")
    }

    @Test("平和・断幺九・ツモの複合")
    func pinfuTanyaoTsumo() {
        // 234m567m22p345p678s、6s ツモ（両面待ち）。雀頭は 2p で役牌ではない。
        let result = score("234m567m22p345p678s", win: "6s", tsumo: true)
        #expect(names(result).isSuperset(of: ["平和", "断幺九", "門前清自摸和"]))
        // 平和ツモは 20 符固定。
        #expect(result?.fu == 20)
        #expect(result?.han == 3)
    }

    @Test("平和は雀頭が役牌だと成立しない")
    func pinfuRejectsYakuhaiPair() {
        // 上と同じ形で雀頭を白（5z）にする。
        let result = score("234m567m55z345p678s", win: "6s", tsumo: true)
        #expect(names(result).contains("平和") == false)
    }

    @Test("平和は嵌張待ちだと成立しない")
    func pinfuRejectsClosedWait() {
        // 345p を 4p で完成させた（嵌張）。
        let result = score("234m567m22p345p678s", win: "4p", tsumo: true)
        #expect(names(result).contains("平和") == false)
    }

    @Test("役牌は 1 種につき 1 飜。白と中の 2 つなら 2 飜")
    func dragonTriplets() {
        // 123m456m789m555z777z ではなく、雀頭を作った形で 2 つの役牌を持つ。
        let result = score("123m456m11p555z777z", win: "1m")
        #expect(names(result).contains("役牌 字牌の白"))
        #expect(names(result).contains("役牌 字牌の中"))
    }

    @Test("自風と場風はそれぞれ 1 飜。東場の東家なら東の刻子で 2 飜（連風牌）")
    func seatAndRoundWind() {
        let result = score("123m456m11p789m111z", win: "1m", seatWind: 0, roundWind: 0)
        #expect(names(result).contains("役牌 自風"))
        #expect(names(result).contains("役牌 場風"))
    }

    @Test("自風でも場風でもない風牌は役にならない")
    func otherWindIsNotYaku() {
        // 南家（seatWind = 1）が西（3z）の刻子を持っていても役ではない。
        let result = score("123m456m11p789m333z", win: "1m", seatWind: 1, roundWind: 0)
        #expect(names(result).contains("役牌 自風") == false)
        #expect(names(result).contains("役牌 場風") == false)
    }

    @Test("一盃口は同じ順子 2 組で 1 飜")
    func iipeiko() {
        let result = score("112233m456p11s789p", win: "3m", riichi: true)
        #expect(names(result).contains("一盃口"))
    }

    @Test("二盃口は同じ順子 2 組 × 2 で 3 飜（一盃口とは重複しない）")
    func ryanpeiko() {
        let result = score("112233m445566p11s", win: "6p", riichi: true)
        #expect(names(result).contains("二盃口"))
        #expect(names(result).contains("一盃口") == false)
    }

    @Test("三色同順は 3 種の同じ並びで 2 飜")
    func sanshoku() {
        let result = score("123m123p123s456m11z", win: "3s", riichi: true)
        #expect(names(result).contains("三色同順"))
    }

    @Test("一気通貫は同じ種類の 123 456 789 で 2 飜")
    func ittsu() {
        let result = score("123456789m123p11z", win: "9m", riichi: true)
        #expect(names(result).contains("一気通貫"))
    }

    @Test("七対子は 2 飜・25 符")
    func sevenPairs() {
        let result = score("1133m5577p99s1122z", win: "2z", riichi: true)
        #expect(names(result).contains("七対子"))
        #expect(result?.fu == 25)
    }

    @Test("混一色は 1 種 + 字牌で 3 飜、清一色は字牌なしで 6 飜")
    func flushes() {
        let honitsu = score("123456789m111z11m", win: "9m", riichi: true)
        #expect(names(honitsu).contains("混一色"))
        let chinitsu = score("11122345678999m", win: "9m", riichi: true)
        #expect(names(chinitsu).contains("清一色"))
        #expect(names(chinitsu).contains("混一色") == false)
    }

    @Test("混全帯幺九は全ブロックが幺九を含み、字牌が混じるとき 2 飜")
    func chanta() {
        let result = score("123m789m123p111z99s", win: "3p", riichi: true)
        #expect(names(result).contains("混全帯幺九"))
    }

    @Test("純全帯幺九は字牌を含まないチャンタで 3 飜")
    func junchan() {
        let result = score("123m789m123p789s99m", win: "3p", riichi: true)
        #expect(names(result).contains("純全帯幺九"))
        #expect(names(result).contains("混全帯幺九") == false)
    }

    @Test("対々和は 4 刻子で 2 飜。ツモなら暗刻 4 つで四暗刻（役満）")
    func toitoiAndSuuankou() {
        // ロンで最後の刻子が完成した場合は明刻扱いになり、四暗刻にはならない。
        let ron = score("222m555m888p333s11z", win: "3s")
        #expect(names(ron).contains("対々和"))
        #expect(names(ron).contains("四暗刻") == false)
        #expect(names(ron).contains("三暗刻"))

        let tsumo = score("222m555m888p333s11z", win: "3s", tsumo: true)
        #expect(names(tsumo).contains("四暗刻"))
    }

    @Test("国士無双は役満")
    func thirteenOrphans() {
        let result = score("19m19p19s12345677z", win: "7z")
        #expect(names(result) == ["国士無双"])
        #expect(result?.limitName == "役満")
    }

    @Test("大三元は役満")
    func bigThreeDragons() {
        let result = score("555z666z777z123m11p", win: "3m")
        #expect(names(result).contains("大三元"))
    }

    @Test("字一色は役満")
    func allHonors() {
        let result = score("111z222z333z555z66z", win: "6z")
        #expect(names(result).contains("字一色"))
    }

    @Test("立直・一発・裏ドラは立直しているときだけ乗る")
    func riichiOnlyBonuses() {
        let withRiichi = score(
            "234m567m22p345p678s", win: "6s", tsumo: true, riichi: true, ippatsu: true, ura: ["1p"]
        )
        #expect(names(withRiichi).isSuperset(of: ["立直", "一発", "裏ドラ"]))
        // 枚数は名前ではなく飜数が持つ（"裏ドラ1 1飜" のような二重表記を避ける）。
        #expect(withRiichi?.yaku.first { $0.name == "裏ドラ" }?.han == 2)

        let without = score("234m567m22p345p678s", win: "6s", tsumo: true, ura: ["1p"])
        #expect(names(without).contains("裏ドラ") == false)
        #expect(names(without).contains("一発") == false)
    }

    @Test("ドラは役ではないので、ドラだけでは和了できない")
    func doraAloneCannotWin() {
        // 上の役なしの手にドラ（1p 表示 → 2p がドラ、2 枚持っている）を積んでも nil のまま。
        let result = score("123m456m678m22p567s", win: "7m", dora: ["1p"])
        #expect(result == nil)
    }

    @Test("海底摸月・河底撈魚は最後の 1 枚での和了に付く")
    func lastTileYaku() {
        let tsumo = score("234m567m22p345p678s", win: "6s", tsumo: true, lastTile: true)
        #expect(names(tsumo).contains("海底摸月"))
        let ron = score("234m567m22p345p678s", win: "6s", lastTile: true)
        #expect(names(ron).contains("河底撈魚"))
    }
}

// MARK: - 符と点数

@Suite("符計算と点数")
struct MahjongScoreValueTests {

    @Test("平和ロンは 30 符。立直 + 平和の 2 飜 30 符で子は 2000 点")
    func pinfuRon() {
        // 123m456m678m22p345s を 5s ロン（34s の両面待ち）。1m があるので断幺九は付かない。
        let result = score("123m456m678m22p345s", win: "5s", riichi: true)
        #expect(result?.fu == 30)
        #expect(result?.han == 2, "立直 + 平和だけであること: \(names(result))")
        #expect(result?.ronPayment == 2000)
    }

    @Test("30 符 3 飜の子ロンは 3900 点、親ロンは 5800 点")
    func standardRon() {
        // 立直 + 平和 + 断幺九 = 3 飜 30 符。
        let child = score("234m567m22p345p678s", win: "6s", riichi: true, seatWind: 1)
        #expect(child?.fu == 30 && child?.han == 3)
        #expect(child?.ronPayment == 3900)

        let dealer = score("234m567m22p345p678s", win: "6s", riichi: true, seatWind: 0, roundWind: 3)
        #expect(dealer?.fu == 30 && dealer?.han == 3)
        #expect(dealer?.ronPayment == 5800)
    }

    @Test("平和ツモ 20 符 3 飜の子は 700 / 1300（合計 2700 点）")
    func pinfuTsumoPayments() {
        // 立直 + 平和 + 門前清自摸和 + 断幺九 = 4 飜…にならないよう断幺九を外した形で確認する。
        let result = score("234m567m22p345p678s", win: "6s", tsumo: true)
        #expect(result?.fu == 20)
        #expect(result?.han == 3)          // 平和 + ツモ + 断幺九
        #expect(result?.tsumoFromNonDealer == 700)
        #expect(result?.tsumoFromDealer == 1300)
        #expect(result?.total == 2700)
    }

    @Test("親のツモは全員から同額（20 符 3 飜なら 1300 オール）")
    func dealerTsumo() {
        let result = score("234m567m22p345p678s", win: "6s", tsumo: true, seatWind: 0)
        #expect(result?.fu == 20 && result?.han == 3)
        #expect(result?.tsumoFromDealer == 0, "自分が親なので親からの受け取りは無い")
        #expect(result?.tsumoFromNonDealer == 1300)
        #expect(result?.total == 3900)
    }

    @Test("6 飜は跳満（子ロン 12000）で頭打ちになる")
    func haneman() {
        // 立直 + 一発 + 平和 + 断幺九 + ドラ 2（1p 表示 → 2p がドラ、雀頭の 2 枚）= 6 飜。
        let child = score(
            "234m567m22p345p678s", win: "6s", riichi: true, ippatsu: true, seatWind: 1, dora: ["1p"]
        )
        #expect(child?.han == 6)
        #expect(child?.limitName == "跳満")
        #expect(child?.ronPayment == 12000)
    }

    @Test("役満は子ロン 32000 / 親ロン 48000")
    func yakuman() {
        let child = score("19m19p19s12345677z", win: "7z", seatWind: 1)
        #expect(child?.ronPayment == 32000)
        let dealer = score("19m19p19s12345677z", win: "7z", seatWind: 0)
        #expect(dealer?.ronPayment == 48000)
    }

    @Test("符は 10 符単位に切り上げる（40 符 2 飜の子ロンは 2600 点）")
    func fuRoundsUp() {
        // 東場南家。345m678m123p999s + 東の雀頭を 3m ロン（45m の両面待ち）。
        // 20（副底）+ 10（門前ロン）+ 8（幺九牌の暗刻 999s）= 38 → 切り上げて 40 符。
        // 役は立直 + 一発の 2 飜（刻子があるので平和は付かず、9s・1p・東があるので断幺九も付かない）。
        let result = score("345m678m123p999s11z", win: "3m", riichi: true, ippatsu: true, seatWind: 1)
        #expect(result?.fu == 40)
        #expect(result?.han == 2, "立直 + 一発だけであること: \(names(result))")
        #expect(result?.ronPayment == 2600)
    }
}
