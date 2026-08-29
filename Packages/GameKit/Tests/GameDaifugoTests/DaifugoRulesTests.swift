import Testing
@testable import GameDaifugo

// MARK: - ヘルパー

/// テスト用のカード。id はランクとスートから決めるので同じ札は常に同じ id になる。
func card(_ rank: Int, _ suit: DaifugoSuit = .spades) -> DaifugoCard {
    DaifugoCard(id: rank * 10 + suit.rawValue, suit: suit, rank: rank)
}

func joker(_ index: Int = 0) -> DaifugoCard {
    DaifugoCard(id: 900 + index, suit: nil, rank: DaifugoRules.jokerRank)
}

// MARK: - 強さ

@Suite("カードの強弱")
struct DaifugoStrengthTests {

    @Test("通常時は 3 が最弱・2 が最強・ジョーカーが別格")
    func normalOrder() {
        let order = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1, 2]   // 3…K, A, 2
        let strengths = order.map { DaifugoRules.strength(rank: $0, isRevolution: false) }
        #expect(strengths == strengths.sorted(), "3 → 2 の順に強くなる")
        #expect(DaifugoRules.strength(rank: DaifugoRules.jokerRank, isRevolution: false) > strengths.last!)
    }

    @Test("革命中は強さが反転し、ジョーカーだけは最強のまま")
    func revolutionReverses() {
        let order = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 1, 2]
        let strengths = order.map { DaifugoRules.strength(rank: $0, isRevolution: true) }
        #expect(strengths == strengths.sorted(by: >), "2 → 3 の順に強くなる")
        #expect(
            DaifugoRules.strength(rank: DaifugoRules.jokerRank, isRevolution: true) > strengths.max()!,
            "革命中もジョーカーが最強"
        )
    }

    @Test("通常時は強い組だけ出せる")
    func validPlayNormal() {
        #expect(DaifugoRules.isValidPlay([card(5)], field: [card(4)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay([card(4)], field: [card(5)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay([card(5)], field: [card(5, .hearts)], isRevolution: false), "同じ強さは出せない")
        #expect(DaifugoRules.isValidPlay([card(2)], field: [card(1)], isRevolution: false), "2 は A より強い")
    }

    @Test("革命中は弱いはずの札で勝てる")
    func validPlayRevolution() {
        #expect(DaifugoRules.isValidPlay([card(3)], field: [card(2)], isRevolution: true))
        #expect(!DaifugoRules.isValidPlay([card(2)], field: [card(3)], isRevolution: true))
        #expect(DaifugoRules.isValidPlay([joker()], field: [card(3)], isRevolution: true), "ジョーカーは革命中も勝てる")
    }

    @Test("枚数が違う組は出せない")
    func countMustMatch() {
        #expect(!DaifugoRules.isValidPlay([card(5), card(5, .hearts)], field: [card(4)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay([card(5)], field: [card(4), card(4, .hearts)], isRevolution: false))
        #expect(DaifugoRules.isValidPlay([card(5), card(5, .hearts)],
                                         field: [card(4), card(4, .hearts)], isRevolution: false))
    }

    @Test("ランクが混ざった組は出せない（階段は v1 では扱わない）")
    func mixedRanksAreInvalid() {
        #expect(!DaifugoRules.isValidPlay([card(5), card(6)], field: [], isRevolution: false))
        #expect(DaifugoRules.playRank([card(5), card(6)]) == nil)
    }

    @Test("ジョーカーはワイルドとして他の札のランクになる")
    func jokerIsWild() {
        let pair = [card(13), joker()]
        #expect(DaifugoRules.playRank(pair) == 13, "K + ジョーカーは K のペア")
        #expect(DaifugoRules.isValidPlay(pair, field: [card(12), card(12, .hearts)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay(pair, field: [card(1), card(1, .hearts)], isRevolution: false))
        #expect(DaifugoRules.playRank([joker(0), joker(1)]) == DaifugoRules.jokerRank, "ジョーカーだけなら最強の組")
    }
}

// MARK: - 8切り・革命・反則上がり

@Suite("特殊ルールの判定")
struct DaifugoSpecialRuleTests {

    @Test("8 を含む組は場を流す")
    func eightClearsField() {
        #expect(DaifugoRules.clearsField([card(8)]))
        #expect(DaifugoRules.clearsField([card(8), card(8, .hearts)]))
        #expect(DaifugoRules.clearsField([card(8), joker()]), "ジョーカーと組んだ 8 でも流れる")
        #expect(!DaifugoRules.clearsField([card(9)]))
    }

