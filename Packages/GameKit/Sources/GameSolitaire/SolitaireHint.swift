import Foundation
import Core

/// ヒントの回数（会長決裁 2026-10-11・#2025）。フリーセル・スパイダーと同じ 1 局 無料 3 回・広告で最大 5 回。
public enum SolitaireHintPolicy {
    public static let freeCount = BoardHintBudget.perGame
    public static let adRefillMax = BoardHintBudget.adRefillMax
}

/// ヒントの答え（#2025）。
public enum SolitaireHintResult: Equatable, Sendable {
    /// 次に指す 1 手（動かす・山をめくる）。動かすのはプレイヤー。
    case move(SolitaireMove)
    /// 探索を尽くしても勝ち筋が無い。回数は減らさず、戻すように伝える。
    case hopeless
}

/// 答えと、それを導いた勝ち筋（見つかったときだけ。見込みで示した手・勝てない盤では空）。
/// 筋を持ち回る理由は `SpiderHintAnswer` と同じ（毎回解き直すと別の筋に乗り換えて往復する。山めくりは特に循環しうる）。
public struct SolitaireHintAnswer: Sendable, Equatable {
    public let result: SolitaireHintResult
    public let plan: [SolitaireMove]
}

/// 示した筋の続き（#2025）。示した手を指した後の盤に着いたら、解き直さず同じ筋の次の手を示す。
public struct SolitaireHintTrail: Sendable, Equatable {
    let moves: [SolitaireMove]
    let board: SolitaireBoard

    /// `answer` の手を `board` で指した後の盤と、その続き。筋が無い（見込みの手・勝てない盤）か手が合わなければ nil。
    public static func after(_ answer: SolitaireHintAnswer, from board: SolitaireBoard) -> SolitaireHintTrail? {
        guard case .move(let move) = answer.result, answer.plan.first == move else { return nil }
        var next = board
        guard next.apply(move) else { return nil }
        let rest = Array(answer.plan.dropFirst())
        return rest.isEmpty ? nil : SolitaireHintTrail(moves: rest, board: next)
    }

    /// 今の盤が筋の続きの盤なら、その次の手。
    public func answer(at current: SolitaireBoard) -> SolitaireHintAnswer? {
        guard current == board, let next = moves.first, current.isLegal(next) else { return nil }
        return SolitaireHintAnswer(result: .move(next), plan: moves)
    }
}

/// 「次の一手」を求める純関数（#2025）。画面にも Model にも触れないので `Task.detached` から安全に呼べる。
///
/// **裏札・山札の中身を知ったうえで解いてよい**（会長承認済み）。ジョーカーは探索で使わない。
public enum SolitaireHint {

    /// ヒントの探索上限。配札生成と同じ既定（`SolitaireSolver.defaultMaxStates`）で、実測は
    /// 1 配札あたり平均 0.20 秒・最悪 0.92 秒（Apple Silicon の `-O`）。押した人を待たせる長さの上限としてこれ以上は上げない。
    public static let maxStates = SolitaireSolver.defaultMaxStates

    /// - Parameter isCancelled: 探索を途中で降ろすかを訊く。降ろしたときは nil（印を出さない）。
    public static func find(
        in board: SolitaireBoard,
        maxStates: Int = SolitaireHint.maxStates,
        isCancelled: () -> Bool = { false }
    ) -> SolitaireHintResult? {
        findPlan(in: board, maxStates: maxStates, isCancelled: isCancelled)?.result
    }

    /// `find` と同じだが、勝ち筋も一緒に返す（Model が続きの手に使う）。
    public static func findPlan(
        in board: SolitaireBoard,
        maxStates: Int = SolitaireHint.maxStates,
        isCancelled: () -> Bool = { false }
    ) -> SolitaireHintAnswer? {
        let result = SolitaireSolver.solve(board, allowJoker: false, maxStates: maxStates, isCancelled: isCancelled)
        if let solution = result.solution, let first = solution.first {
            return SolitaireHintAnswer(result: .move(first), plan: solution)
        }
        if isCancelled() { return nil }
        // 解が空（すでにクリア）なら示す手が無い。尽くして勝ち筋が無いなら不能、打ち切りなら「不明」。
        if result.solution != nil || !result.hitLimit { return SolitaireHintAnswer(result: .hopeless, plan: []) }
        guard let move = promisingMove(in: board) else { return SolitaireHintAnswer(result: .hopeless, plan: []) }
        return SolitaireHintAnswer(result: .move(move), plan: [])
    }

    /// 打ち切られたときの手。**組札へ送れる札 → 裏札をめくれる移動 → 空き列を作る移動 → 山札をめくる**
    /// の順で、最初に当たったものを返す（どれも無ければ合法な手の先頭）。
    static func promisingMove(in board: SolitaireBoard) -> SolitaireMove? {
        var foundation: [SolitaireMove] = []
        var flipping: [SolitaireMove] = []
        var emptying: [SolitaireMove] = []
        var others: [SolitaireMove] = []

        for pile in board.tableau.indices where board.isLegal(.tableauToFoundation(pile: pile)) {
            foundation.append(.tableauToFoundation(pile: pile))
        }
        if board.isLegal(.wasteToFoundation) { foundation.append(.wasteToFoundation) }

        for from in board.tableau.indices {
            let column = board.tableau[from]
            for index in column.faceUp.indices where board.isMovableRun(pile: from, from: index) {
                let run = Array(column.faceUp[index...])
                for to in board.tableau.indices where to != from && board.canPlace(run, onPile: to) {
                    let move = SolitaireMove.tableauToTableau(from: from, cardIndex: index, to: to)
                    // 空列へ K を移すだけの手は、K が既に列の底なら盤が進まない（往復の元）。
                    if index == 0, column.faceDown.isEmpty, board.tableau[to].isEmpty { continue }
                    if index == 0, !column.faceDown.isEmpty { flipping.append(move) }
                    else if index == 0 { emptying.append(move) }
                    else { others.append(move) }
                }
            }
        }
        for to in board.tableau.indices where board.isLegal(.wasteToTableau(pile: to)) {
            others.append(.wasteToTableau(pile: to))
        }

        if let move = foundation.first ?? flipping.first ?? emptying.first { return move }
        if board.isLegal(.draw) { return .draw }
        return others.first
    }
}
