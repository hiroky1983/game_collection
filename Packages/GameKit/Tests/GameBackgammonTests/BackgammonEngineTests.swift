import Testing
import CoreEngine
@testable import GameBackgammon

private func board(_ white: [Int: Int], _ black: [Int: Int], bar: [Int] = [0, 0], off: [Int] = [0, 0]) -> BackgammonBoard {
    var p = Array(repeating: 0, count: 24)
    for (i, n) in white { p[i] = n }
    for (i, n) in black { p[i] = -n }
    return BackgammonBoard(points: p, bar: bar, off: off)
}

@Suite("バックギャモンの CPU")
struct BackgammonEngineTests {
    @Test("どの段階でも返す手順は合法な最大手順の 1 つ")
    func sequencesAreLegal() {
        let b = BackgammonBoard()
        for level in CPUStrength.allCases.map(\.rawValue) {
            for dice in [[3, 1], [6, 5], [4, 4, 4, 4], [2, 1]] {
                let seq = BackgammonEngine(level: level, seed: 1).bestSequence(board: b, side: .black, dice: dice)
                let legal = BackgammonRules.sequences(board: b, side: .black, dice: dice)
                #expect(legal.contains(seq), "level \(level) dice \(dice)")
            }
        }
    }

    @Test("動かせないときは空を返す")
    func noMoves() {
        // 白 1 個がバー。黒が 19〜24 をすべて閉じる（黒 15 個: 3+3+3+2+2+2）。
        let b = board([12: 4, 7: 3, 5: 5, 4: 2], [18: 3, 19: 3, 20: 3, 21: 2, 22: 2, 23: 2], bar: [1, 0])
        #expect(BackgammonRules.isConsistent(b))
        #expect(BackgammonEngine(level: 1).bestSequence(board: b, side: .white, dice: [6, 1]).isEmpty)
    }

    @Test("ふつう以上は、叩ける相手のブロットを叩く（評価値で固定）")
    func normalPrefersHit() {
        // 黒（CPU）: 1 ポイントの 2 個のうち 1 個を 4 ポイントへ。白の 6 ポイントから 1 個を 3 ポイントへ出したブロット。
        let b = board([2: 1, 5: 4, 7: 3, 12: 5, 23: 2], [0: 2, 11: 5, 16: 3, 18: 5])
        // 黒の目 2: 1 → 3 で白のブロットを叩ける。
        let hit = BackgammonMove(from: 0, to: 2, die: 2, hits: true)
        for level in [CPUStrength.normal.rawValue, CPUStrength.hard.rawValue] {
            let seq = BackgammonEngine(level: level).bestSequence(board: b, side: .black, dice: [2, 1])
            #expect(seq.contains(hit), "level \(level): \(seq)")
        }
        // 評価値でも叩いた局面のほうが高い。
        let hitBoard = BackgammonRules.apply(hit, to: b, side: .black)
        let quiet = BackgammonRules.apply(BackgammonMove(from: 11, to: 13, die: 2, hits: false), to: b, side: .black)
        #expect(BackgammonEngine.evaluate(hitBoard, for: .black) > BackgammonEngine.evaluate(quiet, for: .black))
    }

    @Test("評価はブロットを危険とみなし、ポイントを作ると上がる")
    func evaluationFeatures() {
        let initial = BackgammonBoard()
        // 白の 8 ポイントを 1 個崩して 3 ポイントへ置いた（黒の直射圏内のブロット）。
        var blot = initial
        blot.points[7] -= 1; blot.points[2] += 1
        #expect(BackgammonEngine.evaluate(blot, for: .white) < BackgammonEngine.evaluate(initial, for: .white))
        // 8 と 6 から 1 個ずつで 5 ポイントを作る（3・1 の定石）。
        var made = initial
        made.points[7] -= 1; made.points[5] -= 1; made.points[4] += 2
        #expect(BackgammonEngine.evaluate(made, for: .white) > BackgammonEngine.evaluate(initial, for: .white))
        // 対称な局面では両者の評価が打ち消し合う。
        #expect(abs(BackgammonEngine.evaluate(initial, for: .white)) < 0.001)
    }

    @Test("むずかしいは 1 手先を読み、勝てる手順があれば必ず選ぶ")
    func hardTakesTheWin() {
        // 白（CPU 役）が 1 ポイントと 6 ポイントに 1 個ずつ、他はあがり済み。目 6・1。
        // 6 で 6 ポイントの駒をあげてから 1 で 1 ポイントの駒をあげれば勝ち。
        // 1 で 6→5 と動かしてから 6 で 5 ポイントの駒をあげる手順も合法だが、1 個残って勝てない。
        let b = board([0: 1, 5: 1], [18: 15], off: [13, 0])
        for level in [CPUStrength.normal.rawValue, CPUStrength.hard.rawValue] {
            let seq = BackgammonEngine(level: level).bestSequence(board: b, side: .white, dice: [6, 1])
            #expect(seq.count == 2, "level \(level): \(seq)")
            #expect(BackgammonEngine.result(of: seq, b, .white).hasWon(.white), "level \(level): \(seq)")
        }
    }

    @Test("入門は種が同じなら同じ手順を返す（決定的）")
    func noviceIsSeeded() {
        let b = BackgammonBoard()
        let a = BackgammonEngine(level: CPUStrength.novice.rawValue, seed: 42).bestSequence(board: b, side: .black, dice: [6, 5])
        let c = BackgammonEngine(level: CPUStrength.novice.rawValue, seed: 42).bestSequence(board: b, side: .black, dice: [6, 5])
        #expect(a == c)
    }

    @Test("むずかしいの読みは初期局面のゾロ目でも実用時間で終わる")
    func hardIsFastEnough() {
        let b = BackgammonBoard()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = BackgammonEngine(level: CPUStrength.hard.rawValue).bestSequence(board: b, side: .black, dice: [4, 4, 4, 4])
        }
        #expect(elapsed < .seconds(20), "Debug ビルドでも 20 秒以内（実測 \(elapsed)）")
    }
}
