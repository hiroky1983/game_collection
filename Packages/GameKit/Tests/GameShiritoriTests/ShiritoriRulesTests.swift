import Testing
import Foundation
import Core
@testable import GameShiritori

// MARK: - かなの受け方

@Suite("しりとりのかな判定")
struct ShiritoriKanaTests {

    @Test("語尾は最後の字。長音符は 1 つ前の字で受ける")
    func tailSkipsLongMark() {
        #expect(ShiritoriKana.tail(of: "りんご") == "ご")
        #expect(ShiritoriKana.tail(of: "ぎたー") == "た")
        #expect(ShiritoriKana.tail(of: "ぎたーー") == "た", "長音符が続いても 1 つ前の字で受ける")
        #expect(ShiritoriKana.tail(of: "ー") == nil)
        #expect(ShiritoriKana.tail(of: "") == nil)
    }

    @Test("小さい字は大きい字に直して受ける")
    func tailNormalizesSmallKana() {
        #expect(ShiritoriKana.tail(of: "えみゅー") == "ゆ")
        #expect(ShiritoriKana.tail(of: "きゃ") == "や")
        #expect(ShiritoriKana.tail(of: "ちょっ") == "つ")
    }

    @Test("カタカナで書いてもひらがなと同じに扱う")
    func katakanaIsFoldedToHiragana() {
        #expect(ShiritoriKana.hiragana("ドラム") == "どらむ")
        #expect(ShiritoriKana.tail(of: "エミュー") == "ゆ")
        #expect(ShiritoriKana.head(of: "ラッコ") == "ら")
        #expect(ShiritoriKana.hiragana("ぎたー") == "ぎたー", "長音符はそのまま")
    }

    @Test("濁音の語尾は、そのままの字でも濁点を取った字でも受けられる")
    func voicedTailAcceptsBothForms() {
        #expect(ShiritoriKana.accepts(head: "ぎ", after: "ぎ"))
        #expect(ShiritoriKana.accepts(head: "き", after: "ぎ"))
        #expect(ShiritoriKana.accepts(head: "ふ", after: "ぷ"), "半濁音も同じ")
        #expect(ShiritoriKana.accepts(head: "だ", after: "だ"))
    }

    @Test("清音の語尾は濁音の語頭では受けられない・別の字は受けられない")
    func rejectsUnrelatedHeads() {
        #expect(!ShiritoriKana.accepts(head: "ぎ", after: "き"), "濁音で始まる札は清音の語尾に続けない")
        #expect(!ShiritoriKana.accepts(head: "か", after: "ご"))
        #expect(!ShiritoriKana.accepts(head: "ら", after: "り"))
    }

    @Test("「ん」の判定")
    func detectsN() {
        #expect(ShiritoriKana.isN("ん"))
        #expect(!ShiritoriKana.isN("む"))
        #expect(ShiritoriRules.endsWithN("ごはん"))
        #expect(ShiritoriRules.endsWithN("らーめん"))
        #expect(!ShiritoriRules.endsWithN("りんご"), "途中の「ん」は関係ない")
    }
}

// MARK: - 札・盤の判定

private func slots(_ cards: [ShiritoriCard]) -> [ShiritoriSlot] {
    cards.map { ShiritoriSlot(card: $0) }
}

@Suite("しりとりの札と手")
struct ShiritoriRulesTests {

