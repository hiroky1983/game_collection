import Testing
@testable import GameChess

private func sq(_ name: String) -> Int { ChessSquare.fromName(Substring(name))! }

/// 駒の移動を SwiftUI に補間させるための ID 継承（将棋 #200 と同じ仕組み）。
///
/// **チェス固有の難所は 3 つ**: キャスリング（2 駒が同時に動く）・アンパッサン（取られる駒が
/// 着手先に居ない）・プロモーション（駒種が変わる）。どれも「同じ駒が動いた」と読めないと
/// 駒が瞬間移動して見える。
@Suite("チェス 駒の対応付け")
struct ChessPieceLayoutTests {

    private func layout(_ fen: String) -> (ChessPieceLayout, ChessPosition) {
        let pos = ChessPosition.fromFEN(fen)!
        return (ChessPieceLayout(pos), pos)
    }

    private func id(_ layout: ChessPieceLayout, at square: Int) -> Int? {
        layout.placements.first { $0.square == square }?.id
    }

    @Test("初期局面では 32 枚に ID が振られ、ID 昇順で並ぶ")
    func initialPlacements() {
        let (l, _) = layout(ChessPosition.startFEN)
        #expect(l.placements.count == 32)
        #expect(l.placements.map(\.id) == l.placements.map(\.id).sorted(),
                "ForEach の並び = 重なり順なので ID 昇順でなければならない")
    }

    @Test("普通の移動では動いた駒の ID が引き継がれ、他は据え置かれる")
    func normalMoveCarriesID() {
        var (l, pos) = layout(ChessPosition.startFEN)
        let pawnID = id(l, at: sq("e2"))
        let knightID = id(l, at: sq("g1"))

        pos.make(ChessMove.fromUCI("e2e4")!)
        l.update(to: pos)

        #expect(id(l, at: sq("e4")) == pawnID, "動いた駒は同じ ID")
        #expect(id(l, at: sq("e2")) == nil)
        #expect(id(l, at: sq("g1")) == knightID, "動いていない駒は据え置き")
        #expect(l.placements.count == 32)
    }

    @Test("駒を取ると 1 枚減り、取った側の ID が着手先へ移る")
    func captureRemovesOnePiece() {
        var (l, pos) = layout("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
        let pawnID = id(l, at: sq("e4"))
        #expect(l.placements.count == 4)

        pos.make(ChessMove.fromUCI("e4d5")!)
        l.update(to: pos)

        #expect(l.placements.count == 3)
        #expect(id(l, at: sq("d5")) == pawnID, "取った側の駒が移動した扱いになる")
    }

    @Test("キャスリングではキングとルークの両方が ID を保ったまま動く")
    func castlingCarriesBothPieces() {
        var (l, pos) = layout("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let kingID = id(l, at: sq("e1"))
        let rookID = id(l, at: sq("h1"))

        pos.make(ChessMove.fromUCI("e1g1")!)
        l.update(to: pos)

        #expect(id(l, at: sq("g1")) == kingID, "キングは同じ駒として g1 へ")
        #expect(id(l, at: sq("f1")) == rookID, "ルークも同じ駒として f1 へ")
        #expect(l.placements.count == 6, "枚数は変わらない（両陣のキングとルーク）")
    }

    @Test("アンパッサンでは真横の駒が消え、取った駒は斜めへ動く")
    func enPassantRemovesAdjacentPawn() {
        var (l, pos) = layout("4k3/8/8/8/4pP2/8/8/4K3 b - f3 0 1")
        let blackPawnID = id(l, at: sq("e4"))
        let whitePawnID = id(l, at: sq("f4"))
        #expect(whitePawnID != nil)

        pos.make(ChessMove.fromUCI("e4f3")!)
        l.update(to: pos)

        #expect(id(l, at: sq("f3")) == blackPawnID)
        #expect(id(l, at: sq("f4")) == nil, "取られた白ポーンは盤から消える")
        #expect(l.placements.contains { $0.id == whitePawnID } == false)
        #expect(l.placements.count == 3)
    }

    @Test("プロモーションでは駒種が変わっても同じ駒として動く")
    func promotionKeepsIdentity() {
        var (l, pos) = layout("k7/4P3/8/8/8/8/8/6K1 w - - 0 1")
        let pawnID = id(l, at: sq("e7"))

        pos.make(ChessMove.fromUCI("e7e8q")!)
        l.update(to: pos)

        #expect(id(l, at: sq("e8")) == pawnID, "ポーン → クイーンでも ID を引き継ぐ")
        #expect(l.placements.first { $0.id == pawnID }?.piece.type == .queen)
    }

    @Test("同じ局面からは常に同じ対応付けが出る（検討ナビの飛び移りでも壊れない）")
    func deterministicForSamePosition() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1"
        var (a, pos) = layout(fen)
        var b = ChessPieceLayout()
        b.update(to: pos)
        #expect(a.placements.map(\.square).sorted() == b.placements.map(\.square).sorted())

        // 局面を進めて戻すと、駒の顔ぶれは元どおりになる。
        let squaresBefore = Set(a.placements.map(\.square))
        let undo = pos.make(ChessMove.fromUCI("e1g1")!)
        a.update(to: pos)
        pos.unmake(undo)
        a.update(to: pos)
        #expect(Set(a.placements.map(\.square)) == squaresBefore)
    }
}
