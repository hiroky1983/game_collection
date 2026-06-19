import Foundation

/// バックトラッキングで完成グリッドを生成し、唯一解を保ちながらセルを削除するパズル生成エンジン。
public enum SudokuEngine {

    /// 指定難易度のパズルを生成して返す。
    /// - Returns: `board`（空セルあり）と `solution`（完全正解）のタプル。
    public static func generate(difficulty: Int) -> (board: [Int], solution: [Int]) {
        var solution = [Int](repeating: 0, count: 81)
        _ = fill(&solution, 0)

        let removeCount: Int
        switch difficulty {
        case 0:  removeCount = Int.random(in: 30...35)
        case 1:  removeCount = Int.random(in: 40...45)
        default: removeCount = Int.random(in: 46...50)
        }

        var board = solution
        var removed = 0
        for idx in (0..<81).shuffled() {
            guard removed < removeCount else { break }
            let backup = board[idx]
            board[idx] = 0
            var copy = board
            if countSolutions(&copy, limit: 2) == 1 {
                removed += 1
            } else {
                board[idx] = backup
            }
        }
        return (board, solution)
    }

    // MARK: - Private

    private static func fill(_ grid: inout [Int], _ pos: Int) -> Bool {
        if pos == 81 { return true }
        for d in (1...9).shuffled() {
            if isValid(grid, pos, d) {
                grid[pos] = d
                if fill(&grid, pos + 1) { return true }
                grid[pos] = 0
            }
        }
        return false
    }

    private static func countSolutions(_ grid: inout [Int], limit: Int) -> Int {
        guard let pos = grid.firstIndex(of: 0) else { return 1 }
        var count = 0
        for d in 1...9 {
            guard isValid(grid, pos, d) else { continue }
            grid[pos] = d
            count += countSolutions(&grid, limit: limit)
            grid[pos] = 0
            if count >= limit { break }
        }
        return count
    }

    private static func isValid(_ grid: [Int], _ pos: Int, _ d: Int) -> Bool {
        let r = pos / 9, c = pos % 9
        for i in 0..<9 {
            if grid[r * 9 + i] == d || grid[i * 9 + c] == d { return false }
        }
        let br = (r / 3) * 3, bc = (c / 3) * 3
        for dr in 0..<3 {
            for dc in 0..<3 {
                if grid[(br + dr) * 9 + bc + dc] == d { return false }
            }
        }
        return true
    }
}
