import Testing
@testable import GameChess

@Suite("定跡ブック: 種で選ぶ（#2800）")
struct ChessOpeningBookSeedTests {
    private let startFEN = ChessPosition.start().toFEN()

    @Test func startPositionHasSeveralBookMoves() {
        #expect(Set(ChessOpeningBook.moves(for: startFEN)) == ["e2e4", "d2d4", "c2c4"])
    }

    @Test func sameSeedAlwaysPicksSameMove() {
        for seed in [UInt64(1), 2, 99, .max] {
            let first = ChessOpeningBook.move(for: startFEN, seed: seed)
            for _ in 0..<5 { #expect(ChessOpeningBook.move(for: startFEN, seed: seed) == first) }
        }
    }

    @Test func differentSeedsReachEveryCandidateAndStayLegal() throws {
        let legal = Set(ChessPosition.start().legalMoves().map(\.uci))
        var seen = Set<String>()
        for seed in UInt64(0)..<64 {
            let uci = try #require(ChessOpeningBook.move(for: startFEN, seed: seed))
            #expect(legal.contains(uci))
            seen.insert(uci)
        }
        #expect(seen == Set(ChessOpeningBook.moves(for: startFEN)))
    }

    @Test func noSeedKeepsFirstRegisteredMove() {
        #expect(ChessOpeningBook.move(for: startFEN) == "e2e4")
    }

    @Test func engineWithSeedPlaysTheSeededBookMove() async {
        let engine = SimpleChessEngine(level: 2, seed: 7)
        let uci = await engine.bestMove(fen: startFEN)
        #expect(uci == ChessOpeningBook.move(for: startFEN, seed: 7))
    }
}
