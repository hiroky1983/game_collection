import Foundation

extension ChessPosition {
    /// perft: 深さ n までの合法手ノード数を数える。ルールエンジン検証の土台。
    ///
    /// チェスの合法手生成の標準的な検収手法で、公表されている既知の正解値と突き合わせる。
    /// キャスリング・アンパッサン・プロモーション・ピン・王手回避が**1 つでも間違っていれば
    /// 数が合わない**ため、個別のルールテストでは拾いきれない取りこぼしまで捕まえられる。
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

    /// 指し手ごとの内訳（`perft divide`）。数が合わないときにどの手の先で狂っているかを絞り込む。
    public func perftDivide(_ depth: Int) -> [(move: String, nodes: Int)] {
        guard depth >= 1 else { return [] }
        var pos = self
        return pos.legalMovesInPlace().map { move in
            let undo = pos.make(move)
            let n = pos.perft(depth - 1)
            pos.unmake(undo)
            return (move.uci, n)
        }
    }
}
