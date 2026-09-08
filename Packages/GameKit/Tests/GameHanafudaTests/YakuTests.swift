import Testing
@testable import GameHanafuda

/// 役の成立判定と得点。`docs/hanafuda-koikoi-rules.md` の照合表と 1 対 1 で対応させる。
///
/// **すべての役について「成立する最小の組」と「1 枚欠けた組」の両方を書く**。
/// 成立側だけだと、判定を「常に true」に壊しても緑のまま通る。
@Suite("花札: 役の判定と得点")
struct HanafudaYakuTests {

    private func points(_ cards: [HanafudaCard], _ options: HanafudaOptions = noSakeOptions) -> Int {
        HanafudaScoring.points(for: cards, options: options)
    }

    private func hits(_ cards: [HanafudaCard], _ options: HanafudaOptions = noSakeOptions) -> Set<HanafudaYaku> {
        Set(HanafudaScoring.yaku(for: cards, options: options).map(\.yaku))
    }

    private var allHikari: [HanafudaCard] {
        HanafudaCard.fullDeck.filter { $0.kind == .hikari }
    }

    // MARK: 光札

    @Test("五光は10文。光札が5枚そろったときだけ")
    func goko() {
        #expect(points(allHikari) == 10)
        #expect(hits(allHikari) == [.goko])
        // 1 枚欠けたら五光にはならない。
        #expect(hits(Array(allHikari.dropLast())) != [.goko])
    }

    @Test("四光は8文。柳を含むと雨四光で7文")
    func shikoAndAmeShiko() {
        let withoutRain = allHikari.filter { !$0.isRainMan }        // 4 枚（松桜芒桐）
        #expect(points(withoutRain) == 8)
        #expect(hits(withoutRain) == [.shiko])

        let withRain = Array(allHikari.filter { !$0.isRainMan }.prefix(3)) + [
            HanafudaCard(id: HanafudaCard.rainManID),
        ]
        #expect(withRain.count == 4)
        #expect(points(withRain) == 7)
        #expect(hits(withRain) == [.ameShiko])
    }

    @Test("三光は5文。柳を含む3枚は役にならない")
    func sanko() {
        let bright3 = Array(allHikari.filter { !$0.isRainMan }.prefix(3))
        #expect(points(bright3) == 5)
        #expect(hits(bright3) == [.sanko])

        // 柳 + 光2枚は「柳を除くと2枚」なので三光にならない。
        let withRain = Array(allHikari.filter { !$0.isRainMan }.prefix(2)) + [
            HanafudaCard(id: HanafudaCard.rainManID),
        ]
        #expect(points(withRain) == 0)
        #expect(hits(withRain).isEmpty)
    }

    @Test("光札の役は互いに排他で、1つしか立たない")
    func hikariYakuAreExclusive() {
        for count in 3...5 {
            let cards = Array(allHikari.prefix(count))
            let established = HanafudaScoring.yaku(for: cards, options: noSakeOptions)
                .filter { [.goko, .shiko, .ameShiko, .sanko].contains($0.yaku) }
            #expect(established.count <= 1, "光札\(count)枚で \(established.count) 個の役が立った")
        }
    }

    // MARK: 猪鹿蝶・短冊

    @Test("猪鹿蝶は3枚そろって5文。1枚欠けると0文")
    func inoshikacho() {
        let three = [HanafudaCard.boarID, HanafudaCard.deerID, HanafudaCard.butterflyID]
            .map(HanafudaCard.init(id:))
        #expect(points(three) == 5)
        #expect(hits(three) == [.inoshikacho])
        #expect(hits(Array(three.dropLast())).isEmpty)
    }

    @Test("赤短は松梅桜の3枚で5文。無地の赤短冊を混ぜても成立しない")
    func akatan() {
        let red = HanafudaCard.fullDeck.filter { $0.ribbon == .redPoem }
        #expect(red.count == 3)
        #expect(points(red) == 5)
        #expect(hits(red) == [.akatan])

        let mixed = Array(red.prefix(2)) + [HanafudaCard.named("藤に短冊")]
        #expect(hits(mixed).isEmpty)
    }

    @Test("青短は牡丹菊紅葉の3枚で5文")
    func aotan() {
        let blue = HanafudaCard.fullDeck.filter { $0.ribbon == .blue }
        #expect(blue.count == 3)
        #expect(points(blue) == 5)
        #expect(hits(blue) == [.aotan])
        #expect(hits(Array(blue.dropLast())).isEmpty)
    }