    @Test("山札は 30 枚（#1245）。絵は全種そろい、同じ絵は 2 枚無い")
    func deckMatchesApprovedList() {
        let deck = ShiritoriCard.deck
        #expect(deck.count == 30)
        #expect(Set(deck.map(\.kind)) == Set(ObjectCardKind.allCases))
        #expect(Set(deck.map(\.id)).count == 30)
        #expect(deck.map(\.primaryReading) == [
            "りんご", "ごりら", "らっこ", "こあら", "らくだ", "うさぎ", "ぎたー", "たいこ", "こねこ", "こっぷ",
            "りす", "すいか", "かめ", "めがね", "ねこ", "こま", "まくら", "だちょう", "うちわ", "わに",
            "ふね", "ねぎ", "まり", "きのこ", "うま", "しか", "うし", "すず", "つき", "たこ",
        ])
    }

    @Test("裏読みは決裁済みの 4 枚だけ。読みはすべてひらがなで、空でない")
    func alternateReadingsAreTheApprovedOnes() {
        let withAlternates = ShiritoriCard.deck.filter { $0.readings.count > 1 }
        #expect(Dictionary(uniqueKeysWithValues: withAlternates.map { ($0.primaryReading, Array($0.readings.dropFirst())) }) == [
            "たいこ": ["どらむ"], "こっぷ": ["ぐらす"], "だちょう": ["えみゅー"], "うちわ": ["おうぎ"],
        ])
        for card in ShiritoriCard.deck {
            for reading in card.readings {
                #expect(!reading.isEmpty)
                #expect(reading == ShiritoriKana.hiragana(reading), "\(reading) はひらがなに揃っている")
            }
        }
    }

    @Test("山札に「ん」で終わる読みは 1 つも無い（専用トラップ札は作らない・決裁）")
    func noCardEndsWithN() {
        for card in ShiritoriCard.deck {
            for reading in card.readings {
                #expect(!ShiritoriRules.endsWithN(reading), "\(card.id) の \(reading)")
            }
        }
    }

    @Test("表読みで受けられなければ裏読みで受ける。どちらもだめなら nil")
    func acceptingReadingFallsBackToAlternate() {
        let drum = ShiritoriCard(.drum, "たいこ", "どらむ")
        #expect(ShiritoriRules.acceptingReading(of: drum, after: "た") == "たいこ")
        #expect(ShiritoriRules.acceptingReading(of: drum, after: "ど") == "どらむ", "裏読みで受けられる")
        #expect(ShiritoriRules.acceptingReading(of: drum, after: "と") == nil, "濁音の語頭は清音の語尾では受けない")
        #expect(ShiritoriRules.acceptingReading(of: drum, after: "り") == nil)
    }

    @Test("手は盤の並び順で返し、取られた札は含めない")
    func movesFollowBoardOrderAndSkipTaken() {
        var board = slots([
            ShiritoriCard(.koala, "こあら"),
            ShiritoriCard(.apple, "りんご"),
            ShiritoriCard(.kitten, "こねこ"),
            ShiritoriCard(.spinningTop, "こま"),
        ])
        board[2].owner = .cpu
        let moves = ShiritoriRules.moves(slots: board, after: "こ")
        #expect(moves.map(\.slot) == [0, 3], "こあら・こま（こねこは取られている）")
        #expect(ShiritoriRules.moves(slots: board, after: "そ").isEmpty)
    }

    @Test("CPU は固定順の先頭を選ぶ。難易度・乱数で変わらない")
    func cpuPicksFirstInBoardOrder() {
        let board = slots([
            ShiritoriCard(.apple, "りんご"),
            ShiritoriCard(.spinningTop, "こま"),
            ShiritoriCard(.koala, "こあら"),
        ])
        #expect(ShiritoriRules.cpuMove(slots: board, after: "こ")?.slot == 1)
        #expect(ShiritoriRules.cpuMove(slots: board, after: "こ") == ShiritoriRules.cpuMove(slots: board, after: "こ"))
        #expect(ShiritoriRules.cpuMove(slots: board, after: "そ") == nil)
    }

    @Test("CPU は「ん」で終わる読みも避けない（固定順の先頭を選ぶだけ）")
    func cpuDoesNotAvoidN() {
        let trap = ShiritoriCard(.pillow, "こばん")
        let safe = ShiritoriCard(.kitten, "こねこ")
        #expect(ShiritoriRules.cpuMove(slots: slots([trap, safe]), after: "こ")?.slot == 0, "先頭が「ん」なら選んで負ける")
        #expect(ShiritoriRules.cpuMove(slots: slots([safe, trap]), after: "こ")?.slot == 0)
    }

    @Test("最初の場の札は、プレイヤーの最初の手が残る札から選ぶ")
    func openerLeavesAFirstMove() throws {
        // わに（語尾「に」に続く札は無い）を先頭に置いても、後ろの札が選ばれる。
        let deck = [ShiritoriCard(.crocodile, "わに"), ShiritoriCard(.apple, "りんご"), ShiritoriCard(.gorilla, "ごりら")]
        #expect(ShiritoriRules.openerIndex(in: deck) == 1)
        #expect(ShiritoriRules.openerIndex(in: [ShiritoriCard(.crocodile, "わに")]) == nil)
        // 語尾が「ん」の札は場に出さない。
        let n = [ShiritoriCard(.apple, "ごはん"), ShiritoriCard(.gorilla, "んま")]
        #expect(ShiritoriRules.openerIndex(in: n) == nil)
    }
}

