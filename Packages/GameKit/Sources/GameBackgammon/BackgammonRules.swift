import Foundation

/// 進行ルール（純粋関数）。Model と CPU エンジンの両方がここだけを見る。
///
/// バックギャモン特有の「出た目は使えるだけ使わなければならない。片方しか使えないときは大きい目を優先する」
/// という制約を、**1 手ずつの合法手**として返す（`legalMoves`）。1 手目を打った後の残りの目でもう一度
/// 同じ関数を呼べば、自然に「最大限使う」手順だけが残る。
public enum BackgammonRules {
    /// 1 個の駒を 1 つの目で動かした結果。動かせなければ nil。
    ///
    /// - バーに駒があるあいだは、バーからの入場しか許さない。
    /// - 移動先に相手の駒が 2 個以上あれば止まれない。1 個なら叩く（`hits`）。
    /// - あがりは全駒が自陣に入ってから。ぴったりの目か、それより大きい目で「一番後ろの駒」だけあがれる。
    public static func move(
        from: Int, die: Int, board: BackgammonBoard, side: BackgammonSide
    ) -> BackgammonMove? {
        let n = BackgammonBoard.pointCount
        if board.bar(for: side) > 0 {
            guard from == BackgammonBoard.bar else { return nil }
            // 白は 24 ポイント側（添字 23）から入る: 目 d で添字 24 - d。黒は添字 d - 1。
            let to = side == .white ? n - die : die - 1
            guard let landing = landing(at: to, board: board, side: side) else { return nil }
            return BackgammonMove(from: from, to: to, die: die, hits: landing)
        }
        guard board.points.indices.contains(from), board.signedCount(at: from, for: side) > 0 else { return nil }
        let to = from + side.direction * die
        if board.points.indices.contains(to) {
            guard let landing = landing(at: to, board: board, side: side) else { return nil }
            return BackgammonMove(from: from, to: to, die: die, hits: landing)
        }
        // 盤の外 = あがり。
        guard board.canBearOff(side) else { return nil }
        let distance = side.normalized(from) + 1   // あがるのに必要なちょうどの目
        if die == distance {
            return BackgammonMove(from: from, to: BackgammonBoard.off, die: die, hits: false)
        }
        // 大きい目で余らせてあがれるのは、それより後ろに自分の駒が無いときだけ。
        guard die > distance else { return nil }
        for index in 0..<n where board.signedCount(at: index, for: side) > 0 {
            if side.normalized(index) + 1 > distance { return nil }
        }
        return BackgammonMove(from: from, to: BackgammonBoard.off, die: die, hits: false)
    }

    /// 止まれるなら「叩くか」を、止まれなければ nil を返す。
    private static func landing(at index: Int, board: BackgammonBoard, side: BackgammonSide) -> Bool? {
        let opponent = board.signedCount(at: index, for: side.opponent)
        if opponent >= 2 { return nil }
        return opponent == 1
    }

    /// 移動を盤に適用する。
    public static func apply(_ move: BackgammonMove, to board: BackgammonBoard, side: BackgammonSide) -> BackgammonBoard {
        var next = board
        let sign = side == .white ? 1 : -1
        if move.from == BackgammonBoard.bar {
            next.bar[side.rawValue] -= 1
        } else {
            next.points[move.from] -= sign
        }
        if move.to == BackgammonBoard.off {
            next.off[side.rawValue] += 1
        } else {
            if move.hits {
                next.points[move.to] = 0
                next.bar[side.opponent.rawValue] += 1
            }
            next.points[move.to] += sign
        }
        return next
    }

    /// その目で動かせる 1 手をすべて列挙する（「最大限使う」制約は掛けない素の候補）。
    static func rawMoves(board: BackgammonBoard, side: BackgammonSide, die: Int) -> [BackgammonMove] {
        if board.bar(for: side) > 0 {
            return move(from: BackgammonBoard.bar, die: die, board: board, side: side).map { [$0] } ?? []
        }
        var result: [BackgammonMove] = []
        for from in 0..<BackgammonBoard.pointCount where board.signedCount(at: from, for: side) > 0 {
            if let m = move(from: from, die: die, board: board, side: side) { result.append(m) }
        }
        return result
    }

    /// 残りの目でできる**最大限使い切る**手順をすべて列挙する。
    ///
    /// ゾロ目は 4 個の同じ目として渡す（`dice(for:)`）。ゾロ目でなければ 2 通りの順で試す。
    /// 1 個しか使えないときは大きい目を使う手順だけを残す（公式ルール）。
    public static func sequences(board: BackgammonBoard, side: BackgammonSide, dice: [Int]) -> [[BackgammonMove]] {
        guard !dice.isEmpty else { return [] }
        var best: [[BackgammonMove]] = []
        var bestLength = 0
        var seen = Set<[BackgammonMove]>()
        func search(_ board: BackgammonBoard, _ remaining: [Int], _ path: [BackgammonMove]) {
            var extended = false
            // 同じ目を 2 回試さない（ゾロ目・順序違いの重複を抑える）。
            var tried = Set<Int>()
            for (i, die) in remaining.enumerated() where !tried.contains(die) {
                tried.insert(die)
                var rest = remaining
                rest.remove(at: i)
                for m in rawMoves(board: board, side: side, die: die) {
                    extended = true
                    search(apply(m, to: board, side: side), rest, path + [m])
                }
            }
            if !extended && !path.isEmpty {
                if path.count > bestLength {
                    bestLength = path.count
                    best = []
                    seen = []
                }
                if path.count == bestLength, !seen.contains(path) {
                    seen.insert(path)
                    best.append(path)
                }
            }
        }
        search(board, dice, [])
        // 1 個しか使えないときは大きい目を優先する。
        if bestLength == 1, let larger = dice.max(), best.contains(where: { $0[0].die == larger }) {
            best = best.filter { $0[0].die == larger }
        }
        return best
    }

    /// いま打てる 1 手（ルール上、続きの手順で目を最大限使えるものだけ）。重複は除く。
    public static func legalMoves(board: BackgammonBoard, side: BackgammonSide, dice: [Int]) -> [BackgammonMove] {
        var result: [BackgammonMove] = []
        var seen = Set<BackgammonMove>()
        for seq in sequences(board: board, side: side, dice: dice) {
            let first = seq[0]
            if !seen.contains(first) { seen.insert(first); result.append(first) }
        }
        return result
    }

    /// 振った 2 個の目を「使える目の列」に直す。ゾロ目は 4 個。
    public static func dice(for roll: (Int, Int)) -> [Int] {
        roll.0 == roll.1 ? [roll.0, roll.0, roll.0, roll.0] : [roll.0, roll.1]
    }

    /// 盤の上に残った駒の合計が 15 個ずつになっているか（テスト・中断データの検証用）。
    public static func isConsistent(_ board: BackgammonBoard) -> Bool {
        guard board.points.count == BackgammonBoard.pointCount, board.bar.count == 2, board.off.count == 2 else { return false }
        for side in BackgammonSide.allCases {
            var total = board.bar(for: side) + board.off(for: side)
            for index in 0..<BackgammonBoard.pointCount { total += max(0, board.signedCount(at: index, for: side)) }
            if total != BackgammonBoard.checkersPerSide { return false }
            if board.bar(for: side) < 0 || board.off(for: side) < 0 { return false }
        }
        return true
    }
}
