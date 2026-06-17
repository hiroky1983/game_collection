import Testing
@testable import GameShogi

@Suite("座標・SFEN の向き")
struct OrientationTests {
    @Test func rookOn2hBishopOn8h() {
        let pos = Position.start()
        // 先手飛車は 2h、角は 8h（SFEN 左端=9筋）。
        let rook = pos.squares[Sq.fromUSI("2h")!]
        let bishop = pos.squares[Sq.fromUSI("8h")!]
        #expect(rook == Piece(type: .rook, color: .black))
        #expect(bishop == Piece(type: .bishop, color: .black))
    }

    @Test func sfenRoundTrip() {
        #expect(Position.start().toSFEN() == Position.startSFEN)
    }

    @Test func usiSquareRoundTrip() {
        for i in 0..<81 {
            #expect(Sq.fromUSI(Substring(Sq.toUSI(i))) == i)
        }
    }
}

@Suite("反則の実装")
struct IllegalMoveTests {
    /// 二歩: 同じ筋に自分の歩があるとき、その筋への歩打ちは生成されない。
    @Test func nifuExcluded() {
        // 先手玉 5i、後手玉 5a、先手歩 5e、先手持ち駒 歩1。
        let sfen = "4k4/9/9/9/4P4/9/9/9/4K4 b P 1"
        let pos = Position.fromSFEN(sfen)!
        let drops5 = pos.legalMoves().filter {
            if case let .drop(.pawn, to) = $0 { return Sq.file(to) == Sq.file(Sq.fromUSI("5e")!) }
            return false
        }
        #expect(drops5.isEmpty) // 5筋には二歩で打てない
        // 別の筋（6筋）には打てる。
        let drops6 = pos.legalMoves().contains { $0 == .drop(type: .pawn, to: Sq.fromUSI("6e")!) }
        #expect(drops6)
    }

    /// 行き所のない駒: 歩は最奥段へ打てない。
    @Test func pawnDropLastRankExcluded() {
        let sfen = "4k4/9/9/9/9/9/9/9/4K4 b P 1"
        let pos = Position.fromSFEN(sfen)!
        // 先手の最奥段は rank 'a'。1a..9a への歩打ちは無い。
        let dropsOnRankA = pos.legalMoves().contains {
            if case let .drop(.pawn, to) = $0 { return Sq.rank(to) == 0 }
            return false
        }
        #expect(dropsOnRankA == false)
    }

    /// 王手放置: 自玉が取られる手は合法手に含まれない。
    @Test func leavingKingInCheckExcluded() {
        // 先手玉 5e、後手飛車 5a（5筋で王手）、間に何もない。先手は王手を防ぐ／逃げる手のみ。
        let sfen = "4r4/9/9/9/4K4/9/9/9/4k4 b - 1"
        let pos = Position.fromSFEN(sfen)!
        let moves = pos.legalMoves()
        // 王手されている。
        #expect(pos.isKingInCheck(.black))
        // すべての合法手は、指した後に自玉が王手でない。
        for m in moves {
            var p = pos
            p.make(m)
            #expect(p.isKingInCheck(.black) == false)
        }
        // 5筋上で玉が横に逃げる手は存在する（4e/6e）。
        #expect(moves.contains { $0 == .board(from: Sq.fromUSI("5e")!, to: Sq.fromUSI("4e")!, promote: false) })
    }

    /// 打ち歩詰め: 歩を打って詰ますのは反則。
    @Test func dropPawnMateExcluded() {
        // 後手玉 5a。逃げ場 4a/6a/4b/6b を後手自身の香で塞ぎ（香は 5b を攻撃しないので打つ前は王手でない）、
        // 5b は先手銀(6c)が支える。5b への歩打ちは詰み → 打ち歩詰めで非合法。
        let sfen = "3lkl3/3l1l3/3S5/9/9/9/9/9/K8 b P 1"
        let pos = Position.fromSFEN(sfen)!
        #expect(pos.isKingInCheck(.white) == false) // 打つ前は王手でない
        let drop5b = Move.drop(type: .pawn, to: Sq.fromUSI("5b")!)
        #expect(pos.legalMoves().contains(drop5b) == false)
    }

    /// 打ち歩詰めでない歩打ち王手は合法（玉に逃げ場 4a がある）。
    @Test func dropPawnCheckButNotMateAllowed() {
        let sfen = "3lk4/3l1l3/3S5/9/9/9/9/9/K8 b P 1"
        let pos = Position.fromSFEN(sfen)!
        let drop5b = Move.drop(type: .pawn, to: Sq.fromUSI("5b")!)
        #expect(pos.legalMoves().contains(drop5b))
    }
}
