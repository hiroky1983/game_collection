import Testing
import Core
@testable import GameColorRelay

private let deck = RelayCard.makeDeck()

/// 山札から `color` と `kind` の一致する `nth` 枚目を取る（同じ種類の札は 2 枚ずつあるので ID が違う）。
func card(_ color: RelayColor?, _ kind: RelayKind, nth: Int = 0) -> RelayCard {
    deck.filter { $0.color == color && $0.kind == kind }[nth]
}

@Suite("いろリレーの山札")
struct ColorRelayDeckTests {
    @Test("108 枚で、色ごとに 0 が 1 枚・1〜9 が 2 枚ずつ・特殊札が 2 枚ずつ、万能札が 4 枚ずつ")
    func composition() {
        #expect(deck.count == 108)
        #expect(Set(deck.map(\.id)).count == 108, "ID が重複していない")
        for color in RelayColor.allCases {
            let mine = deck.filter { $0.color == color }
            #expect(mine.count == 25)
            #expect(mine.filter { $0.kind == .number(0) }.count == 1)
            for n in 1...9 {
                #expect(mine.filter { $0.kind == .number(n) }.count == 2, "\(color.name)の\(n)")
            }
            #expect(mine.filter { $0.kind == .skip }.count == 2)
            #expect(mine.filter { $0.kind == .reverse }.count == 2)
            #expect(mine.filter { $0.kind == .drawTwo }.count == 2)
        }
        #expect(deck.filter { $0.kind == .wild }.count == 4)
        #expect(deck.filter { $0.kind == .wildDrawFour }.count == 4)
        #expect(deck.filter(\.isWild).allSatisfy { $0.color == nil }, "万能札は色を持たない")
    }

    @Test("特殊札の引き札の枚数と表記")
    func kinds() {
        #expect(RelayKind.drawTwo.penalty == 2)
        #expect(RelayKind.wildDrawFour.penalty == 4)
        #expect(RelayKind.skip.penalty == 0)
        #expect(RelayKind.number(7).label == "7")
        #expect(RelayKind.wildDrawFour.label == "いろがえ+4")
        #expect(RelayColor.allCases.map(\.name) == ["あか", "みどり", "むらさき", "きいろ"])
    }

    @Test("手札の並びは 色 → 数字 → 特殊札 で、万能札が末尾")
    func sortOrder() {
        let hand = [card(nil, .wild), card(.green, .skip), card(.red, .number(9)), card(.red, .number(2)), card(.green, .number(1))]
            .sorted { $0.sortKey < $1.sortKey }
        #expect(hand.map(\.kind) == [.number(2), .number(9), .number(1), .skip, .wild])
        #expect(hand.map(\.color) == [.red, .red, .green, .green, nil])
    }
}

@Suite("いろリレーの出せる判定")
struct ColorRelayPlayabilityTests {
    @Test("同じ色・同じ数字・同じ記号なら出せ、万能札はいつでも出せる")
    func canPlay() {
        let top = card(.red, .number(7))
        #expect(ColorRelayRules.canPlay(card(.red, .number(3)), onto: top, activeColor: .red), "同じ色")
        #expect(ColorRelayRules.canPlay(card(.green, .number(7)), onto: top, activeColor: .red), "同じ数字")
        #expect(ColorRelayRules.canPlay(card(.red, .skip), onto: top, activeColor: .red), "同じ色の特殊札")
        #expect(ColorRelayRules.canPlay(card(nil, .wild), onto: top, activeColor: .red), "いろがえ")
        #expect(ColorRelayRules.canPlay(card(nil, .wildDrawFour), onto: top, activeColor: .red), "いろがえ+4")
        #expect(!ColorRelayRules.canPlay(card(.green, .number(3)), onto: top, activeColor: .red), "色も数字も違う")
        #expect(!ColorRelayRules.canPlay(card(.green, .skip), onto: top, activeColor: .red), "色の違う特殊札")

        let skip = card(.purple, .skip)
        #expect(ColorRelayRules.canPlay(card(.yellow, .skip), onto: skip, activeColor: .purple), "同じ記号")
        #expect(!ColorRelayRules.canPlay(card(.yellow, .reverse), onto: skip, activeColor: .purple), "違う記号")
    }

    @Test("いろがえの上では選ばれた色だけを見る")
    func ontoWild() {
        let top = card(nil, .wild)
        #expect(ColorRelayRules.canPlay(card(.yellow, .number(1)), onto: top, activeColor: .yellow))
        #expect(!ColorRelayRules.canPlay(card(.red, .number(1)), onto: top, activeColor: .yellow))
        #expect(ColorRelayRules.canPlay(card(nil, .wildDrawFour), onto: top, activeColor: .yellow), "万能札は重ねられる")
    }

