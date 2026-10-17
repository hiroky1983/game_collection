import Testing
import CoreEngine
@testable import GameMancala

/// 盤を 14 個の置き場の並び（南の穴 0〜5・南のストア・北の穴 0〜5・北のストア）で作る。
private func board(_ south: [Int], _ southStore: Int, _ north: [Int], _ northStore: Int) -> MancalaBoard {
    MancalaBoard(slots: south + [southStore] + north + [northStore])
}

@Suite("マンカラのルール")
struct MancalaRulesTests {
    @Test("初期配置は各穴 4 個・ストア 0 で、種は 48 個")
    func initialBoard() {
        let b = MancalaBoard()
        #expect(b.slots == [4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(MancalaRules.isConsistent(b))
        #expect(MancalaRules.legalMoves(board: b, side: .south) == [0, 1, 2, 3, 4, 5])
        #expect(!MancalaRules.isGameOver(b))
    }

    @Test("種は右どなりから 1 個ずつまき、まいた穴は空になる")
    func sowing() {
        let r = MancalaRules.apply(pit: 0, side: .south, to: MancalaBoard())
        #expect(r.board.slots == [0, 5, 5, 5, 5, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(r.lastSlot == 4)
        #expect(!r.extraTurn && r.captured == 0 && !r.gameEnded)
    }

    @Test("最後の 1 個が自分のストアに入ると、もう一度打てる")
    func extraTurn() {
        let r = MancalaRules.apply(pit: 2, side: .south, to: MancalaBoard())
        #expect(r.lastSlot == MancalaBoard.storeIndex(.south))
        #expect(r.extraTurn)
        #expect(r.board.store(.south) == 1)
        // 北も同じ（北の 2 番目の穴 = 添字 9 から 4 個で北のストア）。
        let n = MancalaRules.apply(pit: 2, side: .north, to: MancalaBoard())
        #expect(n.lastSlot == MancalaBoard.storeIndex(.north) && n.extraTurn)
    }

    @Test("自分のストアには入れ、相手のストアは飛ばす")
    func skipsOpponentStore() {
        // 南の右端に 10 個: 南のストア → 北の 6 穴 → 北のストアを飛ばして南の 0・1・2 へ。
        let b = board([1, 1, 1, 0, 0, 10], 0, [2, 2, 2, 2, 2, 2], 23)
        let r = MancalaRules.apply(pit: 5, side: .south, to: b)
        #expect(r.board.store(.north) == 23, "相手のストアには入れない")
        #expect(r.board.store(.south) == 1)
        #expect(r.lastSlot == 2)
        #expect(Array(r.board.slots[0...2]) == [2, 2, 2])
        #expect(Array(r.board.slots[7...12]) == [3, 3, 3, 3, 3, 3])
        #expect(r.captured == 0)
        #expect(MancalaRules.isConsistent(r.board))
        // 北から見ても同じ（南のストアを飛ばす）。
        let nb = board([2, 2, 2, 2, 2, 2], 23, [1, 1, 1, 0, 0, 10], 0)
        let nr = MancalaRules.apply(pit: 5, side: .north, to: nb)
        #expect(nr.board.store(.south) == 23 && nr.board.store(.north) == 1)
        #expect(nr.lastSlot == 9 && nr.captured == 0)
    }

    @Test("13 個まくと 1 周してまいた穴に戻る（空になった自分の穴へ入っても 1 個以上なら取りにならない）")
    func fullLap() {
        let b = board([13, 1, 1, 1, 1, 1], 0, [2, 2, 2, 2, 2, 2], 18)
        let r = MancalaRules.apply(pit: 0, side: .south, to: b)
        // 13 個: 1〜5・ストア・北 6 つ（7 + 6 = 12 個）で、北のストアを飛ばして 0 に戻る。
        #expect(r.lastSlot == 0)
        #expect(r.board.slots[0] == 0, "空にした穴へ 1 個戻り、向かいの 3 個と一緒に取った")
        #expect(r.captured == 3)
        #expect(MancalaRules.isConsistent(r.board))
    }

    @Test("最後の 1 個が自分の空の穴に入り、向かいに種があれば両方をストアへ取る")
    func capture() {
        let b = board([1, 0, 3, 3, 3, 3], 5, [3, 3, 3, 3, 6, 3], 9)
        // 南の穴 0 の 1 個 → 穴 1（空）。向かいは北の添字 11（= 北の穴 4）の 6 個。
        #expect(MancalaBoard.oppositeIndex(1) == 11)
        let r = MancalaRules.apply(pit: 0, side: .south, to: b)
        #expect(r.captured == 6)
        #expect(r.board.store(.south) == 5 + 6 + 1)
        #expect(r.board.slots[1] == 0 && r.board.slots[11] == 0)
        #expect(!r.extraTurn)
        #expect(MancalaRules.isConsistent(r.board))
    }

