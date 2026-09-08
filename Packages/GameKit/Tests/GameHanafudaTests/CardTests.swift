import Testing
@testable import GameHanafuda

/// 48 枚の構成そのものを固定する。ここが崩れると全ての役の判定が静かに狂う。
@Suite("花札: 48枚の構成")
struct HanafudaCardTests {

    @Test("48枚ちょうどで、番号が 0...47 に 1 つずつ対応する")
    func deckIsExactlyFortyEight() {
        let deck = HanafudaCard.fullDeck
        #expect(deck.count == 48)
        #expect(Set(deck.map(\.id)) == Set(0..<48))
    }

    @Test("各月が 4 枚ずつある")
    func everyMonthHasFourCards() {
        for month in 1...12 {
            let cards = HanafudaCard.fullDeck.filter { $0.month == month }
            #expect(cards.count == 4, "\(month)月が \(cards.count) 枚")
        }
    }

    /// 実物の花札の構成。役はすべてこの枚数を前提に文数が決まっているので、
    /// 1 枚でもずれると「タネ 5 枚で 1 文」のような役が成立しなくなる。
    @Test("光5・タネ9・短冊10・カス24")
    func kindCountsMatchTheRealDeck() {
        func count(_ kind: HanafudaKind) -> Int {
            HanafudaCard.fullDeck.filter { $0.kind == kind }.count
        }
        #expect(count(.hikari) == 5)
        #expect(count(.tane) == 9)
        #expect(count(.tanzaku) == 10)
        #expect(count(.kasu) == 24)
    }

    @Test("短冊は赤短3・青短3・無地4")
    func ribbonCounts() {
        func count(_ ribbon: HanafudaRibbon) -> Int {
            HanafudaCard.fullDeck.filter { $0.ribbon == ribbon }.count
        }
        #expect(count(.redPoem) == 3)
        #expect(count(.blue) == 3)
        #expect(count(.plainRed) == 4)
        // 短冊札にだけ色が付く。
        #expect(HanafudaCard.fullDeck.filter { $0.ribbon != nil }.count == 10)
        #expect(HanafudaCard.fullDeck.allSatisfy { ($0.ribbon != nil) == ($0.kind == .tanzaku) })
    }

    @Test("光札は 1・3・8・11・12月にあり、11月だけが雨")
    func hikariMonths() {
        let hikari = HanafudaCard.fullDeck.filter { $0.kind == .hikari }
        #expect(Set(hikari.map(\.month)) == [1, 3, 8, 11, 12])
        #expect(hikari.filter(\.isRainMan).map(\.month) == [11])
    }

    @Test("役の相方になる特定札の番号が名前と一致する")
    func namedCardsMatchIDs() {
        #expect(HanafudaCard(id: HanafudaCard.rainManID).name == "柳に小野道風")
        #expect(HanafudaCard(id: HanafudaCard.sakeCupID).name == "菊に盃")
        #expect(HanafudaCard(id: HanafudaCard.moonID).name == "芒に月")
        #expect(HanafudaCard(id: HanafudaCard.curtainID).name == "桜に幕")
        #expect(HanafudaCard(id: HanafudaCard.boarID).name == "萩に猪")
        #expect(HanafudaCard(id: HanafudaCard.deerID).name == "紅葉に鹿")
        #expect(HanafudaCard(id: HanafudaCard.butterflyID).name == "牡丹に蝶")
    }

    /// 盃はタネ札。酒の役をオフにしたときに「タネが 1 枚減る」といった副作用が出ないよう固定する。
    @Test("菊に盃はタネ札で、芒に雁もタネ札")
    func sakeCupIsTane() {
        #expect(HanafudaCard(id: HanafudaCard.sakeCupID).kind == .tane)
        #expect(HanafudaCard.named("芒に雁").kind == .tane)
    }

    @Test("範囲外の番号は生成できない")
    func validatingRejectsOutOfRange() {
        #expect(HanafudaCard(validating: -1) == nil)
        #expect(HanafudaCard(validating: 48) == nil)
        #expect(HanafudaCard(validating: 0)?.id == 0)
        #expect(HanafudaCard(validating: 47)?.id == 47)
    }

    @Test("並べ替えは 光 → タネ → 短冊 → カス の順")
    func sortOrderGroupsByKind() {
        let sorted = HanafudaCard.fullDeck.shuffled().sorted()
        let kinds = sorted.map(\.kind)
        #expect(kinds == kinds.sorted { $0.sortOrder < $1.sortOrder })
        #expect(kinds.first == .hikari)
        #expect(kinds.last == .kasu)
    }

    @Test("同じ月の 4 枚は同じ月名を返す")
    func monthNamesAreShared() {
        #expect(HanafudaCard.named("松に鶴").monthName == "松")
        #expect(HanafudaCard.named("桐に鳳凰").monthName == "桐")
        for month in 1...12 {
            let names = Set(HanafudaCard.fullDeck.filter { $0.month == month }.map(\.monthName))
            #expect(names.count == 1)
        }
    }
}
