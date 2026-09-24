import Testing
@testable import GameBackgammon

/// 添字は 0 = 1 ポイント。白は添字が減る向き、黒は増える向きに進む。
private func board(_ white: [Int: Int], _ black: [Int: Int], bar: [Int] = [0, 0], off: [Int] = [0, 0]) -> BackgammonBoard {
    var p = Array(repeating: 0, count: 24)
    for (i, n) in white { p[i] = n }
    for (i, n) in black { p[i] = -n }
    return BackgammonBoard(points: p, bar: bar, off: off)
}

@Suite("バックギャモンの盤")
struct BackgammonBoardTests {
    @Test("初期配置は 15 個ずつで、ピップは 167")
    func initialPosition() {
        let b = BackgammonBoard()
        #expect(BackgammonRules.isConsistent(b))
        #expect(b.pipCount(.white) == 167)
        #expect(b.pipCount(.black) == 167)
        #expect(b.owner(at: 23) == .white && b.count(at: 23) == 2)
        #expect(b.owner(at: 0) == .black && b.count(at: 0) == 2)
        #expect(!b.canBearOff(.white))
    }

    @Test("ベアオフは全駒が自陣に入り、バーが空のときだけ")
    func bearOffCondition() {
        // 白 15 個すべてが 1〜6 ポイント。
        let home = board([0: 3, 1: 3, 2: 3, 3: 2, 4: 2, 5: 2], [23: 15])
        #expect(home.canBearOff(.white))
        #expect(home.canBearOff(.black))
        var outside = home
        outside.points[5] -= 1; outside.points[6] += 1
        #expect(!outside.canBearOff(.white))
        var onBar = home
        onBar.points[0] -= 1; onBar.bar[0] = 1
        #expect(!onBar.canBearOff(.white))
    }

    @Test("決着の種類: 相手のあがりが 0 ならギャモン、さらにバーか勝者の自陣に残っていればバックギャモン")
    func winKinds() {
        let single = board([:], [20: 15], off: [15, 0])
        #expect(single.winKind(winner: .white) == .gammon, "相手のあがりが 0 個")
        let plain = board([:], [20: 14], off: [15, 1])
        #expect(plain.winKind(winner: .white) == .single)
        let inHome = board([:], [3: 1, 20: 14], off: [15, 0])
        #expect(inHome.winKind(winner: .white) == .backgammon, "白の自陣（1〜6 ポイント）に黒が残っている")
        let onBar = board([:], [20: 14], bar: [0, 1], off: [15, 0])
        #expect(onBar.winKind(winner: .white) == .backgammon)
        // 黒が勝者のときは黒の自陣 = 添字 18〜23。
        let blackWins = board([20: 1, 3: 14], [:], off: [0, 15])
        #expect(blackWins.winKind(winner: .black) == .backgammon)
    }
}

@Suite("バックギャモンの移動ルール")
struct BackgammonRulesTests {
    @Test("相手の駒が 2 個以上あるポイントには止まれず、1 個なら叩く")
    func blockingAndHitting() {
        let b = board([12: 1], [8: 2, 9: 1])
        #expect(BackgammonRules.move(from: 12, die: 4, board: b, side: .white) == nil, "8 は黒が 2 個で止まれない")
        let hit = BackgammonRules.move(from: 12, die: 3, board: b, side: .white)
        #expect(hit?.hits == true && hit?.to == 9)
        let after = BackgammonRules.apply(hit!, to: b, side: .white)
        #expect(after.points[9] == 1 && after.bar(for: .black) == 1)
        #expect(BackgammonRules.isConsistent(after) == false, "この盤は 15 個ずつではないので整合性は見ない")
    }

    @Test("バーに駒があるあいだは入場しか許されない。入場先は白が 24 − 目、黒が目 − 1")
    func barEntry() {
        var b = BackgammonBoard()
        b.points[12] -= 1; b.bar[0] = 1
        let moves = BackgammonRules.legalMoves(board: b, side: .white, dice: [3, 5])
        #expect(!moves.isEmpty)
        #expect(moves.allSatisfy { $0.from == BackgammonBoard.bar })
        #expect(Set(moves.map(\.to)) == [21, 19])
        // 黒が 19〜24 を閉じていれば入れない = 動かせない。
        let closed = board([12: 4, 7: 3, 5: 5, 4: 2], [18: 3, 19: 3, 20: 3, 21: 2, 22: 2, 23: 2], bar: [1, 0])
        #expect(BackgammonRules.isConsistent(closed))
        #expect(BackgammonRules.legalMoves(board: closed, side: .white, dice: [1, 2]).isEmpty)
        // 黒の入場は 1〜6 ポイント（添字 目 − 1）。
        var blackBar = BackgammonBoard()
        blackBar.points[11] += 1; blackBar.bar[1] = 1
        let entry = BackgammonRules.legalMoves(board: blackBar, side: .black, dice: [2, 6])
        #expect(Set(entry.map(\.to)) == [1], "6 は白の 6 ポイント（5 個）で塞がれている")
    }

