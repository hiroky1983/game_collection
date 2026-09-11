import Core
import Foundation
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

@Suite("花札: 月と種別の帯（#602）")
struct HanafudaBandTests {

    /// 帯の色が種別ごとに違うこと。**帯の文字が潰れる小ささ**（取り札の帯は幅 27pt 前後）では
    /// 色だけが手掛かりになるので、4 種別 + 短冊の赤 / 青がすべて別の値でなければならない。
    @Test("帯の色は光・タネ・赤短・青短・カスの5通りに分かれる")
    func bandColorsAreDistinct() {
        let hexes = HanafudaCard.fullDeck.map { HanafudaCardArt.kindHex(for: $0) }
        #expect(Set(hexes).count == 5)
        #expect(HanafudaCardArt.kindHex(for: HanafudaCard.named("松に鶴"))
                != HanafudaCardArt.kindHex(for: HanafudaCard.named("梅に鶯")))
        #expect(HanafudaCardArt.kindHex(for: HanafudaCard.named("松に赤短"))
                == HanafudaCardArt.redRibbonBandHex)
        #expect(HanafudaCardArt.kindHex(for: HanafudaCard.named("牡丹に青短"))
                == HanafudaCardArt.blueRibbonBandHex)
    }

    /// 無地の短冊（藤・菖蒲・萩・柳）は赤短と同じ赤で出す。役の上では「タン」として
    /// 同じ働きをするので、帯で区別を作らない。
    @Test("無地の短冊の帯は赤短と同じ赤")
    func plainRibbonSharesTheRedBand() {
        #expect(HanafudaCardArt.kindHex(for: HanafudaCard.named("藤に短冊"))
                == HanafudaCardArt.kindHex(for: HanafudaCard.named("松に赤短")))
    }

    /// `kindHex` は短冊札を `ribbon` で振り分けており、`.tanzaku` の分岐には来ない前提で書いてある。
    /// 表のほうで短冊札に `ribbon` を付け忘れると、その札だけ赤短の帯になって静かに嘘をつく。
    @Test("短冊札は10枚すべてが短冊の色を持つ")
    func everyTanzakuHasARibbon() {
        let tanzaku = HanafudaCard.fullDeck.filter { $0.kind == .tanzaku }
        #expect(tanzaku.count == 10)
        #expect(tanzaku.allSatisfy { $0.ribbon != nil })
        // 逆向きも縛る（短冊以外に色が付いていない）。
        #expect(HanafudaCard.fullDeck.filter { $0.ribbon != nil }.count == 10)
    }

    /// 帯は文字を載せる面なので、地と文字のコントラストが AA（4.5:1）を満たさなければ
    /// 種別が読めない。**1 つの色で面と文字の両方は賄えない**ため、地ごとに文字色を選ぶ（#220）。
    @Test("48枚すべてで帯の文字が AA のコントラストを満たす")
    func bandLabelMeetsAA() {
        for card in HanafudaCard.fullDeck {
            let background = HanafudaCardArt.kindHex(for: card)
            let label = HanafudaCardArt.bandLabelHex(on: background)
            let ratio = HanafudaCardArt.contrastRatio(background, label)
            #expect(ratio >= 4.5,
                    "\(card.name) の帯 \(String(background, radix: 16)) と文字のコントラストが \(ratio)")
        }
    }

    /// 金の帯だけは墨、それ以外は生成りが選ばれる。明るい面に白を載せて読めなくなる形
    /// （`bandLabelHex` を固定色に戻す変異）をここで捕まえる。
    @Test("文字色は帯の明るさで生成りと墨を選び分ける")
    func bandLabelSwitchesWithBrightness() {
        let hikari = HanafudaCardArt.kindHex(for: HanafudaCard.named("松に鶴"))
        let kasu = HanafudaCardArt.kindHex(for: HanafudaCard.named("桐のカス"))
        #expect(HanafudaCardArt.bandLabelHex(on: hikari) == HanafudaCardArt.bandLabelDarkHex)
        #expect(HanafudaCardArt.bandLabelHex(on: kasu) == HanafudaCardArt.bandLabelLightHex)
    }

    /// 帯には月の数字も並ぶ。`label`（「短冊」）のままだと 12 月の短冊札で 4 文字になり、
    /// 札の幅では潰れて読めない。
    @Test("帯に出す種別の表記は2文字まで")
    func badgeLabelsAreShort() {
        for kind in HanafudaKind.allCases {
            #expect(kind.badgeLabel.count <= 2, "\(kind.label) の帯表記が長い")
        }
        #expect(HanafudaKind.tanzaku.badgeLabel == "短")
        // 短くするのは短冊だけ。他は読み上げと同じ語のままにする（画面と VoiceOver を揃える）。
        for kind in HanafudaKind.allCases where kind != .tanzaku {
            #expect(kind.badgeLabel == kind.label)
        }
    }

    /// 帯と図案が食い合わないこと。帯を厚くしたり図案の領域を上へ広げたりすると、
    /// 主役（鶴の首・幕・雁）が帯に隠れる。
    @Test("帯と図案の領域が重ならず、合わせて札全体になる")
    func bandAndArtDoNotOverlap() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 90)
        let band = HanafudaCardFace.bandRect(in: rect)
        let art = HanafudaCardFace.artRect(in: rect)
        #expect(band.maxY <= art.minY)
        #expect(band.minY == rect.minY)
        #expect(art.maxY == rect.maxY)
        #expect(abs(band.height + art.height - rect.height) < 0.001)
        // 図案が札の 3/4 以上を保つ（帯が太りすぎていない）。
        #expect(art.height / rect.height >= 0.75)
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

    // 花札こいこいはv1.1.4のハブから次版へ持ち越したため（#642）、`AppEnvironment.registry`に
    // 登録が無いあいだは`RecommendationPolicy.candidateTable`にもエントリを持たない
    // （レコメンドの起点にならないゲームを候補テーブルに残すと#237と同じ形の不整合になるため）。
    // 次版で`registry`に戻すときは、このテストも本来の「遷移先が登録されている」検証に戻すこと。
    @Test("レコメンドの遷移先は無い（v1.1.4では未登録のため）")
    func recommendationIsWired() {
        let related = RecommendationPolicy.candidateTable[HanafudaModel.gameID]
        #expect(related == nil)
    }
}