    @Test("向かいが空なら取らない。相手の側の空の穴に入っても取らない")
    func noCapture() {
        let b = board([1, 0, 3, 3, 3, 3], 5, [3, 3, 3, 3, 0, 9], 6)
        let r = MancalaRules.apply(pit: 0, side: .south, to: b)
        #expect(r.captured == 0)
        #expect(r.board.slots[1] == 1, "向かいが空なら最後の 1 個はその穴に残る")
        #expect(r.board.store(.south) == 5)
        // 相手の側の空の穴に最後の 1 個が入る並び（南の右端 2 個 → ストア・北の 0 番目）。
        let c = board([3, 3, 3, 3, 3, 2], 5, [0, 3, 3, 3, 3, 3], 9)
        let cr = MancalaRules.apply(pit: 5, side: .south, to: c)
        #expect(cr.lastSlot == 7 && cr.captured == 0 && cr.board.slots[7] == 1)
    }

    @Test("片側の穴がすべて空になったら終局し、残った種はそれぞれのストアへ入る")
    func gameEndSweeps() {
        // 南の最後の 1 個がストアに入って南の穴が空になる。北の穴の 10 個は北のストアへ。
        let b = board([0, 0, 0, 0, 0, 1], 20, [2, 2, 2, 2, 1, 1], 17)
        let r = MancalaRules.apply(pit: 5, side: .south, to: b)
        #expect(r.gameEnded)
        #expect(!r.extraTurn, "終局した手ではもう一度にならない")
        #expect(r.board.store(.south) == 21 && r.board.store(.north) == 27)
        #expect(r.board.pitTotal(.south) == 0 && r.board.pitTotal(.north) == 0)
        #expect(MancalaRules.winner(of: r.board) == .north)
    }

    @Test("相手の穴を空にする手でも終局する（取りで相手側が空になる）")
    func gameEndsWhenOpponentEmptied() {
        let b = board([1, 0, 5, 5, 5, 5], 10, [0, 0, 0, 0, 3, 0], 14)
        let r = MancalaRules.apply(pit: 0, side: .south, to: b)
        #expect(r.captured == 3)
        #expect(r.gameEnded)
        #expect(r.board.store(.south) == 10 + 4 + 20)
        #expect(MancalaRules.winner(of: r.board) == .south)
    }

    @Test("同数は引き分け")
    func draw() {
        #expect(MancalaRules.winner(of: board([0, 0, 0, 0, 0, 0], 24, [0, 0, 0, 0, 0, 0], 24)) == nil)
    }

    @Test("壊れた盤（置き場の数・負の数・種の総数）は整合しない")
    func consistency() {
        #expect(!MancalaRules.isConsistent(MancalaBoard(slots: [4, 4, 4])))
        var b = MancalaBoard(); b.slots[0] = -1; b.slots[1] = 9
        #expect(!MancalaRules.isConsistent(b))
        var c = MancalaBoard(); c.slots[0] = 5
        #expect(!MancalaRules.isConsistent(c))
    }

    @Test("空の穴・範囲外の穴は打てない")
    func illegal() {
        let b = board([0, 4, 4, 4, 4, 4], 4, [4, 4, 4, 4, 4, 4], 0)
        #expect(!MancalaRules.isLegal(pit: 0, board: b, side: .south))
        #expect(!MancalaRules.isLegal(pit: 6, board: b, side: .south))
        #expect(!MancalaRules.isLegal(pit: -1, board: b, side: .south))
        #expect(MancalaRules.legalMoves(board: b, side: .south) == [1, 2, 3, 4, 5])
    }

    @Test("無作為な 200 局: どの手のあとも種は 48 個のまま、手番は必ず決着する")
    func randomGamesConserveSeeds() {
        var rng = SplitMix64(seed: 2026)
        for _ in 0..<200 {
            var b = MancalaBoard()
            var side = MancalaSide.south
            var plies = 0
            while true {
                let moves = MancalaRules.legalMoves(board: b, side: side)
                #expect(!moves.isEmpty, "終局していない盤では、手番の側に必ず打てる穴がある")
                guard !moves.isEmpty else { break }
                let r = MancalaRules.apply(pit: moves[Int(rng.next() % UInt64(moves.count))], side: side, to: b)
                b = r.board
                #expect(MancalaRules.isConsistent(b))
                plies += 1
                if r.gameEnded {
                    #expect(MancalaRules.isGameOver(b))
                    #expect(b.store(.south) + b.store(.north) == MancalaBoard.totalSeeds)
                    break
                }
                #expect(!MancalaRules.isGameOver(b))
                side = r.extraTurn ? side : side.opponent
                #expect(plies < 400)
                if plies >= 400 { break }
            }
        }
    }
}
