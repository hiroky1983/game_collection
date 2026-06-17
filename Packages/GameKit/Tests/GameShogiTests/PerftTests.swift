import Testing
@testable import GameShogi

@Suite("perft（ルールエンジン検収ライン）")
struct PerftTests {
    @Test func startSFENParses() {
        let pos = Position.start()
        // 先手番・持ち駒なし・40 枚配置。
        #expect(pos.sideToMove == .black)
        #expect(pos.squares.compactMap { $0 }.count == 40)
        #expect(pos.hands[Side.black.rawValue].allSatisfy { $0 == 0 })
    }

    @Test func perftDepth1Is30() {
        #expect(Position.start().perft(1) == 30)
    }

    @Test func perftDepth2Is900() {
        #expect(Position.start().perft(2) == 900)
    }

    // depth3 公表値（成・不成を別手として数える前提）。
    @Test func perftDepth3Is25470() {
        #expect(Position.start().perft(3) == 25470)
    }
}