    @Test("同ランク4枚以上で革命")
    func revolutionTrigger() {
        let four = [card(5), card(5, .hearts), card(5, .diamonds), card(5, .clubs)]
        #expect(DaifugoRules.triggersRevolution(four))
        #expect(DaifugoRules.triggersRevolution([card(5), card(5, .hearts), card(5, .diamonds), joker()]),
                "ジョーカーを混ぜた4枚でも革命")
        #expect(!DaifugoRules.triggersRevolution(Array(four.prefix(3))))
    }

    @Test("2・8・ジョーカーでの上がりは反則")
    func foulFinish() {
        #expect(DaifugoRules.isFoulFinish([card(2)]))
        #expect(DaifugoRules.isFoulFinish([card(8)]))
        #expect(DaifugoRules.isFoulFinish([joker()]))
        #expect(DaifugoRules.isFoulFinish([card(5), card(5, .hearts), card(5, .diamonds), joker()]),
                "組の中に1枚でも含まれていれば反則")
        #expect(!DaifugoRules.isFoulFinish([card(3)]))
        #expect(!DaifugoRules.isFoulFinish([card(13), card(13, .hearts)]))
    }
}

// MARK: - 順位と階級

@Suite("上がり順と階級")
struct DaifugoRankingTests {

    @Test("反則が無ければ上がった順がそのまま階級になる")
    func plainOrder() {
        let ranking = DaifugoRules.ranking(finishOrder: [2, 0, 3, 1], fouls: [])
        #expect(ranking == [2, 0, 3, 1])
        #expect(DaifugoRules.title(forPlace: 0) == "大富豪")
        #expect(DaifugoRules.title(forPlace: 1) == "富豪")
        #expect(DaifugoRules.title(forPlace: 2) == "貧民")
        #expect(DaifugoRules.title(forPlace: 3) == "大貧民")
    }

    @Test("反則上がりは1着でも最下位に落ちる")
    func foulDropsToLast() {
        let ranking = DaifugoRules.ranking(finishOrder: [0, 1, 2, 3], fouls: [0])
        #expect(ranking == [1, 2, 3, 0])
    }

    @Test("反則が複数なら、その中では上がった順を保つ")
    func multipleFouls() {
        let ranking = DaifugoRules.ranking(finishOrder: [0, 1, 2, 3], fouls: [0, 2])
        #expect(ranking == [1, 3, 0, 2])
    }

    @Test("投了は反則上がりよりさらに下（必ず最下位）")
    func resignDropsBelowFoul() {
        let ranking = DaifugoRules.ranking(finishOrder: [1, 2, 3, 0], fouls: [2], resigned: [0])
        #expect(ranking == [1, 3, 2, 0])
    }

    @Test("投了した人が反則も兼ねていても二重に数えない")
    func resignAndFoulOverlap() {
        let ranking = DaifugoRules.ranking(finishOrder: [1, 2, 3, 0], fouls: [0], resigned: [0])
        #expect(ranking == [1, 2, 3, 0])
    }
}

// MARK: - カード交換

@Suite("階級によるカード交換")
struct DaifugoExchangeTests {

    /// 大富豪=0 / 富豪=1 / 貧民=2 / 大貧民=3 の手札。
    private func hands() -> [[DaifugoCard]] {
        [
            [card(3), card(4), card(9), card(2)],                 // 大富豪
            [card(3, .hearts), card(7), card(13)],                // 富豪
            [card(5), card(6), card(1)],                          // 貧民
            [card(3, .diamonds), card(10), card(2, .hearts), joker()],  // 大貧民
        ]
    }

    @Test("大貧民は最強2枚を大富豪へ、大富豪は最弱2枚を大貧民へ渡す")
    func topAndBottomSwapTwo() {
        let (result, transfers) = DaifugoRules.applyExchange(hands: hands(), ranking: [0, 1, 2, 3])

        let toRich = transfers.first { $0.from == 3 && $0.to == 0 }
        #expect(toRich?.cards.count == 2)
        #expect(Set(toRich?.cards.map(\.rank) ?? []) == [DaifugoRules.jokerRank, 2], "大貧民はジョーカーと 2 を供出")

        let toPoor = transfers.first { $0.from == 0 && $0.to == 3 }
        #expect(toPoor?.cards.count == 2)
        #expect(Set(toPoor?.cards.map(\.rank) ?? []) == [3, 4], "大富豪は最弱の 3・4 を供出")

        #expect(result[0].contains(joker()), "渡された札が手札に入っている")
        #expect(!result[3].contains(joker()))
        #expect(result.map(\.count) == hands().map(\.count), "枚数は交換前後で変わらない")
    }

