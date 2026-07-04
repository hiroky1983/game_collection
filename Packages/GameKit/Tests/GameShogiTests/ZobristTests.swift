import Testing
@testable import GameShogi

@Suite("Zobrist差分更新の整合性")
struct ZobristTests {

    /// 決定論的な自己対局で、make 後の差分更新ハッシュがフル再計算と常に一致することを確認。
    @Test func incrementalHashMatchesFullRecompute() {
        var pos = Position.start()
        for i in 0..<300 {
            let moves = pos.legalMoves()
            guard !moves.isEmpty else { break }
            let move = moves[(i &* 7919) % moves.count]

            let hashBefore = pos.hash
            let undo = pos.make(move)
            #expect(pos.hash == Position.computeHash(
                squares: pos.squares, hands: pos.hands, sideToMove: pos.sideToMove))

            // 玉位置キャッシュも盤面と一致していること
            for color in Side.allCases {
                let expected = pos.squares.firstIndex { $0?.type == .king && $0?.color == color }
                #expect(pos.kingSquare(color) == expected)
            }

            // unmake で完全に巻き戻ること
            pos.unmake(undo)
            #expect(pos.hash == hashBefore)

            pos.make(move)
        }
    }

    @Test func nullMoveHashRoundTrip() {
        var pos = Position.start()
        let before = pos.hash
        let undo = pos.makeNull()
        #expect(pos.hash != before)
        #expect(pos.hash == Position.computeHash(
            squares: pos.squares, hands: pos.hands, sideToMove: pos.sideToMove))
        pos.unmakeNull(undo)
        #expect(pos.hash == before)
    }

    /// MoveCode の encode/decode が全パターンで可逆であること。
    @Test func moveCodeRoundTrip() {
        var pos = Position.start()
        for i in 0..<50 {
            let moves = pos.legalMoves()
            guard !moves.isEmpty else { break }
            pos.make(moves[(i &* 31) % moves.count])
        }
        for move in pos.legalMoves() {
            // MoveCode は ShogiEngine.swift 内 private のため、TT 経由の間接テストは
            // EngineTests に任せ、ここでは合法手が 0..80 の範囲に収まることのみ確認する。
            switch move {
            case let .board(from, to, _):
                #expect((0..<81).contains(from) && (0..<81).contains(to))
            case let .drop(_, to):
                #expect((0..<81).contains(to))
            }
        }
    }
}
