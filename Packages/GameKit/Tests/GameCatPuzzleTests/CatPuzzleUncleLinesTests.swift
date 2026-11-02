import Testing
@testable import GameCatPuzzle

@Suite("おじさんちのねこさがし: 終局のおじさんの一言")
struct CatPuzzleUncleLinesTests {
    private func clear(_ n: Int, mistakes: Int = 1, isKey: Bool = false, newBoard: Bool = false, side: Int = 6, previous: String? = nil) -> String {
        CatPuzzleUncleLines.clear(number: n, mistakes: mistakes, isKey: isKey, entersNewBoard: newBoard, side: side, previous: previous)
    }

    @Test("条件つきが通常より優先され、条件が無ければ通常の 12 種から選ぶ")
    func conditionsTakePriority() {
        #expect(CatPuzzleUncleLines.clearNormal.contains(clear(3)))
        #expect(CatPuzzleUncleLines.clearNoMiss.contains(clear(3, mistakes: 0)))
        #expect(clear(10, isKey: true) == CatPuzzleUncleLines.clearKey)
        #expect(clear(11, newBoard: true) == CatPuzzleUncleLines.clearNewBoard)
        #expect(clear(40, side: 10) == CatPuzzleUncleLines.clearBig)
        #expect(clear(11, mistakes: 0, isKey: true, newBoard: true, side: 11) == CatPuzzleUncleLines.clearNewBoard)
    }

    @Test("同じ面・同じ条件なら同じ一言になる")
    func deterministicPerNumber() {
        for n in 1...40 {
            #expect(clear(n) == clear(n))
            #expect(CatPuzzleUncleLines.failed(number: n, previous: nil) == CatPuzzleUncleLines.failed(number: n, previous: nil))
        }
    }

    @Test("連続した面で同じ一言が続かない（条件が毎回合う 10×10 以上のノーミスでも）")
    func neverRepeatsInARow() {
        var previous: String?
        for n in 1...200 {
            let line = clear(n, mistakes: n % 3 == 0 ? 0 : 1, side: n > 50 ? 10 : 6, previous: previous)
            #expect(line != previous)
            previous = line
        }
        previous = nil
        for n in 1...100 {
            let line = CatPuzzleUncleLines.failed(number: n, previous: previous)
            #expect(line != previous)
            previous = line
        }
        // 自由に遊ぶ（通し番号が同じ値を保ったまま 2 局続く）でも、直前と同じなら替える。
        let first = clear(7)
        #expect(clear(7, previous: first) != first)
    }

    @Test("全ての一言に英訳がある")
    func everyLineHasEnglish() {
        let all = CatPuzzleUncleLines.clearNormal + CatPuzzleUncleLines.clearNoMiss + CatPuzzleUncleLines.fail
            + [CatPuzzleUncleLines.clearKey, CatPuzzleUncleLines.clearNewBoard, CatPuzzleUncleLines.clearBig]
        for key in all {
            let en = GameCatPuzzle.tr(key, language: .english)
            #expect(en != key, "\(key)")
        }
    }
}
