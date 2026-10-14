/// ハノイの塔の純粋ロジック（#2003・企画倉庫）。
///
/// 盤は柱 3 本ぶんの配列で、各柱は**下から上へ**円盤の大きさ（1 が最小・`disks` が最大）を並べる。
/// 始めは左の柱（0）に全部が大きい順に積まれ、全部を右の柱（2）へ同じ並びで移したらクリア。
public enum HanoiLogic {
    public static let pegCount = 3
    /// 円盤の枚数として選べる範囲（難易度）。
    public static let diskRange = 3...7
    /// 初めて遊ぶときの枚数。
    public static let defaultDisks = 3
    /// 全部を移す先（右の柱）。
    public static let goalPeg = 2

    /// 置けない理由。画面に文言で出し、読み上げでも伝える。
    public enum Rejection: Equatable, Sendable {
        /// 取ろうとした柱に円盤が無い。
        case emptySource
        /// 小さい円盤の上に大きい円盤を置こうとした。
        case largerOnSmaller
    }

    /// 始めの盤。左の柱に `disks` 枚を大きい順に積む。
    public static func initial(disks: Int) -> [[Int]] {
        [Array((1...disks).reversed()), [], []]
    }

    /// 最少手数（2ⁿ−1 手）。
    public static func minimumMoves(disks: Int) -> Int {
        (1 << disks) - 1
    }

    /// 右の柱に全部が揃ったか。
    public static func isSolved(_ pegs: [[Int]], disks: Int) -> Bool {
        pegs.count == pegCount && pegs[goalPeg] == Array((1...disks).reversed())
    }

    /// 盤として正しいか（中断データの健全性検査）。1〜`disks` が 1 枚ずつあり、どの柱も下ほど大きい。
    public static func isValid(_ pegs: [[Int]], disks: Int) -> Bool {
        guard diskRange.contains(disks), pegs.count == pegCount else { return false }
        guard pegs.flatMap({ $0 }).sorted() == Array(1...disks) else { return false }
        return pegs.allSatisfy { peg in zip(peg, peg.dropFirst()).allSatisfy { $0 > $1 } }
    }

    /// `from` の柱のいちばん上を `to` の柱へ動かせるか。動かせないときは理由を返す。
    /// 同じ柱・範囲外の柱は呼び出し側で弾く（選び直しの操作なので理由を出さない）。
    public static func rejection(_ pegs: [[Int]], from: Int, to: Int) -> Rejection? {
        guard let disk = pegs[from].last else { return .emptySource }
        if let top = pegs[to].last, top < disk { return .largerOnSmaller }
        return nil
    }

    /// 1 手動かした盤。動かせなければ nil。
    public static func moving(_ pegs: [[Int]], from: Int, to: Int) -> [[Int]]? {
        guard pegs.indices.contains(from), pegs.indices.contains(to), from != to,
              rejection(pegs, from: from, to: to) == nil else { return nil }
        var result = pegs
        let disk = result[from].removeLast()
        result[to].append(disk)
        return result
    }

    /// 最少手数の手順（`from` の柱から `to` の柱へ `disks` 枚を移す）。テストで「必ず解ける」「最少手数が式どおり」を確かめる。
    public static func solution(disks: Int, from: Int = 0, to: Int = goalPeg) -> [(from: Int, to: Int)] {
        guard disks > 0 else { return [] }
        let via = 3 - from - to
        return solution(disks: disks - 1, from: from, to: via)
            + [(from, to)]
            + solution(disks: disks - 1, from: via, to: to)
    }
}
