import Testing
@testable import GameHanafuda

/// CPU の評価と判断。
///
/// **「この局面でこの札を選ぶ」だけで固定しない**（#462 の教訓）。選んだ札は評価の粗い射影で、
/// 内部の値が壊れても順位さえ変わらなければ同じ札が出る。評価値そのものを正確な値で
/// 突き合わせたうえで、手の選択はその帰結として確かめる。
@Suite("花札: CPUの評価と判断")
struct HanafudaAITests {

    // MARK: 評価値

    @Test("札の重みが定義どおり（光1.0・盃0.9・猪鹿蝶0.8・赤短青短0.7・タネ0.5・無地短冊0.4・カス0.15）")
    func cardWeights() {
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("松に鶴")) == 1.0)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("菊に盃")) == 0.9)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("萩に猪")) == 0.8)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("松に赤短")) == 0.7)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("菊に青短")) == 0.7)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("梅に鶯")) == 0.5)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("藤に短冊")) == 0.4)
        #expect(HanafudaAI.cardWeight(HanafudaCard.named("桐のカス")) == 0.15)
    }

    /// 役が立っていない局面でも評価が平らにならないこと、役が立ったら
    /// 札の重みより桁で大きく効くことの両方を、**正確な値**で押さえる。
    @Test("評価値は 役の文数×4 ＋ 札の重みの合計")
    func evaluateIsExact() {
        let kasu = HanafudaCard.anyKasu(3)
        #expect(HanafudaAI.evaluate(kasu, options: noSakeOptions)
                == 0.15 * 3, "役が無いときは札の重みだけ")

        // 光札 3 枚 = 三光 5 文。5 * 4 + 1.0 * 3 = 23.0
        let sanko = Array(HanafudaCard.fullDeck.filter { $0.kind == .hikari && !$0.isRainMan }.prefix(3))
        #expect(HanafudaAI.evaluate(sanko, options: noSakeOptions) == 23.0)

        #expect(HanafudaAI.evaluate([], options: noSakeOptions) == 0)
    }

    @Test("酒の役をオフにすると同じ取り札でも評価が下がる")
    func sakeOptionChangesEvaluation() {
        let pair = [HanafudaCard(id: HanafudaCard.moonID), HanafudaCard(id: HanafudaCard.sakeCupID)]
        // 月見酒 5 文 × 4 ＋ 光1.0 ＋ 盃0.9 = 21.9
        #expect(HanafudaAI.evaluate(pair, options: defaultOptions) == 21.9)
        // 役なし → 1.9
        #expect(HanafudaAI.evaluate(pair, options: noSakeOptions) == 1.9)
    }

    // MARK: 手の選択

    @Test("普通は取れる札のうち値打ちの高いほうを取る")
    func normalTakesTheBetterCard() {
        // 場に「松に鶴（光）」と「菊のカス」。手札に松のカスと菊のカスがあれば、松を取る。
        let field = [HanafudaCard.named("松に鶴"), HanafudaCard.named("菊のカス")]
        let hand = [HanafudaCard.kasu(month: 1)[0], HanafudaCard.kasu(month: 9)[0]]
        var rng = HanafudaRandom(seed: 1)
        let move = HanafudaAI.chooseMove(
            hand: hand, field: field, captured: [], opponentCaptured: [],
            options: noSakeOptions, difficulty: .normal, using: &rng
        )
        #expect(move?.card.month == 1)
    }

    @Test("2枚の候補からは値打ちの高いほうを合わせ先に選ぶ")
    func normalPicksTheBetterTarget() {
        let good = HanafudaCard.named("松に赤短")
        let bad = HanafudaCard.kasu(month: 1)[0]
        let field = [bad, good]
        let hand = [HanafudaCard.named("松に鶴")]
        var rng = HanafudaRandom(seed: 1)
        let move = HanafudaAI.chooseMove(
            hand: hand, field: field, captured: [], opponentCaptured: [],
            options: noSakeOptions, difficulty: .normal, using: &rng
        )
        #expect(move?.target == good)
    }

    /// 「強」だけが持つ性質。相手の赤短があと 1 枚のとき、その 1 枚を場に置き去りにしない。
    @Test("強は相手の役のあと1枚を優先して取り、普通は取らない")
    func hardBlocksTheOpponent() {
        // 相手は赤短を 2 枚持っている。場に残る「桜に赤短」を取られると赤短が完成する。
        let opponentCaptured = [HanafudaCard.named("松に赤短"), HanafudaCard.named("梅に赤短")]
        let threat = HanafudaCard.named("桜に赤短")
        // もう一方の選択肢は、**自分にとってはこちらのほうが得**な光札「芒に月」。
        // 自分の得だけを見る「普通」は必ず光を取り、相手の伸びも見る「強」だけが赤短を止める。
        let field = [threat, HanafudaCard.named("芒に月")]
        let hand = [HanafudaCard.kasu(month: 3)[0], HanafudaCard.kasu(month: 8)[0]]

        var rngNormal = HanafudaRandom(seed: 7)
        let normal = HanafudaAI.chooseMove(
            hand: hand, field: field, captured: [], opponentCaptured: opponentCaptured,
            options: noSakeOptions, difficulty: .normal, using: &rngNormal
        )
        var rngHard = HanafudaRandom(seed: 7)
        let hard = HanafudaAI.chooseMove(
            hand: hand, field: field, captured: [], opponentCaptured: opponentCaptured,
            options: noSakeOptions, difficulty: .hard, using: &rngHard
        )
        #expect(hard?.card.month == 3, "強は脅威の札（桜に赤短）を取りにいく")
        #expect(normal?.card.month != 3, "普通は相手の役を見ないので、自分の得だけで選ぶ")
    }

    @Test("弱でも取れる札があるときは取りにいく")
    func easyStillCaptures() {
        let field = [HanafudaCard.named("松に鶴")]
        let hand = [HanafudaCard.kasu(month: 1)[0], HanafudaCard.kasu(month: 9)[0]]
        for seed in UInt64(0)..<10 {
            var rng = HanafudaRandom(seed: seed)
            let move = HanafudaAI.chooseMove(
                hand: hand, field: field, captured: [], opponentCaptured: [],
                options: noSakeOptions, difficulty: .easy, using: &rng
            )
            #expect(move?.card.month == 1, "seed=\(seed)")
        }
    }

    @Test("手札が空なら手を返さない")
    func emptyHandHasNoMove() {
        var rng = HanafudaRandom(seed: 1)
        #expect(HanafudaAI.chooseMove(
            hand: [], field: [], captured: [], opponentCaptured: [],
            options: noSakeOptions, difficulty: .normal, using: &rng
        ) == nil)
    }

    @Test("返す手は必ず手札の中にあり、合わせ先は場の中にある")
    func movesAreAlwaysLegal() {
        for seed in UInt64(0)..<30 {
            var rng = HanafudaRandom(seed: seed)
            let deal = HanafudaRules.deal(using: &rng)
            for difficulty in HanafudaDifficulty.allCases {
                var moveRNG = HanafudaRandom(seed: seed)
                guard let move = HanafudaAI.chooseMove(
                    hand: deal.dealerHand, field: deal.field, captured: [], opponentCaptured: [],
                    options: defaultOptions, difficulty: difficulty, using: &moveRNG
                ) else {
                    Issue.record("seed=\(seed) \(difficulty) で手が返らなかった")
                    continue
                }
                #expect(deal.dealerHand.contains(move.card))
                if let target = move.target {
                    #expect(deal.field.contains(target))
                    #expect(target.month == move.card.month)
                }
            }
        }
    }

    // MARK: こいこいの判断

    @Test("弱は続けず、必ずあがる")
    func easyNeverContinues() {
        #expect(!HanafudaAI.shouldKoiKoi(
            myPoints: 1, opponentPoints: 0, handCount: 6, deckCount: 10, difficulty: .easy
        ))
    }

    @Test("普通は点が低くて札が残っていれば続ける")
    func normalContinuesWhenCheap() {
        #expect(HanafudaAI.shouldKoiKoi(
            myPoints: 1, opponentPoints: 0, handCount: 6, deckCount: 10, difficulty: .normal
        ))
        // 7 文に乗ったら確定させる（そこから先は 2 倍が付いている）。
        #expect(!HanafudaAI.shouldKoiKoi(
            myPoints: 7, opponentPoints: 0, handCount: 6, deckCount: 10, difficulty: .normal
        ))
        // 手札が残り 1 枚なら伸ばせないので降りる。
        #expect(!HanafudaAI.shouldKoiKoi(
            myPoints: 1, opponentPoints: 0, handCount: 1, deckCount: 10, difficulty: .normal
        ))
    }

    @Test("強は相手に役が立っていたら伸ばさない")
    func hardBacksOffAgainstAThreat() {
        #expect(HanafudaAI.shouldKoiKoi(
            myPoints: 1, opponentPoints: 0, handCount: 6, deckCount: 10, difficulty: .hard
        ))
        #expect(!HanafudaAI.shouldKoiKoi(
            myPoints: 1, opponentPoints: 1, handCount: 6, deckCount: 10, difficulty: .hard
        ))
    }

    @Test("宣言できない局面では難易度によらず false")
    func neverContinuesWhenItCannot() {
        for difficulty in HanafudaDifficulty.allCases {
            #expect(!HanafudaAI.shouldKoiKoi(
                myPoints: 1, opponentPoints: 0, handCount: 0, deckCount: 10, difficulty: difficulty
            ))
            #expect(!HanafudaAI.shouldKoiKoi(
                myPoints: 1, opponentPoints: 0, handCount: 5, deckCount: 0, difficulty: difficulty
            ))
        }
    }
}
