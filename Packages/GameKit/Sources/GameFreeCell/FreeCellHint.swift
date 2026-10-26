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

/// 答えと、それを導いた勝ち筋（見つかったときだけ。見込みで示した手・勝てない盤では空）。
/// 筋を持ち回る理由はソリティア・スパイダーと同じ（毎回解き直すと待たされ、別の筋に乗り換えて往復もしうる）。
public struct FreeCellHintAnswer: Sendable, Equatable {
    public let result: FreeCellHintResult
    /// 探索が返した勝ち筋そのまま（安全な組札送りを含む）。
    public let plan: [FreeCellMove]
}

/// 示した筋の続き（#2602）。示した手を指した後の盤に着いたら、解き直さず同じ筋の次の手を示す。
public struct FreeCellHintTrail: Sendable, Equatable {
    let moves: [FreeCellMove]
    let board: FreeCellBoard

    /// `answer` の手を `board` で指した後の盤と、その続き。筋が無い（見込みの手・勝てない盤）か手が合わなければ nil。
    /// 示した手は筋の途中（安全な組札送りの後ろ）にあることがあるので、その 1 手だけを筋から抜く。
    /// 抜いた残りが次の盤から最後まで指せない筋は、続きとして信用せず捨てる。
    public static func after(_ answer: FreeCellHintAnswer, from board: FreeCellBoard) -> FreeCellHintTrail? {
        guard case .move(let move) = answer.result, !answer.plan.isEmpty,
              let step = FreeCellHint.firstStep(of: answer.plan, from: board), step.move == move else { return nil }
        var next = board
        guard next.apply(move) else { return nil }
        var rest = answer.plan
        rest.remove(at: step.index)
        var check = next
        for m in rest where !check.apply(m) { return nil }
        return rest.isEmpty ? nil : FreeCellHintTrail(moves: rest, board: next)
    }

    /// 今の盤が筋の続きの盤なら、その次の手。
    public func answer(at current: FreeCellBoard) -> FreeCellHintAnswer? {
        guard current == board, let step = FreeCellHint.firstStep(of: moves, from: current),
              current.isLegal(step.move) else { return nil }
        return FreeCellHintAnswer(result: .move(step.move), plan: moves)
    }
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
        findPlan(in: board, maxStates: maxStates, isCancelled: isCancelled)?.result
    }

    /// `find` と同じだが、勝ち筋も一緒に返す（Model が続きの手に使う）。
    public static func findPlan(
        in board: FreeCellBoard,
        maxStates: Int = FreeCellSolver.defaultMaxStates,
        isCancelled: () -> Bool = { false }
    ) -> FreeCellHintAnswer? {
        let result = FreeCellSolver.solve(board, maxStates: maxStates, isCancelled: isCancelled)
        if let solution = result.solution {
            guard let move = firstMove(of: solution, from: board) else {
                return FreeCellHintAnswer(result: .hopeless, plan: [])
            }
            return FreeCellHintAnswer(result: .move(move), plan: solution)
        }
        if isCancelled() { return nil }
        // 尽くして勝ち筋が無いなら不能。上限で打ち切ったのなら「不明」なので良さそうな手を示す。
        if !result.hitLimit { return FreeCellHintAnswer(result: .hopeless, plan: []) }
        guard let move = promisingMove(in: board) else { return FreeCellHintAnswer(result: .hopeless, plan: []) }
        return FreeCellHintAnswer(result: .move(move), plan: [])
    }

    /// 勝ち筋のうち、プレイヤーに示す最初の 1 手。
    ///
    /// 勝ち筋は「安全な組札送り」（`FreeCellSolver.autoplaySafe`）を分岐させずに挟み込んで作られている。
    /// それを 1 手ずつ示すと「A を送る」ばかりのヒントになるので飛ばし、**最初の本筋の手**を返す。
    /// ただし飛ばした送りの後でないと本筋の手が成立しない（送る札の上に積む手など）ことがあるので、
    /// 今の盤で同じ札を動かせない手のときは、飛ばした最初の送りを示す。本筋が尽きたら（残りは送るだけ）その送りを示す。
    static func firstMove(of solution: [FreeCellMove], from board: FreeCellBoard) -> FreeCellMove? {
        firstStep(of: solution, from: board)?.move
    }

    /// `firstMove` と同じ手に、それが `solution` の何番目かを添えて返す（筋からその 1 手だけを抜くのに使う）。
    static func firstStep(of solution: [FreeCellMove], from board: FreeCellBoard) -> (move: FreeCellMove, index: Int)? {
        var working = board
        var firstSkipped: (move: FreeCellMove, index: Int)?
        for (index, move) in solution.enumerated() {
            if let card = foundationCard(of: move, in: working), FreeCellSolver.isSafe(card, working) {
                if firstSkipped == nil, board.isLegal(move) { firstSkipped = (move, index) }
                guard working.apply(move) else { return nil }
                continue
            }
            if board.isLegal(move), movedCards(move, in: board) == movedCards(move, in: working) {
                return (move, index)
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
