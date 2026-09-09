import Testing
@testable import GameChess

/// 個別のルール。perft は「合計が合っているか」しか見ないので、
/// **何がどう合法／非合法なのか**はここで名前を付けて確かめる。
@Suite("チェスのルール")
struct RuleTests {

    private func sq(_ name: String) -> Int { ChessSquare.fromName(Substring(name))! }

    private func position(_ fen: String) -> ChessPosition {
        guard let pos = ChessPosition.fromFEN(fen) else {
            Issue.record("FEN を読めません: \(fen)")
            return ChessPosition.start()
        }
        return pos
    }

    private func moves(_ pos: ChessPosition) -> Set<String> {
        Set(pos.legalMoves().map(\.uci))
    }

    // MARK: - 座標と FEN

    @Test("マスの名前と index が対応する（a8 が左上・h1 が右下）")
    func squareNaming() {
        #expect(sq("a8") == 0)
        #expect(sq("h1") == 63)
        #expect(ChessSquare.name(0) == "a8")
        #expect(ChessSquare.name(63) == "h1")
        // a1 は暗いマス、h1 は明るいマス（実物の盤と同じ）。
        #expect(ChessSquare.isLightSquare(sq("a1")) == false)
        #expect(ChessSquare.isLightSquare(sq("h1")))
    }

    @Test("FEN の往復で文字列が変わらない")
    func fenRoundTrip() {
        for fen in [
            ChessPosition.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - c6 3 42",
        ] {
            #expect(position(fen).toFEN() == fen)
        }
    }

    // MARK: - キャスリング

    @Test("キャスリングは両側とも指せる（権利あり・間が空いている）")
    func castlingBothSides() {
        let pos = position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(moves(pos).contains("e1g1"), "キングサイド")
        #expect(moves(pos).contains("e1c1"), "クイーンサイド")
    }

    @Test("キャスリングでルークも一緒に動く（巻き戻しでも元に戻る）")
    func castlingMovesRook() {
        var pos = position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let before = pos
        let undo = pos.make(ChessMove.fromUCI("e1g1")!)
        #expect(pos.squares[sq("g1")] == ChessPiece(type: .king, color: .white))
        #expect(pos.squares[sq("f1")] == ChessPiece(type: .rook, color: .white))
        #expect(pos.squares[sq("h1")] == nil)
        // 権利は両側とも失う（キングが動いたため）。
        #expect(pos.castling.contains(.whiteKingside) == false)
        #expect(pos.castling.contains(.whiteQueenside) == false)
        pos.unmake(undo)
        #expect(pos == before)
    }

    @Test("キングが王手されている・通過マスが攻撃されている・着地が攻撃されているときは指せない")
    func castlingBlockedByAttacks() {
        // e1 のキングが e8 のルークに王手されている。
        #expect(moves(position("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1")).contains("e1g1") == false)
        // 通過マス f1 が攻撃されている。
        #expect(moves(position("5r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")).contains("e1g1") == false)
        // 着地マス g1 が攻撃されている。
        #expect(moves(position("6r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")).contains("e1g1") == false)
        // クイーンサイドは b1 が攻撃されていても指せる（キングが通らないため）。
        #expect(moves(position("1r6/8/8/8/8/8/8/R3K2R w KQ - 0 1")).contains("e1c1"))
    }

    @Test("間に駒があると指せない（クイーンサイドは b1 も空きが要る）")
    func castlingBlockedByPieces() {
        #expect(moves(position("r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1")).contains("e1g1") == false)
        #expect(moves(position("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1")).contains("e1c1") == false)
    }

    @Test("ルークが動く／取られると、その側の権利だけが消える")
    func castlingRightsRevoked() {
        var pos = position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        pos.make(ChessMove.fromUCI("h1h5")!)   // 白のキングサイドのルークが動く
        #expect(pos.castling.contains(.whiteKingside) == false)
        #expect(pos.castling.contains(.whiteQueenside), "クイーンサイドは残る")
        #expect(pos.castling.contains(.blackKingside), "黒の権利には影響しない")

        var taken = position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        taken.make(ChessMove.fromUCI("a1a8")!) // 黒のクイーンサイドのルークを取る
        #expect(taken.castling.contains(.blackQueenside) == false)
        #expect(taken.castling.contains(.blackKingside), "取られていない側は残る")
    }

    // MARK: - アンパッサン

