import Testing
@testable import GameHomerun

/// 打席前の回数の表示（#1694）: 5 個までは点、6 以上は「×N」。回数がいくら増えても横に広がらない。
@Suite("柵越えおじさんの回数の表示")
struct HomerunCountDisplayTests {
    @Test("5 個までは点（残りの数だけ色付き）")
    func dotsUpToFive() {
        #expect(HomerunCountDisplay(allowance: 3, remaining: 2) == .dots(total: 3, lit: 2))
        #expect(HomerunCountDisplay(allowance: 5, remaining: 5) == .dots(total: 5, lit: 5))
        #expect(HomerunCountDisplay(allowance: 4, remaining: 0) == .dots(total: 4, lit: 0))
    }

    @Test("6 以上は「×残り」の数字にする（点の数が上限を超えない）")
    func numberFromSix() {
        #expect(HomerunCountDisplay(allowance: 6, remaining: 6) == .number(remaining: 6))
        #expect(HomerunCountDisplay(allowance: 12, remaining: 12) == .number(remaining: 12))
        #expect(HomerunCountDisplay(allowance: 99, remaining: 0) == .number(remaining: 0))
    }

    @Test("どの回数でも点は maxDots 個を超えない")
    func neverMoreThanMaxDots() {
        for allowance in 0...200 {
            if case .dots(let total, _) = HomerunCountDisplay(allowance: allowance, remaining: allowance) {
                #expect(total <= HomerunCountDisplay.maxDots)
            }
        }
    }
}
