import Testing
import Foundation
@testable import GameSolitaire

/// 場札1列を組み立てる短縮記法。
private func pile(down: [SolitaireCard] = [], up: [SolitaireCard]) -> SolitairePile {
    SolitairePile(faceDown: down, faceUp: up)
}

private func board(
    _ piles: [SolitairePile],
    foundations: [Int] = [0, 0, 0, 0],
    stock: [SolitaireCard] = [],
    waste: [SolitaireCard] = [],
    joker: Bool = false
) -> SolitaireBoard {
    var piles = piles
    while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
    return SolitaireBoard(tableau: piles, foundations: foundations,
                          stock: stock, waste: waste, jokerAvailable: joker)
}

private let s = SolitaireSuit.spade
private let h = SolitaireSuit.heart
private let d = SolitaireSuit.diamond
private let c = SolitaireSuit.club

@Suite("クロンダイクのルール")
struct SolitaireBoardRuleTests {

    @Test("場札は降順・交互色にだけ積める")
    func tableauStacking() {
        let b = board([pile(up: [SolitaireCard(s, 8)]), pile(up: [SolitaireCard(h, 7)]),
                       pile(up: [SolitaireCard(c, 7)])])
        #expect(b.canPlace([SolitaireCard(h, 7)], onPile: 0))       // 黒8 に 赤7
        #expect(!b.canPlace([SolitaireCard(c, 7)], onPile: 0))      // 同色は不可
        #expect(!b.canPlace([SolitaireCard(h, 6)], onPile: 0))      // ランクが飛ぶのは不可
    }

    @Test("空列には K だけ置ける")
    func emptyColumnTakesOnlyKing() {
        let b = board([pile(up: [SolitaireCard(s, 5)])])
        #expect(b.canPlace([SolitaireCard(h, 13)], onPile: 1))
        #expect(!b.canPlace([SolitaireCard(h, 12)], onPile: 1))
    }

    @Test("組札は同スートで A から昇順にだけ積める")
    func foundationOrder() {
        var b = board([pile(up: [SolitaireCard(s, 1)])])
        #expect(b.canSendToFoundation(SolitaireCard(s, 1)))
        #expect(!b.canSendToFoundation(SolitaireCard(s, 2)))
        b.apply(.tableauToFoundation(pile: 0))
        #expect(b.foundations[s.rawValue] == 1)
        #expect(b.canSendToFoundation(SolitaireCard(s, 2)))
        #expect(!b.canSendToFoundation(SolitaireCard(h, 2)))
    }

    @Test("表向きが無くなった列は伏せ札を1枚めくる")
    func flipsFaceDownCard() {
        var b = board([pile(down: [SolitaireCard(d, 4)], up: [SolitaireCard(s, 1)])])
        b.apply(.tableauToFoundation(pile: 0))
        #expect(b.tableau[0].faceDown.isEmpty)
        #expect(b.tableau[0].top == SolitaireCard(d, 4))
    }

    @Test("正規の連続列は丸ごと動かせる")
    func movesWholeRun() {
        var b = board([
            pile(down: [SolitaireCard(d, 4)],
                 up: [SolitaireCard(s, 9), SolitaireCard(h, 8), SolitaireCard(c, 7)]),
            pile(up: [SolitaireCard(d, 10)]),
        ])
        #expect(b.isMovableRun(pile: 0, from: 0))
        b.apply(.tableauToTableau(from: 0, cardIndex: 0, to: 1))
        #expect(b.tableau[1].faceUp.count == 4)
        #expect(b.tableau[0].top == SolitaireCard(d, 4))   // 伏せ札がめくれる
    }

    @Test("山札は1枚ずつめくり、尽きたら捨て札が戻って循環する")
    func stockRecycles() {
        var b = board([pile(up: [SolitaireCard(s, 5)])],
                      stock: [SolitaireCard(h, 2), SolitaireCard(d, 3)])   // last = ♦3 が先
        b.apply(.draw)
        #expect(b.waste.last == SolitaireCard(d, 3))
        b.apply(.draw)
        #expect(b.waste.last == SolitaireCard(h, 2))
        #expect(b.stock.isEmpty)
        b.apply(.draw)                                   // 捨て札を戻してから1枚めくる
        #expect(b.waste.last == SolitaireCard(d, 3))
    }

