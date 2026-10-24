import Testing
@testable import GameShogi

@Suite("定跡ブック: 種で選ぶ（#2800）")
struct ShogiOpeningBookSeedTests {
    /// 1 手目（先手の 7六歩）のあとの後手番には、3四歩と 8四歩の 2 候補がある。

    @Test func positionWithSeveralBookMovesHasAllCandidates() throws {
        var pos = Position.start()
        pos.make(try #require(Move.fromUSI("7g7f")))
        let candidates = OpeningBook.moves(for: pos.toSFEN())
        #expect(Set(candidates) == ["3c3d", "8c8d"])
    }

    @Test func sameSeedAlwaysPicksSameMove() throws {
        var pos = Position.start()
        pos.make(try #require(Move.fromUSI("7g7f")))
        let sfen = pos.toSFEN()
        for seed in [UInt64(1), 2, 99, .max] {
            let first = OpeningBook.move(for: sfen, seed: seed)
            for _ in 0..<5 { #expect(OpeningBook.move(for: sfen, seed: seed) == first) }
        }
    }

    @Test func differentSeedsReachEveryCandidateAndStayLegal() throws {
        var pos = Position.start()
        pos.make(try #require(Move.fromUSI("7g7f")))
        let sfen = pos.toSFEN()
        let legal = Set(pos.legalMoves().map(\.usi))
        var seen = Set<String>()
        for seed in UInt64(0)..<64 {
            let usi = try #require(OpeningBook.move(for: sfen, seed: seed))
            #expect(legal.contains(usi))
            seen.insert(usi)
        }
        #expect(seen == Set(OpeningBook.moves(for: sfen)))
    }

    @Test func noSeedKeepsFirstRegisteredMove() throws {
        #expect(OpeningBook.move(for: Position.startSFEN) == OpeningBook.moves(for: Position.startSFEN).first)
    }

    @Test func engineWithSeedPlaysOneOfTheBookMoves() async throws {
        var pos = Position.start()
        pos.make(try #require(Move.fromUSI("7g7f")))
        let sfen = pos.toSFEN()
        let engine = SimpleMinimaxEngine(level: 2, seed: 7)
        let usi = await engine.bestMove(sfen: sfen)
        #expect(usi == OpeningBook.move(for: sfen, seed: 7))
    }
}
