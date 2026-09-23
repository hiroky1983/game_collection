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

    @Test("裏読みは決裁済みの 3 枚だけ。読みはすべてひらがなで、空でない")
    func alternateReadingsAreTheApprovedOnes() {
        let withAlternates = ShiritoriCard.deck.filter { $0.readings.count > 1 }
        #expect(Dictionary(uniqueKeysWithValues: withAlternates.map { ($0.primaryReading, Array($0.readings.dropFirst())) }) == [
            "こっぷ": ["ぐらす"], "うちわ": ["おうぎ"], "ねこ": ["にゃんこ"],
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

    /// どの札の語尾で終わっても、次を受けられる札が山札に必ずある（#1287 QA: 「わに」が
    /// 「に」で始まる札を 1 枚も持たず、取ると相手が必ず詰んで一発勝ちになっていた）。
    /// この保証が崩れると同じ「取れば勝ち確定」札が生まれる。
    ///
    /// 「どらむ」（語尾 む）・「えみゅー」（語尾 ゆ）も同じ穴だったため、#1292 で裏読み自体を削除した。
    @Test("すべての札の語尾を、別の札の語頭で受けられる（詰み専用札が生まれていないか）")
    func everyTailHasAFollower() {
        for card in ShiritoriCard.deck {
            for reading in card.readings where !ShiritoriRules.endsWithN(reading) {
                guard let tail = ShiritoriKana.tail(of: reading) else { continue }
                let rest = ShiritoriCard.deck.filter { $0.id != card.id }.map { ShiritoriSlot(card: $0) }
                #expect(!ShiritoriRules.moves(slots: rest, after: tail).isEmpty,
                        "\(card.id) の \(reading)（語尾 \(tail)）を受けられる札が無い")
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
        // 「ごはん」（語尾「ん」）は場に出さない。残りは りんご→ごりら→らっこ→こあら で
        // 互いに語尾を受け合える構成（#1297 の新しいチェックでも、どの札を除いても後続が残る）。
        let deck = [
            ShiritoriCard(.apple, "ごはん"), ShiritoriCard(.rabbit, "りんご"), ShiritoriCard(.gorilla, "ごりら"),
            ShiritoriCard(.seaOtter, "らっこ"), ShiritoriCard(.koala, "こあら"),
        ]
        #expect(ShiritoriRules.openerIndex(in: deck) == 1)
        #expect(ShiritoriRules.openerIndex(in: [ShiritoriCard(.crocodile, "わに")]) == nil)
        // 語尾が「ん」の札は場に出さない。
        let n = [ShiritoriCard(.apple, "ごはん"), ShiritoriCard(.gorilla, "んま")]
        #expect(ShiritoriRules.openerIndex(in: n) == nil)
    }

    /// #1297: 「わに」の唯一の後続「にゃんこ」＝ねこ札を開場札に選ぶと、盤の「わに」を取った瞬間に
    /// 相手が詰んで一発勝ちになっていた（#1287型の再発）。開場札の並び順を 30 通り総当たりで変えても、
    /// 選ばれた開場札を除いた 29 枚のどの読みの語尾も、他の札で受けられることを固定する。
    @Test("開場札を除いた29枚でも、唯一の後続を失って詰み専用になる札が生まれない（総当たり30パターン）")
    func openerNeverStripsAnotherCardsOnlyFollower() throws {
        let deck = ShiritoriCard.deck
        for rotation in deck.indices {
            let rotated = Array(deck[rotation...] + deck[..<rotation])
            let openerIdx = try #require(ShiritoriRules.openerIndex(in: rotated), "rotation \(rotation): 開場札が見つからない")
            var rest = rotated
            let opener = rest.remove(at: openerIdx)
            // 検証対象の openerIndex と同じ hasDeadEndReading を使うと、そちらのロジック自体の
            // バグを見逃しうるため、ここは `moves` を直接呼んで独立に確かめる（CodeRabbit 指摘）。
            for card in rest {
                let otherSlots = rest.filter { $0.id != card.id }.map { ShiritoriSlot(card: $0) }
                for reading in card.readings {
                    guard !ShiritoriRules.endsWithN(reading), let tail = ShiritoriKana.tail(of: reading) else { continue }
                    #expect(!ShiritoriRules.moves(slots: otherSlots, after: tail).isEmpty,
                            "rotation \(rotation): 開場札 \(opener.id) を除くと \(card.id) の読み \(reading) に後続がない")
                }
            }
        }
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