    @Test("循環で到達できる札を、必要なめくり回数つきで列挙する")
    func enumeratesReachableStockCards() {
        let b = board([pile(up: [SolitaireCard(s, 5)])],
                      stock: [SolitaireCard(h, 2), SolitaireCard(d, 3)],
                      waste: [SolitaireCard(c, 9), SolitaireCard(s, 4)])
        let reachable = b.reachableStockCards()
        #expect(reachable.map(\.card) == [
            SolitaireCard(s, 4),   // 0 回（いま表を向いている）
            SolitaireCard(d, 3),   // 1 回
            SolitaireCard(h, 2),   // 2 回
            SolitaireCard(c, 9),   // 3 回（捨て札を戻してから）
        ])
        #expect(reachable.map(\.draws) == [0, 1, 2, 3])
        // 山札 + 捨て札の全枚数がちょうど1周で出てくる（重複も取りこぼしも無い）。
        #expect(Set(reachable.map(\.card.id)).count == b.stock.count + b.waste.count)
    }
}

@Suite("ジョーカー（中継札）")
struct SolitaireJokerTests {

    @Test("ジョーカーは場札の上にだけ置ける（空列・組札には置けない）")
    func jokerPlacement() {
        let b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        #expect(b.canPlaceJoker(onPile: 0))
        #expect(!b.canPlaceJoker(onPile: 1))                       // 空列は不可（吟味1の確定）
        #expect(!b.canPlace([SolitaireCard.joker], onPile: 0))     // 通常の積み手としても置けない
        #expect(!b.canSendToFoundation(SolitaireCard.joker))
    }

    @Test("所持していなければ置けず、置くと所持は空になる")
    func jokerIsConsumed() {
        var b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        #expect(!b.jokerAvailable)
        #expect(!b.canPlaceJoker(onPile: 0))
    }

    @Test("ジョーカーの上には任意のカードを1枚だけ置け、その先は通常ルールに戻る")
    func jokerAcceptsAnySingleCard() {
        var b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(d, 3)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        // 色もランクも無関係に1枚だけ乗る。
        #expect(b.canPlace([SolitaireCard(d, 3)], onPile: 0))
        // 2枚以上の連続列は乗らない。
        #expect(!b.canPlace([SolitaireCard(d, 3), SolitaireCard(s, 2)], onPile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))
        #expect(b.tableau[0].faceUp.map(\.label) == ["♠5", "JOKER", "♦3"])
        // その先は通常ルール（♦3 の上は黒2 のみ）。
        #expect(b.canPlace([SolitaireCard(s, 2)], onPile: 0))
        #expect(!b.canPlace([SolitaireCard(h, 2)], onPile: 0))
    }

