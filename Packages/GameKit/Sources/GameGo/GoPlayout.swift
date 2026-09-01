import Foundation

/// ランダム対局（プレイアウト）。MCTS の評価と、終局時の簡易死活判定の両方が使う。
///
/// 2 つのルールだけを入れている:
/// 1. **自分の眼は埋めない** — 埋めさせると生きている自分の石を自分で殺し続け、対局が終わらない。
/// 2. **打てる手（眼を除く）が無くなったらパス** — これで必ず両者パスに到達する。
///
/// 手数の上限も置く（交点数の 3 倍）。取り合いが続く病的な局面でも必ず止まるので、
/// 「必ず終局する」（#398 のプロパティテスト b）が構造的に保証される。
public enum GoPlayout {
    /// 交点数に対する手数上限の倍率。
    public static let moveLimitFactor = 3

    /// 両者パス（または手数上限）まで打ち切る。
    public static func run(_ state: inout GoState, random: inout GoRandom) {
        let limit = state.board.pointCount * moveLimitFactor
        var played = 0
        while !state.isTwoPassEnd, played < limit {
            state.play(move(in: state, random: &random))
            played += 1
        }
    }

    /// 眼を埋めない合法手をランダムに 1 つ。無ければパス。
    public static func move(in state: GoState, random: inout GoRandom) -> GoMove {
        var candidates = emptyPoints(of: state.board)
        let color = state.sideToMove
        while !candidates.isEmpty {
            let pick = random.index(below: candidates.count)
            let point = candidates[pick]
            candidates.swapAt(pick, candidates.count - 1)
            candidates.removeLast()
            if state.isSimpleEye(point, for: color) { continue }
            if state.isLegal(.play(point)) { return .play(point) }
        }
        return .pass
    }

    /// 眼を埋めない合法手の全量。MCTS の候補手に使う。
    public static func candidateMoves(in state: GoState) -> [GoMove] {
        let color = state.sideToMove
        var moves: [GoMove] = []
        for point in emptyPoints(of: state.board) {
            guard !state.isSimpleEye(point, for: color) else { continue }
            if state.isLegal(.play(point)) { moves.append(.play(point)) }
        }
        return moves
    }

    static func emptyPoints(of board: GoBoard) -> [GoPoint] {
        var result: [GoPoint] = []
        result.reserveCapacity(board.pointCount)
        for row in 0..<board.size {
            for col in 0..<board.size where board[row, col] == nil {
                result.append(GoPoint(row: row, col: col))
            }
        }
        return result
    }
}
