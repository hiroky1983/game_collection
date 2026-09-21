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

@Suite("玉への攻め駒の接近（#1258）")
struct KingDangerTests {
    private let engine = SimpleMinimaxEngine(level: 1)

    @Test func startPositionHasNoDanger() {
        let pos = Position.start()
        #expect(engine.kingDanger(pos, .black) == 0)
        #expect(engine.kingDanger(pos, .white) == 0)
    }

    @Test func twoAttackersNearKingAreDangerousButOneIsNot() {
        // 先手玉 5九 に対し、後手の銀が距離2に2枚（棒銀・早繰り銀の形）／1枚だけ。
        let two = Position.fromSFEN("4k4/9/9/9/9/9/2s3s2/9/4K4 b - 1")!
        let one = Position.fromSFEN("4k4/9/9/9/9/9/2s6/9/4K4 b - 1")!
        #expect(engine.kingDanger(two, .black) > 0)
        #expect(engine.kingDanger(one, .black) == 0)
        // 近いほど危険（距離2 → 距離1）
        let closer = Position.fromSFEN("4k4/9/9/9/9/9/9/3s1s3/4K4 b - 1")!
        #expect(engine.kingDanger(closer, .black) > engine.kingDanger(two, .black))
    }

    @Test func dangerIgnoresFarAttackers() {
        let far = Position.fromSFEN("4k4/9/9/s6s1/9/9/9/9/4K4 b - 1")!
        #expect(engine.kingDanger(far, .black) == 0)
    }

    @Test func promotedBishopIsWorthLessThanPromotedRook() {
        // 馬 < 龍、かつ 馬 > 飛（成り駒の駒割を定説の並びに、#1258）
        let horse = PieceValue.onBoard(Piece(type: .bishop, color: .black, promoted: true))
        let dragon = PieceValue.onBoard(Piece(type: .rook, color: .black, promoted: true))
        let rook = PieceValue.onBoard(Piece(type: .rook, color: .black, promoted: false))
        #expect(rook < horse && horse < dragon)
    }
}

@Suite("玉頭の歩の盾と開いた筋（#1258 段階4）")
struct KingPawnShieldTests {
    private let engine = SimpleMinimaxEngine(level: 1)

    private func shield(_ sfen: String, _ color: Side = .black) -> Int {
        let pos = Position.fromSFEN(sfen)!
        return engine.kingPawnShield(pos, color)
    }

    @Test func pawnsInFrontOfKingScoreHigherThanNone() {
        let withPawns = shield("4k4/9/9/9/9/9/3PPP3/9/4K4 b - 1")
        let without = shield("4k4/9/9/9/9/9/9/9/4K4 b - 1")
        #expect(withPawns > without)
    }

    @Test func pawnFarAheadDoesNotShield() {
        let near = shield("4k4/9/9/9/9/9/4P4/9/4K4 b - 1")
        let far = shield("4k4/9/9/9/4P4/9/9/9/4K4 b - 1")
        #expect(near > far)
    }

    @Test func openFileIsWorseWhenOpponentHasRook() {
        let noRook = shield("4k4/9/9/9/9/9/9/9/4K4 b - 1")
        let withRook = shield("4k4/9/9/9/9/9/9/9/4K4 b r 1")
        #expect(withRook < noRook)
    }

    @Test func whiteSideIsMirrored() {
        // 後手玉 5一 の前方（rank が増える向き）に歩があれば盾になる／遠い歩は盾にならない
        let near = shield("4k4/4p4/9/9/9/9/9/9/4K4 w - 1", .white)
        let far = shield("4k4/9/9/9/4p4/9/9/9/4K4 w - 1", .white)
        #expect(near > far)
    }
}
