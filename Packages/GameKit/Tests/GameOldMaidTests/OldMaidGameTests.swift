import Testing
import Foundation
import CoreEngine
@testable import GameOldMaid

// 盤面の生成・合法な引き方・終局判定の検査（#1577）。`OldMaidGame` は Core にも SwiftUI にも依存しない
// 純粋な値なので、Model を通さずにここで固定する。

private func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
    OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

private func shuffledDeck(seed: UInt64) -> [OldMaidCard] {
    var generator = SplitMix64(seed: seed)
    var deck = OldMaidCard.makeDeck()
    deck.shuffle(using: &generator)
    return deck
}

/// どの人の手札にも同じ数字が 2 枚無い（ペアは必ず捨てられている）。
private func hasNoPairs(_ game: OldMaidGame) -> Bool {
    game.hands.allSatisfy { hand in
        let ranks = hand.filter { !$0.isJoker }.map(\.rank)
        return Set(ranks).count == ranks.count
    }
}

/// 決着まで回す。あなたの番は `pickHuman`（既定はでたらめ）で引く。
private func playOut(
    _ game: inout OldMaidGame, seed: UInt64, maxDraws: Int = 5_000,
    pickHuman: ((OldMaidGame, inout SplitMix64) -> Int?)? = nil,
    check: (OldMaidGame) -> Void = { _ in }
) -> Int {
    var generator = SplitMix64(seed: seed)
    var draws = 0
    while !game.isOver, draws < maxDraws {
        if game.currentPlayer == OldMaidGame.humanIndex {
            let target = game.currentTarget!
            let id = pickHuman?(game, &generator) ?? game.hands[target].randomElement(using: &generator)!.id
            do { let ok = game.draw(cardID: id); #expect(ok) }
        } else {
            do { let ok = game.performCPUTurn(using: &generator); #expect(ok) }
        }
        draws += 1
        check(game)
    }
    return draws
}

@Suite("ババ抜きの札")
struct OldMaidCardTests {
    @Test("53 枚（数字札 52 + ジョーカー 1）で、ID は 0〜52 の重複なし")
    func deck() {
        let deck = OldMaidCard.makeDeck()
        #expect(deck.count == 53)
        #expect(Set(deck.map(\.id)) == Set(0..<53))
        #expect(deck.filter(\.isJoker).count == 1)
        #expect(deck.last == .joker)
        for rank in 1...13 {
            #expect(deck.filter { $0.rank == rank && !$0.isJoker }.count == 4, "\(rank) が 4 枚ない")
        }
    }

    @Test("面は共通基盤の図案に渡す（ジョーカーは共通部品のジョーカー）")
    func figures() {
        #expect(OldMaidCard.joker.figure == .joker)
        #expect(card(.hearts, 5).figure == .pip(suit: .heart, rank: 5))
        #expect(card(.spades, 1).label == "♠A")
        #expect(card(.clubs, 13).figure == .pip(suit: .club, rank: 13))
    }

    @Test("ペアは同じ数字の 2 枚ずつ抜く。3 枚なら 1 枚残り、ジョーカーは残る")
    func removingPairs() {
        let hand = [card(.spades, 5), OldMaidCard.joker, card(.hearts, 5), card(.clubs, 5), card(.diamonds, 9)]
        let result = OldMaidGame.removingPairs(from: hand)
        #expect(result.pairs == [[card(.spades, 5), card(.hearts, 5)]])
        #expect(result.kept == [OldMaidCard.joker, card(.clubs, 5), card(.diamonds, 9)])
        let four = OldMaidGame.removingPairs(from: OldMaidSuit.allCases.map { card($0, 7) })
        #expect(four.pairs.count == 2)
        #expect(four.kept.isEmpty)
    }
}

@Suite("ババ抜きの配り")
struct OldMaidDealTests {
    @Test("配った直後: 53 枚が失われず、誰の手札にもペアが無い。最初に配られた人が 14 枚ぶん受け取る")
    func dealIsConsistent() {
        for seed in UInt64(1)...300 {
            let first = Int(seed % 4)
            let game = OldMaidGame(deck: shuffledDeck(seed: seed), firstPlayer: first, aiLevel: 1, tellSeed: seed)
            #expect(game.totalCardCount == 53, "seed \(seed)")
            #expect(hasNoPairs(game), "seed \(seed)")
            #expect(game.isConsistent, "seed \(seed)")
            #expect(game.jokerHolder != nil)
            // 配った枚数 = 残り + 捨てたペア × 2。最初の人は 14 枚、他は 13 枚。
            for player in 0..<4 {
                let pairs: Int
                if case .dealtPairs(let n) = game.lastActions[player] { pairs = n } else { pairs = -1 }
                #expect(game.hands[player].count + pairs * 2 == (player == first ? 14 : 13), "seed \(seed) player \(player)")
            }
            // 番は最初の人（手札が尽きていなければ）。
            if !game.hands[first].isEmpty { #expect(game.currentPlayer == first) }
            #expect(!game.isOver)
        }
    }

    @Test("あなたの手札は数字順・ジョーカーは右端に並べて渡す")
    func humanHandIsSorted() {
        for seed in UInt64(1)...50 {
            let game = OldMaidGame(deck: shuffledDeck(seed: seed), firstPlayer: 0, aiLevel: 1, tellSeed: seed)
            let keys = game.hands[0].map(\.sortKey)
            #expect(keys == keys.sorted(), "seed \(seed)")
            #expect(!game.humanJokerWatched, "配られたジョーカーの場所は誰にも見えていない")
        }
    }

    @Test("ペアだけで手札が尽きた人は配った時点で抜ける")
    func emptyAfterDealFinishes() {
        // 最初の人（あなた）に 7 組のペアが行く並び。残りは何でもよい。
        var deck: [OldMaidCard] = []
        let pairRanks = Array(1...7)
        var rest = OldMaidCard.makeDeck()
        var mine: [OldMaidCard] = []
        for rank in pairRanks {
            for suit in [OldMaidSuit.spades, .hearts] {
                let c = card(suit, rank)
                mine.append(c)
                rest.removeAll { $0 == c }
            }
        }
        // あなたは 0, 4, 8, … 番目に配られる。
        var restIterator = rest.makeIterator()
        var mineIterator = mine.makeIterator()
        for index in 0..<53 {
            if index % 4 == 0, let c = mineIterator.next() { deck.append(c) } else { deck.append(restIterator.next()!) }
        }
        let game = OldMaidGame(deck: deck, firstPlayer: 0, aiLevel: 1, tellSeed: 1)
        #expect(game.hands[0].isEmpty)
        #expect(game.finishOrder == [0])
        #expect(game.currentPlayer == 1, "抜けた人の番は飛ばす")
        #expect(game.isConsistent)
    }
}

@Suite("ババ抜きの引き方")
struct OldMaidDrawTests {
    @Test("引けるのは次の人の手札の札だけ。自分の札・抜けた人の札・存在しない札は引けない")
    func onlyTargetCards() {
        var game = OldMaidGame(hands: [
            [card(.spades, 1), card(.spades, 2)],
            [card(.hearts, 3), OldMaidCard.joker],
            [card(.hearts, 1)],
            [card(.hearts, 2), card(.spades, 3)],
        ])
        #expect(game.currentTarget == 1)
        do { let ok = game.draw(cardID: card(.spades, 1).id); #expect(!ok, "自分の札") }
        do { let ok = game.draw(cardID: card(.hearts, 1).id); #expect(!ok, "引く相手ではない人の札") }
        do { let ok = game.draw(cardID: 999); #expect(!ok) }
        #expect(game.turnSerial == 0, "引けなかったときは何も進まない")
        do { let ok = game.draw(cardID: OldMaidCard.jokerID); #expect(ok) }
        #expect(game.hands[0].last == .joker, "あなたが引いた札は右端に入る")
        #expect(game.humanJokerWatched, "右端に置いたジョーカーは見られている")
        #expect(game.lastActions[0] == .drewKept)
        #expect(game.currentPlayer == 1, "番は引かれた人へ移る")
        #expect(game.currentTarget == 2)
    }

    @Test("ペアができたら捨てる。最後の 1 枚を引かれた人・引いて手札が尽きた人の順に抜ける")
    func pairsAndFinishing() {
        var game = OldMaidGame(hands: [
            [card(.spades, 4)],
            [card(.hearts, 4)],
            [OldMaidCard.joker, card(.hearts, 9)],
            [card(.spades, 9)],
        ])
        do { let ok = game.draw(cardID: card(.hearts, 4).id); #expect(ok) }
        #expect(game.lastActions[0] == .drewPair(rank: 4))
        #expect(game.discardedPairs.last == [card(.spades, 4), card(.hearts, 4)])
        #expect(game.finishOrder == [1, 0])
        #expect(game.lastTransfer == OldMaidTransfer(from: 1, to: 0, card: card(.hearts, 4), paired: true))
        #expect(game.currentPlayer == 2, "抜けた人を飛ばして次の人の番")
        #expect(game.currentTarget == 3)
        // 2 が 3 の最後の 1 枚（9）を引いてペアで捨て、3 が抜ける。2 の手にはジョーカー 1 枚だけが残る。
        do { let ok = game.draw(cardID: card(.spades, 9).id); #expect(ok) }
        #expect(game.isOver)
        #expect(game.loser == 2)
        #expect(game.ranking == [1, 0, 3, 2])
        do { let ok = game.draw(cardID: OldMaidCard.jokerID); #expect(!ok, "決着後は引けない") }
    }

    @Test("CPU は相手の手札にある札だけを引き、自分の番でないときは何もしない")
    func cpuOnlyLegalMoves() {
        var generator = SplitMix64(seed: 3)
        var game = OldMaidGame(hands: [
            [card(.spades, 1)],
            [card(.hearts, 2), card(.hearts, 3)],
            [card(.clubs, 2), OldMaidCard.joker],
            [card(.clubs, 3), card(.clubs, 1)],
        ])
        do { let ok = game.performCPUTurn(using: &generator); #expect(!ok, "あなたの番に CPU は引かない") }
        do { let ok = game.draw(cardID: card(.hearts, 2).id); #expect(ok) }
        #expect(game.currentPlayer == 1)
        let targetIDs = Set(game.hands[2].map(\.id))
        for seed in UInt64(0)..<50 {
            var g = SplitMix64(seed: seed)
            let choice = game.cpuChoice(using: &g)
            #expect(choice.map(targetIDs.contains) == true)
        }
    }

    @Test("決着までどの局も合法手だけで進み、札は 53 枚のまま・ペアは残らず・負けは 1 人（ジョーカー 1 枚）")
    func playsToTheEnd() {
        for seed in UInt64(1)...400 {
            for level in CPUStrength.allCases {
                var game = OldMaidGame(deck: shuffledDeck(seed: seed), firstPlayer: Int(seed % 4),
                                       aiLevel: level.rawValue, tellSeed: seed)
                let draws = playOut(&game, seed: seed &* 31) { g in
                    #expect(g.totalCardCount == 53)
                    #expect(hasNoPairs(g))
                }
                #expect(game.isOver, "seed \(seed) / \(level): \(draws) 回引いても決着しない")
                #expect(game.isConsistent)
                #expect(game.loser.map { game.hands[$0] == [OldMaidCard.joker] } == true, "最後に残るのはジョーカー 1 枚")
                #expect(game.ranking.count == 4)
                #expect(Set(game.ranking) == Set(0..<4))
                #expect(game.ranking.last == game.loser)
                #expect(game.currentTarget == nil)
            }
        }
    }

    @Test("あなたが抜けたあとも CPU だけで決着まで進む")
    func cpusFinishWithoutHuman() {
        var generator = SplitMix64(seed: 9)
        var game = OldMaidGame(hands: [
            [card(.spades, 4)],
            [card(.hearts, 4), card(.hearts, 6)],
            [OldMaidCard.joker, card(.clubs, 6), card(.clubs, 8)],
            [card(.spades, 8)],
        ])
        do { let ok = game.draw(cardID: card(.hearts, 4).id); #expect(ok) }
        #expect(game.finishOrder == [0])
        var steps = 0
        while !game.isOver, steps < 100 {
            #expect(game.currentPlayer != OldMaidGame.humanIndex, "抜けたあなたに番は回らない")
            do { let ok = game.performCPUTurn(using: &generator); #expect(ok) }
            steps += 1
        }
        #expect(game.isOver)
        #expect(game.loser != OldMaidGame.humanIndex)
        #expect(game.ranking.first == 0)
    }
}

@Suite("ババ抜きの CPU の強さ")
struct OldMaidStrengthTests {
    /// あなたの手札の右端にジョーカーを置いたまま、CPU3 があなたから引く局面。
    private func watchedGame(level: CPUStrength, watched: Bool) -> OldMaidGame {
        OldMaidGame(hands: [
            [card(.spades, 1), card(.spades, 2), card(.spades, 3), OldMaidCard.joker],
            [card(.hearts, 4)],
            [card(.hearts, 5)],
            [card(.hearts, 6), card(.hearts, 7)],
        ], currentPlayer: 3, aiLevel: level.rawValue, humanJokerWatched: watched)
    }

    private func jokerRate(level: CPUStrength, watched: Bool) -> Double {
        let game = watchedGame(level: level, watched: watched)
        var generator = SplitMix64(seed: 77)
        let trials = 4_000
        var jokers = 0
        for _ in 0..<trials where game.cpuChoice(using: &generator) == OldMaidCard.jokerID { jokers += 1 }
        return Double(jokers) / Double(trials)
    }

    @Test("見ていたジョーカーは強いほどよける。混ぜられたら誰でも 4 枚に 1 枚")
    func watchAvoidsJoker() {
        let rates = CPUStrength.allCases.map { jokerRate(level: $0, watched: true) }
        // 入門 0.25 → かんたん 0.175 → ふつう 0.1 → むずかしい 0.025（期待値）。
        #expect(abs(rates[0] - 0.25) < 0.03)
        #expect(rates == rates.sorted(by: >), "強いほどジョーカーを引きにくい: \(rates)")
        #expect(rates[3] < 0.05)
        for level in CPUStrength.allCases {
            #expect(abs(jokerRate(level: level, watched: false) - 0.25) < 0.03, "\(level): 混ぜたあとは読めない")
        }
    }

    @Test("あなたが引いたジョーカーは見張られ、シャッフルするか出ていくと見張りが外れる")
    func watchFlag() {
        var game = OldMaidGame(hands: [
            [card(.spades, 1)],
            [OldMaidCard.joker, card(.hearts, 2)],
            [card(.hearts, 1), card(.spades, 2)],
            [card(.clubs, 3), card(.hearts, 3)],
        ])
        do { let ok = game.draw(cardID: OldMaidCard.jokerID); #expect(ok) }
        #expect(game.humanJokerWatched)
        var generator = SplitMix64(seed: 1)
        game.shuffleHand(of: 0, using: &generator)
        #expect(!game.humanJokerWatched)
        #expect(Set(game.hands[0]) == [card(.spades, 1), OldMaidCard.joker])
    }

    @Test("顔に出るのはジョーカーを持つ CPU だけ。同じ番・同じ札なら同じ顔。むずかしいは顔に出ない")
    func faces() {
        for level in CPUStrength.allCases {
            var smiles = 0, worries = 0
            for seed in UInt64(1)...400 {
                let game = OldMaidGame(hands: [
                    [card(.spades, 1)],
                    [OldMaidCard.joker, card(.hearts, 2), card(.hearts, 3)],
                    [card(.hearts, 1), card(.spades, 2)],
                    [card(.clubs, 3)],
                ], aiLevel: level.rawValue, tellSeed: seed)
                let onJoker = game.face(of: 1, touching: OldMaidCard.jokerID)
                #expect(onJoker == game.face(of: 1, touching: OldMaidCard.jokerID), "触り直しで顔が変わる")
                #expect(onJoker != .worried)
                if onJoker == .smile { smiles += 1 }
                let onOther = game.face(of: 1, touching: card(.hearts, 2).id)
                #expect(onOther != .smile)
                if onOther == .worried { worries += 1 }
                // ジョーカーを持たない CPU・手札に無い札・指を離したときはふつうの顔。
                #expect(game.face(of: 2, touching: card(.hearts, 1).id) == .neutral)
                #expect(game.face(of: 1, touching: card(.hearts, 1).id) == .neutral)
                #expect(game.face(of: 1, touching: nil) == .neutral)
            }
            let expected = OldMaidTuning.tellChance(level)
            #expect(abs(Double(smiles) / 400 - expected) < 0.08, "\(level): にやり \(smiles)/400")
            #expect(abs(Double(worries) / 400 - expected) < 0.08, "\(level): ひやり \(worries)/400")
        }
    }

    @Test("強さの振る舞いは強いほど顔に出にくく、置き場所をよく覚える")
    func tuningIsMonotonic() {
        let tells = CPUStrength.allCases.map(OldMaidTuning.tellChance)
        let watches = CPUStrength.allCases.map(OldMaidTuning.watchChance)
        #expect(tells == tells.sorted(by: >))
        #expect(watches == watches.sorted())
        #expect(tells.last == 0)
        #expect(watches.first == 0)
    }

    @Test("でたらめに引くあなた（入門の CPU 相手）より、顔を読むあなたのほうがジョーカーを持ち帰りにくい")
    func readingFacesHelps() {
        func loseRate(readFaces: Bool) -> Double {
            var losses = 0
            let games = 300
            for seed in UInt64(1)...UInt64(games) {
                var game = OldMaidGame(deck: shuffledDeck(seed: seed), firstPlayer: 0,
                                       aiLevel: CPUStrength.novice.rawValue, tellSeed: seed)
                _ = playOut(&game, seed: seed, pickHuman: { g, generator in
                    let target = g.currentTarget!
                    let ids = g.hands[target].map(\.id).shuffled(using: &generator)
                    guard readFaces else { return ids.first }
                    // 顔ににやりと出た札は避け、ひやりと出た札があれば引く。
                    if let safe = ids.first(where: { g.face(of: target, touching: $0) == .worried }) { return safe }
                    return ids.first { g.face(of: target, touching: $0) != .smile } ?? ids.first
                })
                if game.loser == OldMaidGame.humanIndex { losses += 1 }
            }
            return Double(losses) / Double(games)
        }
        #expect(loseRate(readFaces: true) < loseRate(readFaces: false))
    }
}

@Suite("ババ抜きの中断データ")
struct OldMaidSnapshotTests {
    @Test("途中の局は JSON を往復しても同じで、検査も通る")
    func roundTrip() throws {
        var game = OldMaidGame(deck: shuffledDeck(seed: 5), firstPlayer: 2, aiLevel: 2, tellSeed: 99)
        var generator = SplitMix64(seed: 5)
        for _ in 0..<10 where !game.isOver {
            if game.currentPlayer == 0 {
                game.draw(cardID: game.hands[game.currentTarget!][0].id)
            } else {
                game.performCPUTurn(using: &generator)
            }
        }
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(OldMaidGame.self, from: data)
        #expect(decoded == game)
        #expect(decoded.isConsistent)
    }

    @Test("札が欠けた・重なった・番の人が抜けている中断データは検査で弾く")
    func brokenIsRejected() {
        let good = OldMaidGame(deck: shuffledDeck(seed: 8), firstPlayer: 0, aiLevel: 1, tellSeed: 1)
        #expect(good.isConsistent)
        var missing = good.hands
        missing[1].removeLast()
        #expect(!OldMaidGame(hands: missing, discardedPairs: good.discardedPairs).isConsistent)
        var duplicated = good.hands
        duplicated[1][0] = duplicated[2][0]
        #expect(!OldMaidGame(hands: duplicated, discardedPairs: good.discardedPairs).isConsistent)
        var emptyTurn = good.hands
        emptyTurn[3] += emptyTurn[0]
        emptyTurn[0] = []
        #expect(!OldMaidGame(hands: emptyTurn, discardedPairs: good.discardedPairs, currentPlayer: 0).isConsistent)
    }
}