    @Test("両方の目を使える手順があるときは、片方しか使わない手は合法手に出ない")
    func mustUseBothDice() {
        // 白: 6 に 1 個、残り 14 個は 23 に（黒が 21・20 を塞いでいるので 3 でも 2 でも動けない）。
        // 黒が 4 を塞ぎ、3 と 1 は空き。目 3・2: 6→3→1 は通る。6→4 は塞がれている。
        // 3 だけ使って止まる手は禁止（2 が続けて使えるため）。
        let b = board([5: 1, 22: 14], [3: 2, 19: 2, 20: 2, 18: 9])
        #expect(BackgammonRules.isConsistent(b))
        let seqs = BackgammonRules.sequences(board: b, side: .white, dice: [3, 2])
        #expect(!seqs.isEmpty && seqs.allSatisfy { $0.count == 2 }, "\(seqs)")
        let first = BackgammonRules.legalMoves(board: b, side: .white, dice: [3, 2])
        #expect(first.count == 1 && first[0].die == 3 && first[0].to == 2, "3 を先に使わないと 2 が使えない: \(first)")
    }

    @Test("片方の目しか使えないときは大きい目を使う")
    func preferLargerDie() {
        // 白 1 個が 8 ポイント、残り 14 個は 24（黒が 22 と 19 を塞いでいるので 2 でも 5 でも動けない）。
        // 目 5・2: 8→3（5）と 8→6（2）の両方が単独では可能だが、その先が続かない
        // （8→6 の後の 6→1（5）も、8→3 の後の 3→1（2）も、黒の 1 ポイントで塞がれている）。
        let b = board([7: 1, 23: 14], [0: 2, 21: 2, 18: 11])
        #expect(BackgammonRules.isConsistent(b))
        let seqs = BackgammonRules.sequences(board: b, side: .white, dice: [5, 2])
        #expect(seqs.count == 1 && seqs[0].count == 1 && seqs[0][0].die == 5, "\(seqs)")
    }

    @Test("ゾロ目は 4 回動かせる")
    func doublesGiveFourMoves() {
        let b = BackgammonBoard()
        let seqs = BackgammonRules.sequences(board: b, side: .white, dice: BackgammonRules.dice(for: (3, 3)))
        #expect(!seqs.isEmpty)
        #expect(seqs.allSatisfy { $0.count == 4 })
        #expect(BackgammonRules.dice(for: (3, 3)) == [3, 3, 3, 3])
        #expect(BackgammonRules.dice(for: (6, 1)) == [6, 1])
    }

    @Test("ベアオフ: ちょうどの目であがれる。大きい目は一番後ろの駒だけあがれる")
    func bearingOff() {
        // 白: 6 に 2・4 に 1・1 に 12（全駒が自陣）。
        let b = board([5: 2, 3: 1, 0: 12], [23: 15])
        #expect(BackgammonRules.move(from: 5, die: 6, board: b, side: .white)?.to == BackgammonBoard.off)
        #expect(BackgammonRules.move(from: 3, die: 4, board: b, side: .white)?.to == BackgammonBoard.off)
        #expect(BackgammonRules.move(from: 3, die: 6, board: b, side: .white) == nil, "6 ポイントに駒が残っている間は 4 ポイントの駒を 6 であげられない")
        #expect(BackgammonRules.move(from: 3, die: 5, board: b, side: .white) == nil)
        // 6 ポイントの駒が無くなれば、4 ポイントの駒を 6 であげられる。
        let later = board([3: 1, 0: 12], [23: 15], off: [2, 0])
        #expect(BackgammonRules.move(from: 3, die: 6, board: later, side: .white)?.to == BackgammonBoard.off)
        // 黒のベアオフは 19〜24 から。
        let black = board([0: 15], [18: 2, 20: 1, 23: 12])
        #expect(BackgammonRules.move(from: 18, die: 6, board: black, side: .black)?.to == BackgammonBoard.off)
        #expect(BackgammonRules.move(from: 20, die: 6, board: black, side: .black) == nil)
    }

    @Test("あがりを適用すると off が増え、駒が 15 個そろえば勝ち")
    func applyBearOff() {
        let b = board([0: 1], [23: 15], off: [14, 0])
        let move = BackgammonRules.move(from: 0, die: 1, board: b, side: .white)!
        let after = BackgammonRules.apply(move, to: b, side: .white)
        #expect(after.off(for: .white) == 15 && after.hasWon(.white))
        #expect(BackgammonRules.isConsistent(after))
    }

    @Test("初期配置の 3・1 は 8→5・6→5 でポイントを作れる（合法手に含まれる）")
    func openingThreeOne() {
        let b = BackgammonBoard()
        let seqs = BackgammonRules.sequences(board: b, side: .white, dice: [3, 1])
        let makesFive = seqs.contains { seq in
            seq.contains(BackgammonMove(from: 7, to: 4, die: 3, hits: false))
                && seq.contains(BackgammonMove(from: 5, to: 4, die: 1, hits: false))
        }
        #expect(makesFive)
        // 手順の適用後も駒の数は保たれる。
        for seq in seqs {
            #expect(BackgammonRules.isConsistent(seq.reduce(b) { BackgammonRules.apply($1, to: $0, side: .white) }))
        }
    }
}
