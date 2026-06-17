import Testing
@testable import GameShogi

@Suite("定跡ブック")
struct OpeningBookTests {
    @Test func bookIsNonEmptyAndLegal() {
        // 構築時に非合法手は打ち切られる。初期局面は登録されているはず。
        let first = OpeningBook.move(for: Position.startSFEN)
        #expect(first != nil)
        // 登録手は初期局面の合法手。
        if let usi = first, let m = Move.fromUSI(usi) {
            #expect(Position.start().legalMoves().contains(m))
        }
    }

    @Test func strongEnginePlaysBookFromStart() async {
        let engine = SimpleMinimaxEngine(level: 2)
        let usi = await engine.bestMove(sfen: Position.startSFEN)
        #expect(usi == OpeningBook.move(for: Position.startSFEN))
    }
}

@Suite("囲い評価")
struct KingSafetyTests {
    @Test func castledKingScoresHigherThanBareKing() {
        let engine = SimpleMinimaxEngine(level: 1)
        // 玉だけ（裸玉）
        let bare = Position.fromSFEN("4k4/9/9/9/9/9/9/9/4K4 b - 1")!
        // 玉の周りに金銀を寄せた（美濃囲い風に端へ寄せた）形
        let castled = Position.fromSFEN("4k4/9/9/9/9/9/9/1SG6/1K7 b - 1")!
        let bareScore = engine.kingSafety(bare, .black)
        let castledScore = engine.kingSafety(castled, .black)
        #expect(castledScore > bareScore) // 囲うほど安全度が上がる
    }
}

@Suite("強レベル（depth3）")
struct StrongLevelTests {
    @Test func returnsLegalMoveFromNonBookPosition() async {
        // 定跡を外れた局面でも合法手を返す（探索が走る）。
        let sfen = "lnsgkgsnl/1r5b1/ppppppppp/9/9/2P6/PP1PPPPPP/1B5R1/LNSGKGSNL w - 2"
        let engine = SimpleMinimaxEngine(level: 2)
        let usi = await engine.bestMove(sfen: sfen)
        let move = usi.flatMap(Move.fromUSI)
        #expect(move != nil)
        #expect(Position.fromSFEN(sfen)!.legalMoves().contains(move!))
    }

    @Test func strongStillTakesFreeRook() async {
        let sfen = "4k4/9/9/4r4/4G4/9/9/9/4K4 b - 1"
        let engine = SimpleMinimaxEngine(level: 2)
        let usi = await engine.bestMove(sfen: sfen)
        #expect(usi == "5e5d")
    }
}
