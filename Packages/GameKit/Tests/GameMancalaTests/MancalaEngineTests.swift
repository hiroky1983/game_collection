import Testing
import CoreEngine
@testable import GameMancala

private func board(_ south: [Int], _ southStore: Int, _ north: [Int], _ northStore: Int) -> MancalaBoard {
    MancalaBoard(slots: south + [southStore] + north + [northStore])
}

/// 2 つの強さで 1 局を通しで打つ。打った手がすべて合法だったかと、終局した盤を返す。
private func playOut(south: Int, north: Int, first: MancalaSide, seed: UInt64) -> (allLegal: Bool, board: MancalaBoard) {
    var rng = SplitMix64(seed: seed)
    var b = MancalaBoard()
    var side = first
    var allLegal = true
    for _ in 0..<400 {
        let level = side == .south ? south : north
        guard let pit = MancalaEngine(level: level, seed: rng.next()).bestMove(board: b, side: side) else {
            allLegal = false
            break
        }
        if !MancalaRules.isLegal(pit: pit, board: b, side: side) { allLegal = false; break }
        let r = MancalaRules.apply(pit: pit, side: side, to: b)
        b = r.board
        if r.gameEnded { break }
        side = r.extraTurn ? side : side.opponent
    }
    return (allLegal, b)
}

@Suite("マンカラの CPU")
struct MancalaEngineTests {
    @Test("段階ごとの読みの深さ（開始シートの説明と一致: でたらめ・1・4・8 手）")
    func depths() {
        #expect(MancalaEngine.depth(for: .novice) == 0)
        #expect(MancalaEngine.depth(for: .easy) == 1)
        #expect(MancalaEngine.depth(for: .normal) == 4)
        #expect(MancalaEngine.depth(for: .hard) == 8)
    }

    @Test("どの強さも合法な穴だけを選び、1 局が必ず終局する", arguments: CPUStrength.allCases)
    func legalMovesOnly(strength: CPUStrength) {
        // むずかしいは読みが深いので局数を絞る（デバッグビルドでも数秒で終わる量）。
        let games = strength == .hard ? 2 : 12
        for g in 0..<games {
            let opponent = CPUStrength.allCases[g % 3].rawValue
            let result = playOut(south: strength.rawValue, north: opponent,
                                 first: g % 2 == 0 ? .south : .north, seed: UInt64(g + 1))
            #expect(result.allLegal, "\(strength) が打てない穴を選んだ")
            #expect(MancalaRules.isGameOver(result.board), "\(strength) の局が終局していない")
            #expect(result.board.store(.south) + result.board.store(.north) == MancalaBoard.totalSeeds)
        }
    }

    @Test("打てる穴が無ければ nil、1 つだけならそれを選ぶ")
    func trivialPositions() {
        let empty = board([0, 0, 0, 0, 0, 0], 20, [4, 4, 4, 4, 4, 4], 4)
        #expect(MancalaEngine(level: 1).bestMove(board: empty, side: .south) == nil)
        let single = board([0, 0, 0, 5, 0, 0], 20, [4, 4, 4, 4, 4, 3], 4)
        for level in [-1, 0, 1, 2] {
            #expect(MancalaEngine(level: level, seed: 1).bestMove(board: single, side: .south) == 3)
        }
    }

    @Test("かんたん以上は、目の前の大きな取りを逃さない")
    func takesBigCapture() {
        // 南の穴 0 の 1 個 → 空の穴 1 → 向かい（北の穴 4 = 添字 11）の 12 個を取れる。
        let b = board([1, 0, 1, 1, 1, 3], 10, [1, 1, 1, 1, 12, 1], 14)
        #expect(MancalaRules.isConsistent(b))
        for level in [0, 1, 2] {
            #expect(MancalaEngine(level: level).bestMove(board: b, side: .south) == 0, "level \(level)")
        }
    }

    @Test("ふつう以上は、ストアに入ってもう一度打てる手を使って取りまでつなげる")
    func usesExtraTurn() {
        // 穴 5 の 1 個でストア（もう一度）→ 穴 0 の 1 個で空の穴 1 へ → 向かいの 9 個を取る。
        // いきなり穴 0 を打っても取れるが、先にストアへ 1 個入れたほうが 1 個多い。
        let b = board([1, 0, 2, 2, 2, 1], 12, [1, 1, 1, 1, 9, 1], 14)
        #expect(MancalaRules.isConsistent(b))
        for level in [1, 2] {
            #expect(MancalaEngine(level: level).bestMove(board: b, side: .south) == 5, "level \(level)")
        }
    }

    @Test("同じ局面なら同じ手（入門以外は乱数を使わない）")
    func deterministic() {
        let b = MancalaBoard()
        for level in [0, 1, 2] {
            let a = MancalaEngine(level: level, seed: 1).bestMove(board: b, side: .north)
            let c = MancalaEngine(level: level, seed: 99).bestMove(board: b, side: .north)
            #expect(a == c)
        }
    }

    @Test("強さの順: 上の段は下の段に先手・後手とも負けない")
    func strengthOrder() {
        for (strong, weak) in [(CPUStrength.easy, CPUStrength.novice), (.normal, .easy), (.hard, .normal)] {
            for first in MancalaSide.allCases {
                let b = playOut(south: strong.rawValue, north: weak.rawValue, first: first, seed: 7).board
                #expect(MancalaRules.winner(of: b) != .north, "\(strong) が \(weak) に負けた（先手 \(first)）")
            }
        }
    }
}