    @Test("富豪と貧民は1枚ずつ交換する")
    func middlePairSwapsOne() {
        let (result, transfers) = DaifugoRules.applyExchange(hands: hands(), ranking: [0, 1, 2, 3])

        let toSecond = transfers.first { $0.from == 2 && $0.to == 1 }
        #expect(toSecond?.cards.map(\.rank) == [1], "貧民は最強の A を供出")

        let toThird = transfers.first { $0.from == 1 && $0.to == 2 }
        #expect(toThird?.cards.map(\.rank) == [3], "富豪は最弱の 3 を供出")

        #expect(result[1].contains(card(1)))
        #expect(result[2].contains(card(3, .hearts)))
    }

    @Test("交換で札が消えたり増えたりしない")
    func conserved() {
        let before = hands()
        let (after, _) = DaifugoRules.applyExchange(hands: before, ranking: [2, 3, 0, 1])
        let beforeIDs = Set(before.flatMap { $0 }.map(\.id))
        let afterIDs = Set(after.flatMap { $0 }.map(\.id))
        #expect(beforeIDs == afterIDs)
    }
}

// MARK: - CPU（貪欲法）

@Suite("CPU の手選び")
struct DaifugoGreedyTests {

    @Test("出せる中で最も弱い手を選ぶ")
    func picksWeakestPlayable() {
        let hand = [card(3), card(9), card(13), card(2)]
        let play = DaifugoRules.greedyPlay(hand: hand, field: [card(7)], isRevolution: false)
        #expect(play?.map(\.rank) == [9], "7 に勝てる最弱は 9")
    }

    @Test("出せる手が無ければ nil（＝パス）")
    func passesWhenNothingBeatsField() {
        let hand = [card(3), card(4)]
        #expect(DaifugoRules.greedyPlay(hand: hand, field: [card(13)], isRevolution: false) == nil)
    }

    @Test("同じ強さならジョーカーを温存する")
    func avoidsWastingJoker() {
        let hand = [card(9), joker()]
        let play = DaifugoRules.greedyPlay(hand: hand, field: [card(7)], isRevolution: false)
        #expect(play?.contains(joker()) == false)
    }

    @Test("場が空なら必ず何か出す")
    func alwaysLeadsWhenFieldIsEmpty() {
        let hand = [card(2), joker()]
        #expect(DaifugoRules.greedyPlay(hand: hand, field: [], isRevolution: false) != nil)
    }

    @Test("他に手があるときは反則上がりを避ける")
    func avoidsFoulFinish() {
        // 残り2枚が 2 のペア。まとめて出すと反則上がりになるので、1枚だけ出して次に回す。
        let hand = [card(2), card(2, .hearts)]
        let play = DaifugoRules.greedyPlay(hand: hand, field: [], isRevolution: false)
        #expect(play?.count == 1)
    }

    @Test("避けようが無ければ反則上がりでも出す（手詰まりにしない）")
    func playsFoulWhenItIsTheOnlyMove() {
        let play = DaifugoRules.greedyPlay(hand: [card(2)], field: [], isRevolution: false)
        #expect(play?.map(\.rank) == [2])
    }

    @Test("革命中は反転した強さで選ぶ")
    func respectsRevolution() {
        let hand = [card(3), card(9), card(13)]
        let play = DaifugoRules.greedyPlay(hand: hand, field: [card(1)], isRevolution: true)
        #expect(play?.map(\.rank) == [13], "革命中に A に勝てる最弱は K")
    }
}

// MARK: - ヒント（#190）

@Suite("出せるカードのヒント")
struct DaifugoPlayableHintTests {

    private func ids(_ cards: [DaifugoCard]) -> Set<Int> { Set(cards.map(\.id)) }

    @Test("場が流れていれば手札すべてが出せる")
    func everythingPlayableOnEmptyField() {
        let hand = [card(3), card(8), card(2), joker()]
        let playable = DaifugoRules.playableCardIDs(hand: hand, field: [], isRevolution: false)
        #expect(playable == ids(hand))
    }

    @Test("1枚場では、場より強い札とジョーカーだけが出せる")
    func singleCardField() {
        let hand = [card(3), card(9), card(13), joker()]
        let playable = DaifugoRules.playableCardIDs(hand: hand, field: [card(9, .hearts)], isRevolution: false)
        #expect(playable == ids([card(13), joker()]), "同じ強さの 9 は出せない")
    }

    @Test("同ランク4枚から2枚だけ出す手も「出せる」と数える（legalPlays の列挙漏れを踏まない）")
    func countsAlternativePlaysWithinSameRank() {
        let hand = [card(9), card(9, .hearts), card(9, .diamonds), card(9, .clubs)]
        let playable = DaifugoRules.playableCardIDs(hand: hand, field: [card(5), card(5, .hearts)], isRevolution: false)
        #expect(playable == ids(hand), "2枚場に対し、4枚のどれを選んでもペアが作れる")
    }