    @Test("2マス進みの直後だけアンパッサンで取れる")
    func enPassantAvailableOnlyImmediately() {
        var pos = position("4k3/7p/8/8/4pP2/8/8/4K3 b - f3 0 1")
        #expect(moves(pos).contains("e4f3"), "直後は取れる")

        // 1 手挟むと標的が消える。
        pos.make(ChessMove.fromUCI("h7h6")!)
        pos.make(ChessMove.fromUCI("e1e2")!)
        #expect(pos.enPassant == nil)
        #expect(moves(pos).contains("e4f3") == false, "1手経つと取れない")
    }

    @Test("アンパッサンで取られる駒は着手先ではなく真横にある")
    func enPassantRemovesAdjacentPawn() {
        var pos = position("4k3/8/8/8/4pP2/8/8/4K3 b - f3 0 1")
        let before = pos
        let undo = pos.make(ChessMove.fromUCI("e4f3")!)
        #expect(pos.squares[sq("f3")] == ChessPiece(type: .pawn, color: .black))
        #expect(pos.squares[sq("f4")] == nil, "真横の白ポーンが消える")
        pos.unmake(undo)
        #expect(pos == before, "巻き戻しで真横のポーンが戻る")
    }

    @Test("アンパッサンで自玉が開き王手になる手は指せない")
    func enPassantCannotExposeKing() {
        // 5段目に黒キング・白ポーン・黒ポーン・白ルークが一直線に並ぶ有名な形。
        // 取ると 2 枚まとめて筋が開き、黒キングがルークに晒される。
        let pos = position("8/8/8/8/k2pP2R/8/8/4K3 b - e3 0 1")
        #expect(moves(pos).contains("d4e3") == false)
    }

    // MARK: - プロモーション

