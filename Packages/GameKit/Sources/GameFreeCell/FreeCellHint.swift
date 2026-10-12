import Foundation
import Core

/// ヒントの回数（会長決裁 2026-10-11・#2025）。1 局 無料 3 回、使い切ったら広告 1 本で +1、広告は最大 5 回。
/// 戻すとは別の回数で、戻してもヒントの回数は戻らない。値は Core の `BoardHintBudget` の既定のまま。
public enum FreeCellHintPolicy {
    public static let freeCount = BoardHintBudget.perGame
    public static let adRefillMax = BoardHintBudget.adRefillMax
}

/// ヒントの答え（#2025）。
public enum FreeCellHintResult: Equatable, Sendable {
    /// 次に指す 1 手。動かすのはプレイヤー。
    case move(FreeCellMove)
    /// 探索を尽くしても勝ち筋が無い。回数は減らさず、戻すように伝える。
    case hopeless
}

/// 「次の一手」を求める純関数（#2025）。画面にも Model にも触れないので、`Task.detached` から安全に呼べる。
public enum FreeCellHint {

    /// - Parameter isCancelled: 探索を途中で降ろすかを訊く。降ろしたときは nil（印を出さない）。
    /// - Returns: 勝ち筋が見つかれば最初の 1 手、探索を尽くして無ければ `.hopeless`、
    ///   上限で打ち切られたら（勝てるとも勝てないとも言えない）見込みの良い手。
    public static func find(
        in board: FreeCellBoard,
        maxStates: Int = FreeCellSolver.defaultMaxStates,
        isCancelled: () -> Bool = { false }
    ) -> FreeCellHintResult? {
        let result = FreeCellSolver.solve(board, maxStates: maxStates, isCancelled: isCancelled)
        if let solution = result.solution {
            return firstMove(of: solution, from: board).map { .move($0) } ?? .hopeless
        }
        if isCancelled() { return nil }
        // 尽くして勝ち筋が無いなら不能。上限で打ち切ったのなら「不明」なので良さそうな手を示す。
        if !result.hitLimit { return .hopeless }
        return promisingMove(in: board).map { .move($0) } ?? .hopeless
    }

    /// 勝ち筋のうち、プレイヤーに示す最初の 1 手。
    ///
    /// 勝ち筋は「安全な組札送り」（`FreeCellSolver.autoplaySafe`）を分岐させずに挟み込んで作られている。
    /// それを 1 手ずつ示すと「A を送る」ばかりのヒントになるので飛ばし、**最初の本筋の手**を返す。
    /// ただし飛ばした送りの後でないと本筋の手が成立しない（送る札の上に積む手など）ことがあるので、
    /// 今の盤で同じ札を動かせない手のときは、飛ばした最初の送りを示す。本筋が尽きたら（残りは送るだけ）その送りを示す。
    static func firstMove(of solution: [FreeCellMove], from board: FreeCellBoard) -> FreeCellMove? {
        var working = board
        var firstSkipped: FreeCellMove?
        for move in solution {
            if let card = foundationCard(of: move, in: working), FreeCellSolver.isSafe(card, working) {
                if firstSkipped == nil, board.isLegal(move) { firstSkipped = move }
                guard working.apply(move) else { return nil }
                continue
            }
            if board.isLegal(move), movedCards(move, in: board) == movedCards(move, in: working) {
                return move
            }
            return firstSkipped
        }
        return firstSkipped
    }

    /// 打ち切られたときの手。組札へ送れる → 空き列ができる → 次に要る札が出る、の順に効く
    /// （`FreeCellSolver.heuristic` が小さくなる手）。同点は探索の並び（組札送り → 積み替え → 退避）の先頭。
    static func promisingMove(in board: FreeCellBoard) -> FreeCellMove? {
        var best: (move: FreeCellMove, score: Int)?
        for move in FreeCellSolver.successors(of: board) {
            var next = board
            guard next.apply(move) else { continue }
            let score = FreeCellSolver.heuristic(FreeCellSolver.autoplaySafe(next).0)
            if best == nil || score < best!.score { best = (move, score) }
        }
        return best?.move
    }

    private static func foundationCard(of move: FreeCellMove, in board: FreeCellBoard) -> FreeCellCard? {
        switch move {
        case .tableauToFoundation(let pile): board.tableau.indices.contains(pile) ? board.tableau[pile].last : nil
        case .cellToFoundation(let cell): board.cells.indices.contains(cell) ? board.cells[cell] : nil
        default: nil
        }
    }

    /// 手で動く札。盤が違っても「同じ札を動かす手か」を比べるために使う。
    static func movedCards(_ move: FreeCellMove, in board: FreeCellBoard) -> [FreeCellCard] {
        switch move {
        case .tableauToCell(let from, _), .tableauToFoundation(let from):
            return board.tableau.indices.contains(from) ? Array(board.tableau[from].suffix(1)) : []
        case .tableauToTableau(let from, let index, _):
            guard board.tableau.indices.contains(from), board.tableau[from].indices.contains(index) else { return [] }
            return Array(board.tableau[from][index...])
        case .cellToTableau(let cell, _), .cellToFoundation(let cell):
            return board.cells.indices.contains(cell) ? board.cells[cell].map { [$0] } ?? [] : []
        }
    }
}