    @Test("枚数が足りないランクは出せない。ジョーカーで埋まるなら出せる")
    func jokerFillsMissingCards() {
        let field = [card(5), card(5, .hearts)]
        // 9 が1枚だけ。ジョーカーが無ければペアを作れない。
        #expect(
            DaifugoRules.playableCardIDs(hand: [card(9), card(3)], field: field, isRevolution: false).isEmpty
        )
        // ジョーカーを足すと 9 + JOKER のペアが作れる。
        let withJoker = DaifugoRules.playableCardIDs(hand: [card(9), card(3), joker()], field: field, isRevolution: false)
        #expect(withJoker == ids([card(9), joker()]), "3 はどう組んでも 5 のペアに勝てない")
    }

    @Test("ジョーカーだけの場には何も出せない")
    func nothingBeatsJoker() {
        let hand = [card(2), joker(1)]
        #expect(DaifugoRules.playableCardIDs(hand: hand, field: [joker()], isRevolution: false).isEmpty)
    }

    @Test("革命中は弱い数字が出せる側になる")
    func revolutionFlipsPlayableSet() {
        let hand = [card(3), card(13), card(2)]
        let playable = DaifugoRules.playableCardIDs(hand: hand, field: [card(9)], isRevolution: true)
        #expect(playable == ids([card(3)]), "革命中に 9 より強いのは 3 だけ")
    }

    @Test("出せる札の集合は isValidPlay と矛盾しない（1枚場の総当たり）")
    func agreesWithIsValidPlay() {
        let hand = [card(3), card(7), card(7, .hearts), card(1), card(2), joker()]
        for field in [[card(5)], [card(7, .diamonds)], [card(1, .hearts)], [card(2, .hearts)]] {
            let playable = DaifugoRules.playableCardIDs(hand: hand, field: field, isRevolution: false)
            for c in hand {
                let canPlayAlone = DaifugoRules.isValidPlay([c], field: field, isRevolution: false)
                #expect(playable.contains(c.id) == canPlayAlone, "\(c.rankLabel) が場 \(field[0].rankLabel) と食い違う")
            }
        }
    }
}

@Suite("出せない理由の表示")
struct DaifugoRejectionReasonTests {

    @Test("未選択・出せる組では理由を出さない")
    func silentWhenPlayable() {
        #expect(DaifugoRules.rejectionReason([], field: [card(5)], isRevolution: false) == nil)
        #expect(DaifugoRules.rejectionReason([card(9)], field: [card(5)], isRevolution: false) == nil)
        #expect(DaifugoRules.rejectionReason([card(3)], field: [], isRevolution: false) == nil, "場が空なら何でも出せる")
    }

    @Test("数字が混ざっていればそう伝える")
    func mixedRanks() {
        let reason = DaifugoRules.rejectionReason([card(5), card(9)], field: [], isRevolution: false)
        #expect(reason == "数字がそろっていません（ジョーカーは他の数字の代わりに使えます）")
    }

    @Test("枚数違いは場の枚数と選択枚数を出す")
    func countMismatch() {
        let reason = DaifugoRules.rejectionReason(
            [card(9)], field: [card(5), card(5, .hearts)], isRevolution: false
        )
        #expect(reason == "場は2枚です。1枚では出せません")
    }

    @Test("強さ不足は場のランクを添えて伝える")
    func tooWeak() {
        let reason = DaifugoRules.rejectionReason([card(3)], field: [card(13)], isRevolution: false)
        #expect(reason == "場の K より強い数字が必要です")
    }

    @Test("革命中は「弱い数字が必要」と反転して伝える")
    func tooWeakDuringRevolution() {
        let reason = DaifugoRules.rejectionReason([card(13)], field: [card(5)], isRevolution: true)
        #expect(reason == "革命中です。場の 5 より弱い数字が必要です")
    }

    @Test("理由が出るのは isValidPlay が false のときだけ")
    func matchesIsValidPlay() {
        let field = [card(7), card(7, .hearts)]
        let candidates: [[DaifugoCard]] = [
            [card(9), card(9, .hearts)],
            [card(3), card(3, .hearts)],
            [card(9)],
            [card(9), card(3)],
            [card(9), joker()],
        ]
        for cards in candidates {
            let valid = DaifugoRules.isValidPlay(cards, field: field, isRevolution: false)
            let reason = DaifugoRules.rejectionReason(cards, field: field, isRevolution: false)
            #expect(valid == (reason == nil), "\(cards.map(\.rankLabel)) の可否と理由の有無が食い違う")
        }
    }
}