    @Test("ジョーカーを含む並びは動かせない（置いたジョーカーは動かない）")
    func jokerCannotBeMoved() {
        var b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(d, 4)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))    // ♠5, JOKER, ♦4
        #expect(!b.isMovableRun(pile: 0, from: 1))                  // JOKER から下は動かせない
        #expect(b.isMovableRun(pile: 0, from: 2))                   // その上の ♦4 だけなら動かせる
    }

    @Test("受け取り済みのジョーカーは露出した瞬間に消え、下の札が使えるようになる")
    func consumedJokerVanishesWhenExposed() {
        var b = board([pile(up: [SolitaireCard(s, 5)]),
                       pile(up: [SolitaireCard(d, 4)]),
                       pile(up: [SolitaireCard(c, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))    // ♠5, JOKER, ♦4
        #expect(b.tableau[0].faceUp.count == 3)
        b.apply(.tableauToTableau(from: 0, cardIndex: 2, to: 2))    // ♦4 を ♣5 の上へ退かす
        #expect(b.tableau[0].faceUp.map(\.label) == ["♠5"])         // JOKER は消滅
        #expect(b.tableau[0].top == SolitaireCard(s, 5))            // 下の札が再び使える
    }

    @Test("まだ何も受け取っていないジョーカーは露出したままでも消えない")
    func pendingJokerStays() {
        var b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        #expect(b.tableau[0].top?.isJoker == true)
    }
}

@Suite("詰み検知")
struct SolitaireDeadEndTests {

    @Test("動かせる手が1つも無ければ詰み")
    func detectsDeadEnd() {
        // 山札も捨て札も空、場札は互いに積めない2列だけ。
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])])
        #expect(b.isDeadEnd)
    }

    @Test("山札に使える札があれば詰みではない")
    func stockKeepsGameAlive() {
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])],
                      stock: [SolitaireCard(h, 4)])
        #expect(!b.isDeadEnd)
    }

    @Test("空列どうしの入れ替えしか無い状態は詰みとみなす")
    func emptyColumnShuffleIsNotProgress() {
        let b = board([pile(up: [SolitaireCard(s, 13)])])   // ♠K 単独 + 空列6本
        #expect(b.isDeadEnd)
    }

    @Test("ジョーカーを所持していても詰みの判定は変わらない")
    func jokerIsExcludedFromDeadEndCheck() {
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])], joker: true)
        #expect(b.isDeadEnd)
    }

    @Test("クリア済みの盤面は詰みではない")
    func wonBoardIsNotDeadEnd() {
        let b = board([], foundations: [13, 13, 13, 13])
        #expect(b.isWon)
        #expect(!b.isDeadEnd)
    }

    /// #475（会長QA）の受け入れ条件1・2。**同じ「K→空列」でも、伏せ札の有無で意味が正反対**になる。
    @Test("K→空列は伏せ札がめくれるなら有効手、移動元が空になるなら入れ替えにすぎない")
    func kingToEmptyColumnDependsOnFaceDown() {
        // 移動元に伏せ札がある = K を退かせば1枚めくれる → 詰みではない
        let revealing = board([pile(down: [SolitaireCard(c, 7)], up: [SolitaireCard(s, 13)]),
                               pile(up: [SolitaireCard(h, 9)])])
        #expect(!revealing.isDeadEnd)

        // 伏せ札が無い = 移動元も空になるので、列を入れ替えただけ → 詰みのまま
        let swapping = board([pile(up: [SolitaireCard(s, 13)]), pile(up: [SolitaireCard(h, 9)])])
        #expect(swapping.isDeadEnd)
    }

    /// #475 の起票時の見立て（「K→空列を除外するのは1手先しか見ておらず、移動後に別列の札を
    /// 載せられるケースを見落とす」）を**反証したまま固定する**ためのテスト。
    ///
    /// 伏せ札なしの K 連なりを空列へ移すと移動元も空になるため、移動後の盤面は移動前の
    /// **列を入れ替えただけ**になる。合法手は列の並び順に依存しないので、この手で新しい手が
    /// 生まれることは原理上ありえない。1局面の手組みでは「たまたま無かった」と区別できないので、
    /// K + 空列の形をランダムに大量生成し、詰みと判定した盤面から**実際に局面が進む手順**
    /// （伏せ札がめくれる / 組札が増える）が無いことを総当たりで確かめる。
    @Test("K→空列が残る詰み局面に、実際に局面を進める手順は存在しない")
    func deadEndWithKingToEmptyColumnHasNoHiddenProgress() {
        var rng = SeededRNG(seed: 0x5011_7A18)
        var deadEnds = 0
        var withKingMove = 0
        var loneKing = 0
        var kingRun = 0
        for _ in 0..<8_000 {
            let b = randomKingAndEmptyColumnBoard(using: &rng)
            guard b.isDeadEnd else { continue }
            deadEnds += 1
            if b.tableau.indices.contains(where: {
                b.tableau[$0].isEmpty && b.isLegal(.tableauToTableau(from: 0, cardIndex: 0, to: $0))
            }) {
                withKingMove += 1
                if b.tableau[0].faceUp.count == 1 { loneKing += 1 } else { kingRun += 1 }
            }
            #expect(progressSequence(from: b, depth: 4) == nil,
                    "詰みと判定した盤面に進む手順があった:\n\(b.tableau.map(\.debugText).joined(separator: "\n"))")
        }
        // 母集団が痩せると上の #expect は素通りする。**「詰みと判定したのに K を空列へ置く手が
        // 残っている」= 会長が見た形**が十分な数だけ含まれていることまで確かめる。
        #expect(deadEnds > 500)
        #expect(withKingMove == deadEnds)
        // 単独の K と**複数枚の連なり**の両方を踏むこと。片方だけだと、除外条件を
        // 「1枚のときだけ」に狭める退行を素通りさせる（verifier の指摘・2026-09-07）。
        #expect(loneKing > 100)
        #expect(kingRun > 100)
    }
}

// MARK: - #475 の反証に使う道具

/// 種を固定した乱数（SplitMix64）。CI で毎回同じ盤面を引くために標準の乱数は使わない。
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension SolitairePile {
    var debugText: String { "down=\(faceDown.map(\.label)) up=\(faceUp.map(\.label))" }
}

