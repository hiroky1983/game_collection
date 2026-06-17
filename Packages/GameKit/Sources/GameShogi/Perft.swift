import Foundation

extension Position {
    /// perft: 深さ n までの合法手ノード数を数える。ルールエンジン検証の土台。
    /// perft(n) = Σ over legalMoves { make → perft(n-1) → unmake }
    public func perft(_ depth: Int) -> Int {
        var pos = self
        return pos.perftInPlace(depth)
    }

    private mutating func perftInPlace(_ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = legalMovesInPlace()
        if depth == 1 { return moves.count }
        var nodes = 0
        for move in moves {
            let undo = make(move)
            nodes += perftInPlace(depth - 1)
            unmake(undo)
        }
        return nodes
    }
}