    /// 赤短・青短の 6 枚は「タン」の 5 枚も同時に満たす。標準ルールでは**重ねて数える**。
    @Test("赤短と青短はタンにも数える（重複して成立する）")
    func ribbonYakuStackWithTan() {
        let all6 = HanafudaCard.fullDeck.filter { $0.ribbon == .redPoem || $0.ribbon == .blue }
        #expect(all6.count == 6)
        // 赤短5 + 青短5 + タン（6枚 = 1 + 1）= 12
        #expect(hits(all6) == [.akatan, .aotan, .tan])
        #expect(points(all6) == 12)
    }

    // MARK: 枚数で伸びる役

    @Test("タネは5枚で1文、1枚増えるごとに+1文")
    func taneScales() {
        // 盃（酒の役）と鹿（猪鹿蝶）を外して、**タネの枚数だけ**が効く形にする。
        // 猪と蝶は残るが、鹿が欠けているので猪鹿蝶は立たない。
        let tane = HanafudaCard.anyTane(9, excluding: [HanafudaCard.sakeCupID, HanafudaCard.deerID])
        #expect(tane.count == 7)
        #expect(points(Array(tane.prefix(4))) == 0)
        #expect(points(Array(tane.prefix(5))) == 1)
        #expect(points(Array(tane.prefix(6))) == 2)
        #expect(points(tane) == 3)
    }

    /// 猪鹿蝶の 3 枚はいずれもタネ札。**猪鹿蝶とタネは重ねて数える**（赤短とタンと同じ）。
    /// ここを排他にすると、実戦でいちばん出る形の点が過少になる。
    @Test("猪鹿蝶はタネにも数える（重複して成立する）")
    func inoshikachoStacksWithTane() {
        let trio = [HanafudaCard.boarID, HanafudaCard.deerID, HanafudaCard.butterflyID]
            .map(HanafudaCard.init(id:))
        #expect(trio.allSatisfy { $0.kind == .tane })
        // 猪鹿蝶の 3 枚 + タネ 2 枚 = タネ 5 枚。猪鹿蝶 5 + タネ 1 = 6 文。
        let others = HanafudaCard.anyTane(
            2, excluding: Set(trio.map(\.id)).union([HanafudaCard.sakeCupID])
        )
        #expect(others.count == 2)
        #expect(hits(trio + others) == [.inoshikacho, .tane])
        #expect(points(trio + others) == 6)
    }

    @Test("タンは5枚で1文、1枚増えるごとに+1文")
    func tanScales() {
        // 赤短・青短が同時に立たないよう、無地4枚 + 赤短2枚で組む。
        let plain = HanafudaCard.fullDeck.filter { $0.ribbon == .plainRed }
        let red2 = Array(HanafudaCard.fullDeck.filter { $0.ribbon == .redPoem }.prefix(2))
        let five = Array(plain.prefix(4)) + Array(red2.prefix(1))
        #expect(points(Array(five.prefix(4))) == 0)
        #expect(points(five) == 1)
        #expect(points(plain + red2) == 2)
    }

    @Test("カスは10枚で1文、1枚増えるごとに+1文")
    func kasuScales() {
        let kasu = HanafudaCard.anyKasu(12)
        #expect(points(Array(kasu.prefix(9))) == 0)
        #expect(points(Array(kasu.prefix(10))) == 1)
        #expect(points(Array(kasu.prefix(11))) == 2)
        #expect(points(kasu) == 3)
    }

    // MARK: 酒の役

    @Test("月見酒は芒に月＋菊に盃で5文。設定オフなら数えない")
    func tsukimizake() {
        let pair = [HanafudaCard(id: HanafudaCard.moonID), HanafudaCard(id: HanafudaCard.sakeCupID)]
        #expect(hits(pair, defaultOptions) == [.tsukimizake])
        #expect(points(pair, defaultOptions) == 5)
        // オフにすると 0 文（盃はタネ 1 枚として残るだけ）。
        #expect(points(pair, noSakeOptions) == 0)
    }

