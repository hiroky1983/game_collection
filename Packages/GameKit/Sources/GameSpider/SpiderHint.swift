import Foundation
import Core

/// ヒントの回数（会長決裁 2026-10-11・#2025）。フリーセルと同じ 1 局 無料 3 回・広告で最大 5 回。
public enum SpiderHintPolicy {
    public static let freeCount = BoardHintBudget.perGame
    public static let adRefillMax = BoardHintBudget.adRefillMax
}

/// ヒントの答え（#2025）。
public enum SpiderHintResult: Equatable, Sendable {
    /// 次に指す 1 手（動かす・配る）。動かすのはプレイヤー。
    case move(SpiderMove)
    /// 探索を尽くしても勝ち筋が無い。回数は減らさず、戻すように伝える。
    case hopeless
}

/// 答えと、それを導いた勝ち筋（見つかったときだけ。見込みで示した手・勝てない盤では空）。
///
/// 筋を持ち回る理由: スパイダーは盤の変化が大きく、毎回解き直すと**別の筋に乗り換えて往復する**
/// （ヒントの手だけを指し続けても勝てない・実測）。示した手をプレイヤーが指したら、同じ筋の続きを示す。
public struct SpiderHintAnswer: Sendable, Equatable {
    public let result: SpiderHintResult
    public let plan: [SpiderMove]
}

/// 示した筋の続き（#2025）。示した手を指した後の盤に着いたら、解き直さず同じ筋の次の手を示す。
public struct SpiderHintTrail: Sendable, Equatable {
    let moves: [SpiderMove]
    let board: SpiderBoard

    /// `answer` の手を `board` で指した後の盤と、その続き。筋が無い（見込みの手・勝てない盤）か手が合わなければ nil。
    public static func after(_ answer: SpiderHintAnswer, from board: SpiderBoard) -> SpiderHintTrail? {
        guard case .move(let move) = answer.result, answer.plan.first == move else { return nil }
        var next = board
        guard next.apply(move) else { return nil }
        let rest = Array(answer.plan.dropFirst())
        return rest.isEmpty ? nil : SpiderHintTrail(moves: rest, board: next)
    }

    /// 今の盤が筋の続きの盤なら、その次の手。
    public func answer(at current: SpiderBoard) -> SpiderHintAnswer? {
        guard current == board, let next = moves.first, current.isLegal(next) else { return nil }
        return SpiderHintAnswer(result: .move(next), plan: moves)
    }
}

/// 「次の一手」を求める純関数（#2025）。画面にも Model にも触れないので `Task.detached` から安全に呼べる。
public enum SpiderHint {

    /// ヒントの探索上限（スート数ごと）。**1 秒前後で答えが返る値**に絞る（会長決裁の仕様）。
    ///
    /// 実測（Mac・`swiftc -O`・2026-10-11）: 6 万局面で 0.1〜0.5 秒（4 スートは 0.34〜0.66 秒）、3 万局面で 0.02〜0.3 秒。
    /// 1 スートは数千〜2.5 万局面で解け、途中の盤も同じ。実機はこの 1.5〜2 倍を見込み、1・2 スートは 6 万、
    /// 4 スートは 1 局面が重いので 4 万で打ち切る。**配札生成の上限（`SpiderSolver.defaultMaxStates`）よりずっと小さい**:
    /// 生成は時間をかけて踏破できた種だけを残すが、ヒントは押した人を待たせるので、勝ち筋が見つからなければ
    /// 打ち切って見込みの良い手を示す（2・4 スートの難しい盤はこちらに落ちる）。
    public static func maxStates(for suits: SpiderSuitCount) -> Int {
        switch suits {
        case .one, .two: return 60_000
        case .four:      return 40_000
        }
    }

    /// - Parameter isCancelled: 探索を途中で降ろすかを訊く。降ろしたときは nil（印を出さない）。
    /// - Returns: 勝ち筋が見つかれば最初の 1 手、探索を尽くして無ければ `.hopeless`、
    ///   上限で打ち切られたら（勝てるとも勝てないとも言えない）見込みの良い手。
    public static func find(
        in board: SpiderBoard,
        suits: SpiderSuitCount,
        maxStates: Int? = nil,
        isCancelled: () -> Bool = { false }
    ) -> SpiderHintResult? {
        findPlan(in: board, suits: suits, maxStates: maxStates, isCancelled: isCancelled)?.result
    }

    /// `find` と同じだが、勝ち筋も一緒に返す（Model が続きの手に使う）。
    public static func findPlan(
        in board: SpiderBoard,
        suits: SpiderSuitCount,
        maxStates: Int? = nil,
        isCancelled: () -> Bool = { false }
    ) -> SpiderHintAnswer? {
        let result = SpiderSolver.solve(
            board, maxStates: maxStates ?? Self.maxStates(for: suits), isCancelled: isCancelled)
        if let solution = result.solution, let first = solution.first {
            return SpiderHintAnswer(result: .move(first), plan: solution)
        }
        if isCancelled() { return nil }
        // 解が空（すでにクリア）なら示す手が無い。尽くして勝ち筋が無いなら不能、打ち切りなら「不明」。
        if result.solution != nil || !result.hitLimit { return SpiderHintAnswer(result: .hopeless, plan: []) }
        guard let move = promisingMove(in: board) else { return SpiderHintAnswer(result: .hopeless, plan: []) }
        return SpiderHintAnswer(result: .move(move), plan: [])
    }

    /// 打ち切られたときの手。**組を完成させる → 伏せ札をめくれる → 空き列ができる → 同じスートに繋がる → 山札を配る**
    /// の順で、最初に当たったものを返す（どれも無ければ合法手の先頭）。
    static func promisingMove(in board: SpiderBoard) -> SpiderMove? {
        let legal = board.legalMoves
        let moves: [(move: SpiderMove, from: Int, index: Int, to: Int)] = legal.compactMap {
            guard case .move(let from, let index, let to) = $0 else { return nil }
            return ($0, from, index, to)
        }
        // 空列への置き手は「動かす先が無いから」の逃げなので、上の 4 段では最後に回す。
        let toNonEmpty = moves.filter { !board.piles[$0.to].isEmpty }

        for entry in toNonEmpty {
            var next = board
            next.apply(entry.move)
            if next.completed.count > board.completed.count { return entry.move }
        }
        for entry in toNonEmpty {
            let pile = board.piles[entry.from]
            if pile.faceDownCount > 0, entry.index == pile.faceDownCount { return entry.move }
        }
        for entry in toNonEmpty {
            let pile = board.piles[entry.from]
            if pile.faceDownCount == 0, entry.index == 0 { return entry.move }
        }
        for entry in toNonEmpty {
            let run = board.piles[entry.from].cards
            if let top = board.piles[entry.to].top, run[entry.index].suit == top.suit { return entry.move }
        }
        if board.canDeal { return .deal }
        return toNonEmpty.first?.move ?? legal.first
    }
}