// MARK: - ノルマ

@Suite("ノルマ（難易度）")
struct ShiritoriQuotaTests {

    @Test("ノルマの枚数は やさしい4・ふつう6・むずかしい9（暫定値・#1245）")
    func cardCounts() {
        #expect(ShiritoriQuota.allCases.map(\.cardCount) == [4, 6, 9])
    }

    @Test("ちょうどの枚数で満たし、1 枚足りなければ満たさない")
    func boundaryIsInclusive() {
        for quota in ShiritoriQuota.allCases {
            #expect(quota.isMet(player: quota.cardCount), "\(quota)")
            #expect(!quota.isMet(player: quota.cardCount - 1), "\(quota)")
            #expect(quota.isMet(player: quota.cardCount + 1), "\(quota)")
        }
        for quota in ShiritoriQuota.allCases { #expect(!quota.isMet(player: 0)) }
    }

    @Test("難易度が上がるほどノルマは厳しい（同じ枚数で満たす段が単調に減る）")
    func laddersAreMonotonic() {
        for player in 0...12 {
            let met = ShiritoriQuota.allCases.map { $0.isMet(player: player) }
            #expect(met == met.sorted { $0 && !$1 }, "\(player): \(met)")
        }
    }

    @Test("説明文は枚数を含む")
    func summaryMentionsCount() {
        #expect(ShiritoriQuota.allCases.map(\.summary) == ["4枚取ったらクリア", "6枚取ったらクリア", "9枚取ったらクリア"])
    }

    @Test("解析の段階と表示名")
    func labelsAndAnalyticsLevels() {
        #expect(ShiritoriQuota.allCases.map(\.label) == ["やさしい", "ふつう", "むずかしい"])
        #expect(ShiritoriQuota.allCases.map(\.analyticsLevel) == [.beginner, .normal, .hard])
        #expect(ShiritoriQuota.standard == .normal)
    }
}

// MARK: - ドット絵

@Suite("具体物カードのドット絵")
struct ObjectCardArtTests {

    @Test("全種が 40×40 で、パレットに無い文字を使っていない")
    func spritesAreWellFormed() {
        #expect(ObjectCardKind.allCases.count == 30)
        #expect(ObjectCardKind.dots == 40, "#1287 で 20 → 40 に上げた。全種を同時に戻す退行も赤にする")
        for kind in ObjectCardKind.allCases {
            let sprite = kind.sprite
            #expect(sprite.width == ObjectCardKind.dots && sprite.height == ObjectCardKind.dots, "\(kind)")
            #expect(sprite.undefinedKeys.isEmpty, "\(kind) がパレットに無い文字を使っている")
            #expect(sprite.opaqueBounds != nil, "\(kind) が空の絵")
            #expect(kind.cgImage != nil, "\(kind) のビットマップが作れない")
        }
    }

    @Test("絵は 1 枚ずつ違う（コピペで同じ絵が 2 枚にならない）")
    func spritesAreDistinct() {
        let rows = ObjectCardKind.allCases.map { $0.sprite.rows.joined() }
        #expect(Set(rows).count == rows.count)
    }

    @Test("絵の外周 1 ドットは縁取り（K）か透明だけ（絵が枠に触れて切れていない）")
    func spritesDoNotTouchTheFrame() {
        for kind in ObjectCardKind.allCases {
            let rows = kind.sprite.rows.map(Array.init)
            let last = ObjectCardKind.dots - 1
            let edge = rows[0] + rows[last] + rows.map { $0[0] } + rows.map { $0[last] }
            #expect(edge.allSatisfy { $0 == "." || $0 == "K" }, "\(kind) が枠いっぱいまで描かれて切れている")
        }
    }

    @Test("VoiceOver 用の名前が全種にある")
    func everyKindHasAName() {
        for kind in ObjectCardKind.allCases { #expect(!kind.displayName.isEmpty) }
        #expect(Set(ObjectCardKind.allCases.map(\.displayName)).count == 30)
    }
}
