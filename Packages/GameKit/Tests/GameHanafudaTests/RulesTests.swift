import Testing
@testable import GameHanafuda

@Suite("花札: 配札と場合わせ")
struct HanafudaRulesTests {

    // MARK: 配札

    @Test("手札8枚ずつ・場8枚・山24枚に分かれ、48枚が過不足なく行き渡る")
    func dealSplitsTheDeck() {
        for seed in UInt64(0)..<20 {
            var rng = HanafudaRandom(seed: seed)
            let deal = HanafudaRules.deal(using: &rng)
            #expect(deal.dealerHand.count == 8)
            #expect(deal.opponentHand.count == 8)
            #expect(deal.field.count == 8)
            #expect(deal.deck.count == 24)
            let all = deal.dealerHand + deal.opponentHand + deal.field + deal.deck
            #expect(Set(all.map(\.id)) == Set(0..<48), "seed=\(seed) で札の重複か欠けがある")
        }
    }

    @Test("同じ種から配ると1ビットも変わらない（再現性）")
    func dealIsDeterministicForASeed() {
        var a = HanafudaRandom(seed: 12345)
        var b = HanafudaRandom(seed: 12345)
        #expect(HanafudaRules.deal(using: &a) == HanafudaRules.deal(using: &b))
    }

    @Test("場に同月4枚が出る配りは配り直される")
    func dealAvoidsFourOfAMonthOnTheField() {
        for seed in UInt64(0)..<50 {
            var rng = HanafudaRandom(seed: seed)
            let deal = HanafudaRules.deal(using: &rng)
            #expect(!HanafudaRules.hasFourOfAMonth(deal.field), "seed=\(seed)")
        }
    }

    @Test("同月4枚の検出そのものが効いている")
    func detectsFourOfAMonth() {
        let fourPines = HanafudaCard.fullDeck.filter { $0.month == 1 }
        #expect(HanafudaRules.hasFourOfAMonth(fourPines))
        #expect(!HanafudaRules.hasFourOfAMonth(Array(fourPines.prefix(3))))
        #expect(!HanafudaRules.hasFourOfAMonth([]))
    }

    // MARK: 場合わせ

    private let pineHikari = HanafudaCard.named("松に鶴")

    @Test("同月が場に無ければ、その札は場に置かれる")
    func noMatchDiscardsToField() {
        let field = HanafudaCard.fullDeck.filter { $0.month == 5 }
        #expect(HanafudaRules.outcome(playing: pineHikari, field: field) == .discard)
        let result = HanafudaRules.resolve(playing: pineHikari, field: field)
        #expect(result.captured.isEmpty)
        #expect(result.field.count == field.count + 1)
        #expect(result.field.contains(pineHikari))
    }

    @Test("同月が1枚なら自動で2枚取る")
    func singleMatchCapturesTwo() {
        let target = HanafudaCard.named("松に赤短")
        let field = [target, HanafudaCard.named("菊に盃")]
        #expect(HanafudaRules.outcome(playing: pineHikari, field: field) == .capture(field: target))
        let result = HanafudaRules.resolve(playing: pineHikari, field: field)
        #expect(Set(result.captured.map(\.id)) == [pineHikari.id, target.id])
        #expect(result.field.map(\.id) == [HanafudaCard.named("菊に盃").id])
    }

    @Test("同月が2枚のときは選択待ちになり、選んだ札だけを取る")
    func twoMatchesRequireAChoice() {
        let candidates = HanafudaCard.kasu(month: 1, count: 2)
        let field = candidates + [HanafudaCard.named("菊に盃")]
        #expect(HanafudaRules.outcome(playing: pineHikari, field: field)
                == .mustChoose(candidates: candidates))
        #expect(!HanafudaRules.isAutomatic(HanafudaRules.outcome(playing: pineHikari, field: field)))

        let result = HanafudaRules.resolve(playing: pineHikari, field: field, chosen: candidates[1])
        #expect(Set(result.captured.map(\.id)) == [pineHikari.id, candidates[1].id])
        // 選ばなかったほうは場に残る。
        #expect(result.field.contains(candidates[0]))
    }

    /// 場に無い札を「選んだ」と渡されても、場の候補から外れた札を取ってしまわないこと。
    @Test("候補に無い札を渡されても候補の先頭に倒れる")
    func invalidChoiceFallsBackToACandidate() {
        let candidates = HanafudaCard.kasu(month: 1, count: 2)
        let field = candidates
        let result = HanafudaRules.resolve(
            playing: pineHikari, field: field, chosen: HanafudaCard.named("菊に盃")
        )
        #expect(result.captured.count == 2)
        #expect(result.captured.contains(candidates[0]))
    }

    @Test("同月が3枚あれば4枚まとめて取る")
    func threeMatchesCaptureAll() {
        let three = HanafudaCard.fullDeck.filter { $0.month == 1 && $0.id != pineHikari.id }
        #expect(three.count == 3)
        let field = three + [HanafudaCard.named("菊に盃")]
        #expect(HanafudaRules.outcome(playing: pineHikari, field: field) == .captureAll(field: three))
        let result = HanafudaRules.resolve(playing: pineHikari, field: field)
        #expect(result.captured.count == 4)
        #expect(result.field.map(\.id) == [HanafudaCard.named("菊に盃").id])
    }

    @Test("取っても捨てても場と取り札の合計枚数は保存される")
    func cardsAreNeverLost() {
        let field = HanafudaCard.kasu(month: 1, count: 2) + HanafudaCard.kasu(month: 5, count: 1)
        for card in [pineHikari, HanafudaCard.named("菖蒲に八橋"), HanafudaCard.named("桐に鳳凰")] {
            let result = HanafudaRules.resolve(playing: card, field: field)
            #expect(result.captured.count + result.field.count == field.count + 1,
                    "\(card.name) で枚数が合わない")
        }
    }

    // MARK: こいこいの可否

    @Test("手札か山札が尽きる手番ではこいこいを宣言できない")
    func cannotKoiKoiWhenOutOfCards() {
        #expect(HanafudaRules.canDeclareKoiKoi(handCountAfterTurn: 1, deckCount: 5))
        #expect(!HanafudaRules.canDeclareKoiKoi(handCountAfterTurn: 0, deckCount: 5))
        #expect(!HanafudaRules.canDeclareKoiKoi(handCountAfterTurn: 3, deckCount: 0))
    }

    @Test("こいこいのあとは宣言時より文数が増えないとあがれない")
    func cannotStopWithoutImproving() {
        #expect(HanafudaRules.canStop(currentPoints: 3, claimedPoints: 0))
        #expect(!HanafudaRules.canStop(currentPoints: 3, claimedPoints: 3))
        #expect(HanafudaRules.canStop(currentPoints: 4, claimedPoints: 3))
    }
}