    @Test("最奥段に届くと 4 種類の成りが候補になる")
    func promotionOffersFourPieces() {
        let pos = position("8/4P3/8/8/8/8/8/4k1K1 w - - 0 1")
        let promotions = pos.legalMoves().filter { $0.from == sq("e7") }.compactMap(\.promotion)
        #expect(Set(promotions) == [.queen, .rook, .bishop, .knight])
        #expect(pos.legalMoves().contains { $0.from == sq("e7") && $0.promotion == nil } == false,
                "成らずに最奥段へ進む手は無い")
    }

    @Test("成った駒が盤に現れ、巻き戻すとポーンに戻る")
    func promotionReplacesPawn() {
        var pos = position("8/4P3/8/8/8/8/8/4k1K1 w - - 0 1")
        let before = pos
        let undo = pos.make(ChessMove.fromUCI("e7e8n")!)
        #expect(pos.squares[sq("e8")] == ChessPiece(type: .knight, color: .white))
        pos.unmake(undo)
        #expect(pos == before)
        #expect(pos.squares[sq("e7")] == ChessPiece(type: .pawn, color: .white))
    }

    // MARK: - 王手・詰み・ステイルメイト

    @Test("ピンされた駒は動かせない")
    func pinnedPieceCannotMove() {
        // e1 の白キング・e2 の白ナイト・e8 の黒ルーク。ナイトは動けない。
        let pos = position("4r3/8/8/8/8/8/4N3/4K3 w - - 0 1")
        #expect(moves(pos).contains { $0.hasPrefix("e2") } == false)
    }

    @Test("王手されたら、王手を解く手しか指せない")
    func mustResolveCheck() {
        // g1 のルークは e8 のキングに当たっていない（筋が違う）。
        let quiet = position("4k3/8/8/8/8/8/8/4K1R1 b - - 0 1")
        #expect(quiet.isKingInCheck(.black) == false)

        // e7 のルークが王手。取るか、e 筋から逃げるかしかない。
        let real = position("4k3/4R3/8/8/8/8/8/4K3 b - - 0 1")
        #expect(real.isKingInCheck(.black))
        #expect(moves(real) == ["e8e7", "e8d8", "e8f8"])
    }

    @Test("チェックメイトは合法手ゼロ + 王手")
    func checkmate() {
        // 定番の「バックランクメイト」。
        let pos = position("6k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1")
        #expect(pos.legalMoves().isEmpty == false, "まだ詰んでいない")

        let mated = position("R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1")
        #expect(mated.legalMoves().isEmpty)
        #expect(mated.isKingInCheck(.black))
    }

    @Test("ステイルメイトは合法手ゼロ + 王手なし（引き分け）")
    func stalemate() {
        // 有名なステイルメイト形。黒キングは動けるマスが無いが王手されていない。
        let pos = position("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(pos.legalMoves().isEmpty)
        #expect(pos.isKingInCheck(.black) == false)
    }

    // MARK: - 引き分けの条件

    @Test("50手ルールの計数はポーンの移動と駒取りで 0 に戻る")
    func halfmoveClockResets() {
        var pos = position("4k3/p7/8/8/8/8/P6R/4K2r w - - 17 30")
        pos.make(ChessMove.fromUCI("e1e2")!)     // 普通の手 → 増える
        #expect(pos.halfmoveClock == 18)
        pos.make(ChessMove.fromUCI("a7a6")!)     // ポーンの移動 → 0
        #expect(pos.halfmoveClock == 0)
        pos.make(ChessMove.fromUCI("h2h1")!)     // 駒取り → 0
        #expect(pos.halfmoveClock == 0)
    }

    @Test("駒不足の判定（キング同士・軽い駒1枚・同色マスのビショップ）")
    func insufficientMaterial() {
        #expect(position("4k3/8/8/8/8/8/8/4K3 w - - 0 1").isInsufficientMaterial())
        #expect(position("4k3/8/8/8/8/8/8/4KN2 w - - 0 1").isInsufficientMaterial(), "K+N vs K")
        #expect(position("4k3/8/8/8/8/8/8/4KB2 w - - 0 1").isInsufficientMaterial(), "K+B vs K")
        // 同色マスのビショップ同士（c1 と f8 はどちらも暗いマス）。
        #expect(position("5b2/4k3/8/8/8/8/8/2B1K3 w - - 0 1").isInsufficientMaterial())
        // 違う色のマスなら詰ませられる。
        #expect(position("2b5/4k3/8/8/8/8/8/2B1K3 w - - 0 1").isInsufficientMaterial() == false)
        #expect(position("4k3/8/8/8/8/8/8/2N1KN2 w - - 0 1").isInsufficientMaterial() == false, "N 2枚")
        #expect(position("4k3/7p/8/8/8/8/8/4K3 w - - 0 1").isInsufficientMaterial() == false, "ポーンが居る")
    }

    // MARK: - 記譜

    @Test("SAN の表記（ポーン・駒・取る・キャスリング・成り・王手）")
    func standardAlgebraicNotation() {
        var pos = ChessPosition.start()
        #expect(ChessNotation.san(ChessMove.fromUCI("e2e4")!, in: pos) == "e4")
        #expect(ChessNotation.san(ChessMove.fromUCI("g1f3")!, in: pos) == "Nf3")

        pos = position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(ChessNotation.san(ChessMove.fromUCI("e1g1")!, in: pos) == "O-O")
        #expect(ChessNotation.san(ChessMove.fromUCI("e1c1")!, in: pos) == "O-O-O")

        // 取る手・成り・王手。
        let capture = position("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
        #expect(ChessNotation.san(ChessMove.fromUCI("e4d5")!, in: capture) == "exd5")

        let promote = position("8/4P3/8/8/8/8/8/4k1K1 w - - 0 1")
        #expect(ChessNotation.san(ChessMove.fromUCI("e7e8n")!, in: promote) == "e8=N")

        // 同じ駒種が同じマスへ行けるときは筋で区別する。
        // キングは d1 への道を塞がないよう e4 に置く（e1 に居ると h1 のルークが d1 へ届かない）。
        let ambiguous = position("4k3/8/8/8/4K3/8/8/R6R w - - 0 1")
        #expect(ChessNotation.san(ChessMove.fromUCI("a1d1")!, in: ambiguous) == "Rad1")
        #expect(ChessNotation.san(ChessMove.fromUCI("h1d1")!, in: ambiguous) == "Rhd1")
    }

    @Test("詰ませる手には # が付く")
    func sanMarksCheckmate() {
        let pos = position("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(ChessNotation.san(ChessMove.fromUCI("a1a8")!, in: pos) == "Ra8#")
    }

    // MARK: - UCI

    @Test("UCI 文字列の往復")
    func uciRoundTrip() {
        for uci in ["e2e4", "e7e8q", "e1g1", "a7a8n"] {
            #expect(ChessMove.fromUCI(uci)?.uci == uci)
        }
        #expect(ChessMove.fromUCI("e2") == nil)
        #expect(ChessMove.fromUCI("e2e4k") == nil, "キングには成れない")
        #expect(ChessMove.fromUCI("z9z9") == nil)
    }
}
