import Core
import Testing
@testable import GameHanafuda

@Suite("花札: 絵柄の定義")
struct HanafudaArtTests {

    /// 実物の花札で「主役」を持つのは光札5・タネ札9・柳の鬼札の 15 枚。
    /// 絵柄を足し引きするとここが動くので、枚数と月の対応をまとめて固定する。
    @Test("主役を持つのは15枚で、光札とタネ札と柳の鬼札")
    func motifsAreOnTheRightCards() {
        let withMotif = HanafudaCard.fullDeck.filter { HanafudaCardArt.motif(for: $0) != nil }
        #expect(withMotif.count == 15)
        for card in withMotif {
            #expect(card.kind == .hikari || card.kind == .tane || card.name == "柳に鬼札",
                    "\(card.name) に主役が付いている")
        }
        // 光札5枚とタネ札9枚には必ず主役が付く。
        for card in HanafudaCard.fullDeck where card.kind == .hikari || card.kind == .tane {
            #expect(HanafudaCardArt.motif(for: card) != nil, "\(card.name) に主役が無い")
        }
    }

    @Test("主役は15種すべてが1枚ずつに割り当てられている")
    func everyMotifIsUsedExactlyOnce() {
        let used = HanafudaCard.fullDeck.compactMap { HanafudaCardArt.motif(for: $0) }
        #expect(Set(used).count == used.count, "同じ主役が2枚に付いている")
        #expect(Set(used) == Set(HanafudaMotif.allCases), "使われていない主役がある")
    }

    @Test("役の要になる札に正しい主役が付く")
    func keyCardsHaveTheirMotif() {
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("松に鶴")) == .crane)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("桜に幕")) == .curtain)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("芒に月")) == .moon)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("菊に盃")) == .sakeCup)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("萩に猪")) == .boar)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("紅葉に鹿")) == .deer)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("牡丹に蝶")) == .butterfly)
        #expect(HanafudaCardArt.motif(for: HanafudaCard.named("柳に小野道風")) == .rainMan)
    }

    /// 同じ月の 4 枚が画面で見分けられることの定義。**見分けが付かないのはカス同士だけ**で、
    /// 役に効く札（光・タネ・短冊）は必ず固有の手掛かりを持つ。
    @Test("同じ月で見分けが付かないのはカス札同士だけ")
    func cardsInAMonthAreDistinguishable() {
        for month in 1...12 {
            let cards = HanafudaCard.fullDeck.filter { $0.month == month }
            var seen: [String: [HanafudaCard]] = [:]
            for card in cards {
                seen[HanafudaCardArt.distinguishingKey(for: card), default: []].append(card)
            }
            for (key, group) in seen where group.count > 1 {
                #expect(key == "kasu",
                        "\(month)月に見分けの付かない札が\(group.count)枚ある: \(group.map(\.name))")
            }
        }
    }

    @Test("12か月の主色がすべて違う")
    func monthColorsAreDistinct() {
        let hexes = (1...12).map { HanafudaCardArt.monthHex($0) }
        #expect(Set(hexes).count == 12)
    }

    @Test("短冊の色は赤系と青系に分かれ、赤短と無地は同じ赤を使う")
    func ribbonColors() {
        #expect(HanafudaCardArt.ribbonColor(.redPoem) == HanafudaCardArt.ribbonColor(.plainRed))
        #expect(HanafudaCardArt.ribbonColor(.blue) != HanafudaCardArt.ribbonColor(.redPoem))
    }

    @Test("札の縦横比は実物と同じ 1.5:1")
    func aspectRatio() {
        #expect(HanafudaCardArt.aspectRatio == 1.5)
    }
}

@Suite("花札: 読み上げ文")
struct HanafudaSpeechTests {

    /// 合わせは月でしか起きないので、**読み上げは必ず月から始める**。
    @Test("札の読み上げは月・札名・種別の順")
    func cardLabelStartsWithTheMonth() {
        #expect(HanafudaSpeech.label(for: HanafudaCard.named("松に鶴")) == "1月 松に鶴 光")
        #expect(HanafudaSpeech.label(for: HanafudaCard.named("柳に鬼札")) == "11月 柳に鬼札 カス")
    }