/// 「K を先頭にした連なりの列 + 空列」を必ず含む小さい盤面をランダムに作る（#475 の観測と同じ形）。
///
/// **K を単独札にしてはいけない**。除外条件は連なりの長さを問わないので、単独の K しか作らないと
/// 「複数枚の連なりを空列へ移す」分岐を一度も踏まず、そこを狭める退行を検知できない
/// （verifier の指摘・2026-09-07。`run.count == 1` を条件に足す変異が緑のまま通った）。
private func randomKingAndEmptyColumnBoard(using rng: inout SeededRNG) -> SolitaireBoard {
    // K を下端にした降順・交互色の連なり（長さ1〜4）。
    let runLength = Int.random(in: 1...4, using: &rng)
    let kingIsRed = Bool.random(using: &rng)
    let run = (0..<runLength).map { step -> SolitaireCard in
        let isRed = (step % 2 == 0) == kingIsRed
        return SolitaireCard(isRed ? .heart : .spade, 13 - step)
    }

    var deck: [SolitaireCard] = []
    let runIDs = Set(run.map(\.id))
    for suit in SolitaireSuit.allCases {
        for rank in 1...13 where !runIDs.contains(SolitaireCard(suit, rank).id) {
            deck.append(SolitaireCard(suit, rank))
        }
    }
    deck.shuffle(using: &rng)

    var index = 0
    // K の下に伏せ札がある形も母集団に入れる（こちらは「退かせば1枚めくれる」= 有効手）。
    var piles: [SolitairePile] = []
    if Bool.random(using: &rng) {
        piles.append(SolitairePile(faceDown: [deck[index]], faceUp: run))
        index += 1
    } else {
        piles.append(SolitairePile(faceUp: run))
    }
    for _ in 0..<Int.random(in: 1...4, using: &rng) {
        let size = Int.random(in: 1...3, using: &rng)
        let taken = Array(deck[index..<(index + size)])
        index += size
        // 伏せ札を1枚持つ列を混ぜる（「めくれる余地」がある盤面も母集団に入れる）。
        if size >= 2, Bool.random(using: &rng) {
            piles.append(SolitairePile(faceDown: [taken[0]], faceUp: Array(taken.dropFirst())))
        } else {
            piles.append(SolitairePile(faceUp: taken))
        }
    }
    // 7列に足りない分を空列で埋める。**ここを忘れると空列が1本も無い盤面になり、
    // 「K→空列」を一度も試さないままテストが緑になる**（実際に一度そうなった）。
    while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
    let stockSize = Int.random(in: 0...3, using: &rng)
    return SolitaireBoard(tableau: piles, stock: Array(deck[index..<(index + stockSize)]))
}

/// ジョーカーと山めくりを除く合法手（`isDeadEnd` が数える範囲と揃える）。
private func legalMoves(_ b: SolitaireBoard) -> [SolitaireMove] {
    var moves: [SolitaireMove] = []
    if b.isLegal(.wasteToFoundation) { moves.append(.wasteToFoundation) }
    for pile in b.tableau.indices {
        if b.isLegal(.wasteToTableau(pile: pile)) { moves.append(.wasteToTableau(pile: pile)) }
        if b.isLegal(.tableauToFoundation(pile: pile)) { moves.append(.tableauToFoundation(pile: pile)) }
        for index in b.tableau[pile].faceUp.indices {
            for target in b.tableau.indices where target != pile {
                let move = SolitaireMove.tableauToTableau(from: pile, cardIndex: index, to: target)
                if b.isLegal(move) { moves.append(move) }
            }
        }
    }
    return moves
}

/// `depth` 手以内に「伏せ札がめくれる / 組札が増える」手順があれば返す。無ければ nil。
private func progressSequence(from start: SolitaireBoard, depth: Int) -> [SolitaireMove]? {
    func measure(_ b: SolitaireBoard) -> (foundations: Int, faceDown: Int) {
        (b.foundations.reduce(0, +), b.tableau.reduce(0) { $0 + $1.faceDown.count })
    }
    let base = measure(start)
    var seen: Set<Data> = [start.stateKey]
    var stack: [(SolitaireBoard, [SolitaireMove])] = [(start, [])]
    while let (board, path) = stack.popLast() {
        guard path.count < depth else { continue }
        for move in legalMoves(board) {
            var next = board
            next.apply(move)
            guard seen.insert(next.stateKey).inserted else { continue }
            let score = measure(next)
            if score.foundations > base.foundations || score.faceDown < base.faceDown {
                return path + [move]
            }
            stack.append((next, path + [move]))
        }
    }
    return nil
}