    @Test("出せる札の ID を集める")
    func playableIDs() {
        let hand = [card(.red, .number(3)), card(.green, .number(7)), card(.green, .number(2)), card(nil, .wild)]
        let ids = ColorRelayRules.playableCardIDs(hand: hand, top: card(.red, .number(7)), activeColor: .red)
        #expect(ids == Set([card(.red, .number(3)).id, card(.green, .number(7)).id, card(nil, .wild).id]))
    }
}

@Suite("いろリレーの CPU")
struct ColorRelayCPUTests {
    @Test("出せる札が無ければ nil（山から引く）")
    func drawsWhenNothingPlayable() {
        let hand = [card(.green, .number(3)), card(.purple, .number(5))]
        #expect(ColorRelayRules.cpuPlay(hand: hand, top: card(.red, .number(7)), activeColor: .red, nextHandCount: 5) == nil)
    }

    @Test("色の合う数字札を大きい数字から出す。万能札は温存する")
    func prefersMatchingNumbers() {
        let hand = [card(nil, .wild), card(.red, .number(3)), card(.red, .number(9)), card(.green, .number(7))]
        let play = ColorRelayRules.cpuPlay(hand: hand, top: card(.red, .number(7)), activeColor: .red, nextHandCount: 5)
        #expect(play == card(.red, .number(9)))
    }

    @Test("いろがえ+4 はいろがえより後に出す")
    func savesWildDrawFour() {
        let hand = [card(nil, .wildDrawFour), card(nil, .wild)]
        let play = ColorRelayRules.cpuPlay(hand: hand, top: card(.red, .number(7)), activeColor: .red, nextHandCount: 5)
        #expect(play == card(nil, .wild))
    }

    @Test("次の人の手札が 2 枚以下なら番を奪う札を先に出す（いろがえ+4 → +2 → とばし → ぎゃく）")
    func attacksWhenNextIsClose() {
        let top = card(.red, .number(7))
        let all = [card(.red, .number(9)), card(.red, .reverse), card(.red, .skip), card(.red, .drawTwo), card(nil, .wildDrawFour)]
        #expect(ColorRelayRules.cpuPlay(hand: all, top: top, activeColor: .red, nextHandCount: 2) == card(nil, .wildDrawFour))
        let noWild = Array(all.dropLast())
        #expect(ColorRelayRules.cpuPlay(hand: noWild, top: top, activeColor: .red, nextHandCount: 1) == card(.red, .drawTwo))
        let noDraw = Array(noWild.dropLast())
        #expect(ColorRelayRules.cpuPlay(hand: noDraw, top: top, activeColor: .red, nextHandCount: 2) == card(.red, .skip))
        let onlyReverse = [card(.red, .number(9)), card(.red, .reverse)]
        #expect(ColorRelayRules.cpuPlay(hand: onlyReverse, top: top, activeColor: .red, nextHandCount: 2) == card(.red, .reverse))
        // 次の人が 3 枚以上なら数字札を優先する。
        #expect(ColorRelayRules.cpuPlay(hand: all, top: top, activeColor: .red, nextHandCount: 3) == card(.red, .number(9)))
    }

    @Test("色が合わないときは、手札で最も多い色へ寄せられる同じ数字の札を選ぶ")
    func steersTowardDominantColor() {
        let hand = [card(.green, .number(7)), card(.purple, .number(7)), card(.purple, .number(1)), card(.purple, .number(2))]
        let play = ColorRelayRules.cpuPlay(hand: hand, top: card(.red, .number(7)), activeColor: .red, nextHandCount: 5)
        #expect(play == card(.purple, .number(7)))
    }

    @Test("いろがえで選ぶ色は手札で最も多い色。同数なら並び順で先、色札が無ければあか")
    func dominantColor() {
        #expect(ColorRelayRules.dominantColor(in: [card(.yellow, .number(1)), card(.yellow, .number(2)), card(.green, .number(3))]) == .yellow)
        #expect(ColorRelayRules.dominantColor(in: [card(.yellow, .number(1)), card(.green, .number(3))]) == .green)
        #expect(ColorRelayRules.dominantColor(in: [card(nil, .wild)]) == .red)
    }

    @Test("順位は上がった人が 1 位で、残りは手札の少ない順（同数は番号順）")
    func ranking() {
        let hands: [[RelayCard]] = [
            [card(.red, .number(1)), card(.red, .number(2))],
            [],
            [card(.green, .number(1))],
            [card(.purple, .number(1)), card(.purple, .number(2))],
        ]
        #expect(ColorRelayRules.ranking(hands: hands, winner: 1) == [1, 2, 0, 3])
    }
}