    @Test("手札は合う場札があるかまで読む")
    func handLabelMentionsMatches() {
        let card = HanafudaCard.named("松に鶴")
        #expect(HanafudaSpeech.handLabel(for: card, matches: []).hasSuffix("合う場札なし"))
        #expect(HanafudaSpeech.handLabel(for: card, matches: HanafudaCard.kasu(month: 1, count: 2))
            .hasSuffix("場の2枚と合う"))
    }

    @Test("取り札は種別ごとの枚数で要約する")
    func capturedSummaryCountsByKind() {
        #expect(HanafudaSpeech.capturedSummary([]) == "取り札なし")
        let cards = [HanafudaCard.named("松に鶴")] + HanafudaCard.anyKasu(2)
        #expect(HanafudaSpeech.capturedSummary(cards) == "光1枚、カス2枚")
    }

    @Test("役の読み上げは名前・文数・合計を含む")
    func yakuSummary() {
        #expect(HanafudaSpeech.yakuSummary([]) == "役なし")
        let hits = [
            HanafudaYakuHit(yaku: .sanko, points: 5),
            HanafudaYakuHit(yaku: .kasu, points: 2),
        ]
        #expect(HanafudaSpeech.yakuSummary(hits) == "三光5文、カス2文。合計7文")
    }

    @Test("流局とあがりで読み上げが変わる")
    func roundResultSummary() {
        #expect(HanafudaSpeech.roundResultSummary(.drawn).hasPrefix("流局"))
        let win = HanafudaRoundResult(
            winner: .human, hits: [HanafudaYakuHit(yaku: .sanko, points: 5)],
            basePoints: 5, score: 5, reasons: []
        )
        #expect(HanafudaSpeech.roundResultSummary(win).contains("あなたのあがり"))
        #expect(HanafudaSpeech.roundResultSummary(win).contains("獲得5文"))
    }
}

@Suite("花札こいこいのモジュール登録")
struct HanafudaModuleTests {

    /// `HanafudaModule.id` は LP 照合スクリプトの都合で**文字列リテラル**で書いてあり、
    /// `HanafudaModel.gameID` とは別々に書かれている。食い違うと
    /// 「記録・解析・中断データが別のキーに書かれる」という静かな故障になるので、ここで縛る。
    @Test("モジュールの id と Model の gameID が一致する")
    func idsMatch() {
        #expect(HanafudaModule().id == HanafudaModel.gameID)
        #expect(HanafudaModule().id == "hanafuda")
    }

    /// 権利チェック（#495）の結論。`花札` `こいこい` 単独は採用可だが、
    /// **「花札 ONLINE / 花札オンライン」の組合せ商標（そらいろ㈱ 登録5903259・第9類）**を
    /// 踏まないようにする。`月見酒` は第41類を含む登録があるため、ゲーム内の役名としては
    /// 使うが**ハブに出る表示名・説明・ID には載せない**（ASO 面での不使用は入稿側の運用）。
    @Test("表示名・説明・ID が権利チェックの結論に沿っている")
    func respectsTrademarkFindings() {
        let module = HanafudaModule()
        let surfaces = [module.id, module.title, module.description]
        for forbidden in ["花札オンライン", "花札online", "hanafuda online", "月見酒"] {
            for surface in surfaces {
                #expect(
                    !surface.lowercased().contains(forbidden.lowercased()),
                    "使用を避ける語 '\(forbidden)' が '\(surface)' に入っている"
                )
            }
        }
        #expect(module.title == "花札こいこい")
    }

    @Test("遊び方ガイドがこのゲームの ID に紐づいている")
    func howToPlayGuideIsWired() {
        #expect(HowToPlayGuide.hanafuda.gameID == HanafudaModel.gameID)
        #expect(HowToPlayGuide.all.contains { $0.gameID == HanafudaModel.gameID })
    }

    @Test("リーダーボードは合計文数（High to Low）に紐づいている")
    func leaderboardIsWired() {
        let entry = GameCenterLeaderboard.score(
            gameID: HanafudaModel.gameID,
            outcome: .win,
            score: GameScore(metric: .points, points: 24)
        )
        #expect(entry == GameCenterScore(leaderboardID: GameCenterLeaderboard.hanafudaPoints, value: 24))
        #expect(GameCenterLeaderboard.allIDs.contains(GameCenterLeaderboard.hanafudaPoints))
    }

    @Test("レコメンドの遷移先が登録されている")
    func recommendationIsWired() {
        let related = RecommendationPolicy.candidateTable[HanafudaModel.gameID]
        #expect(related?.isEmpty == false)
        // 自分自身を勧めない。
        #expect(related?.contains(HanafudaModel.gameID) == false)
    }
}