    @Test("花見酒は桜に幕＋菊に盃で5文。設定オフなら数えない")
    func hanamizake() {
        let pair = [HanafudaCard(id: HanafudaCard.curtainID), HanafudaCard(id: HanafudaCard.sakeCupID)]
        #expect(hits(pair, defaultOptions) == [.hanamizake])
        #expect(points(pair, defaultOptions) == 5)
        #expect(points(pair, noSakeOptions) == 0)
    }

    @Test("盃だけでは酒の役にならない")
    func sakeCupAloneIsNothing() {
        let alone = [HanafudaCard(id: HanafudaCard.sakeCupID)]
        #expect(hits(alone, defaultOptions).isEmpty)
    }

    @Test("月と幕と盃が3枚そろうと月見酒と花見酒が両方立つ")
    func bothSakeYaku() {
        let three = [HanafudaCard.moonID, HanafudaCard.curtainID, HanafudaCard.sakeCupID]
            .map(HanafudaCard.init(id:))
        #expect(hits(three, defaultOptions) == [.tsukimizake, .hanamizake])
        #expect(points(three, defaultOptions) == 10)
    }

    // MARK: 倍率

    @Test("6文はそのまま・7文で2倍")
    func sevenMonDoubles() {
        #expect(HanafudaScoring.finalScore(base: 6, opponentDeclaredKoiKoi: false) == 6)
        #expect(HanafudaScoring.finalScore(base: 7, opponentDeclaredKoiKoi: false) == 14)
        #expect(HanafudaScoring.finalScore(base: 10, opponentDeclaredKoiKoi: false) == 20)
    }

    @Test("相手のこいこいのあとにあがると2倍。7文以上と重なると4倍")
    func koiKoiReturnDoubles() {
        #expect(HanafudaScoring.finalScore(base: 3, opponentDeclaredKoiKoi: true) == 6)
        #expect(HanafudaScoring.finalScore(base: 8, opponentDeclaredKoiKoi: true) == 32)
    }

    @Test("0文には倍率が掛からない")
    func zeroStaysZero() {
        #expect(HanafudaScoring.finalScore(base: 0, opponentDeclaredKoiKoi: true) == 0)
    }

    @Test("倍率の内訳が表示用に返る")
    func multiplierReasons() {
        #expect(HanafudaScoring.multiplierReasons(base: 5, opponentDeclaredKoiKoi: false).isEmpty)
        #expect(HanafudaScoring.multiplierReasons(base: 7, opponentDeclaredKoiKoi: false)
                == ["7文以上で2倍"])
        #expect(HanafudaScoring.multiplierReasons(base: 7, opponentDeclaredKoiKoi: true)
                == ["7文以上で2倍", "こいこい返しで2倍"])
    }

    // MARK: 照合表

    /// `docs/hanafuda-koikoi-rules.md` の「役と文数」の表をそのまま持ってきたもの。
    /// 表を直したらここも直る（＝表とコードが同時にしか動かせない）。
    @Test("役の基本文数が照合表と一致する")
    func basePointsMatchTheReferenceTable() {
        let table: [(HanafudaYaku, Int)] = [
            (.goko, 10), (.shiko, 8), (.ameShiko, 7), (.sanko, 5),
            (.inoshikacho, 5), (.akatan, 5), (.aotan, 5),
            (.tsukimizake, 5), (.hanamizake, 5),
            (.tane, 1), (.tan, 1), (.kasu, 1),
        ]
        for (yaku, expected) in table {
            #expect(yaku.basePoints == expected, "\(yaku.name) の文数が違う")
        }
        // 表に載っていない役が増えていないこと。
        #expect(Set(table.map(\.0)) == Set(HanafudaYaku.allCases))
        #expect(HanafudaYaku.displayOrder.count == HanafudaYaku.allCases.count)
    }

    /// 実戦で出る「役が重なる」局面。手作業で足した値と突き合わせる。
    @Test("重なった役の合計が正しい（五光＋タネ＋カス）")
    func combinedYakuTotals() {
        var cards = allHikari                                   // 五光 10
        cards += HanafudaCard.anyTane(5, excluding: [HanafudaCard.sakeCupID])  // タネ5 → 1
        cards += HanafudaCard.anyKasu(11)                       // カス11 → 2
        #expect(hits(cards) == [.goko, .tane, .kasu])
        #expect(points(cards) == 13)
        // 13 文は 7 文以上なので 2 倍。
        #expect(HanafudaScoring.finalScore(base: 13, opponentDeclaredKoiKoi: false) == 26)
    }
}
