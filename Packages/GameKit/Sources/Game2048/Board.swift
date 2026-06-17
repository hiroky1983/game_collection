import Foundation

/// スワイプ方向。
public enum Direction: CaseIterable, Sendable {
    case up, down, left, right
}

/// 1 方向スライドの結果。
public struct SlideResult: Equatable, Sendable {
    public let board: [[Int]]
    public let gained: Int
    public let moved: Bool
}

/// 2048 の純粋ロジック。SwiftUI 非依存・決定的（乱数は呼び出し側が注入）なので網羅的にテストできる。
/// コアは「左方向の 1 行スライド＆マージ」だけ。残り 3 方向は盤の転置・反転で使い回す。
public enum Game2048Logic {
    public static let size = 4

    /// 1 行を左へ寄せ、隣接同値をマージし、再度寄せる。各タイルは 1 回の操作で 1 度だけマージされる。
    /// 戻り値: 整形後の行と、マージで得たスコア。
    public static func slideRowLeft(_ row: [Int]) -> (row: [Int], gained: Int) {
        let tiles = row.filter { $0 != 0 }
        var result: [Int] = []
        var gained = 0
        var i = 0
        while i < tiles.count {
            if i + 1 < tiles.count, tiles[i] == tiles[i + 1] {
                let merged = tiles[i] * 2
                result.append(merged)
                gained += merged
                i += 2
            } else {
                result.append(tiles[i])
                i += 1
            }
        }
        while result.count < row.count { result.append(0) }
        return (result, gained)
    }

    /// 盤全体を指定方向へスライドする。
    public static func slide(_ board: [[Int]], _ direction: Direction) -> SlideResult {
        // 各方向を「左スライド」に正規化するための行列。
        let lines: [[Int]]
        switch direction {
        case .left:  lines = board
        case .right: lines = board.map { $0.reversed() }
        case .up:    lines = transpose(board)
        case .down:  lines = transpose(board).map { $0.reversed() }
        }

        var gained = 0
        let slid = lines.map { line -> [Int] in
            let r = slideRowLeft(line)
            gained += r.gained
            return r.row
        }

        // 元の向きへ戻す。
        let newBoard: [[Int]]
        switch direction {
        case .left:  newBoard = slid
        case .right: newBoard = slid.map { $0.reversed() }
        case .up:    newBoard = transpose(slid)
        case .down:  newBoard = transpose(slid.map { $0.reversed() })
        }

        return SlideResult(board: newBoard, gained: gained, moved: newBoard != board)
    }

    /// 空きマス座標の一覧。
    public static func emptyCells(_ board: [[Int]]) -> [(row: Int, col: Int)] {
        var cells: [(Int, Int)] = []
        for r in board.indices {
            for c in board[r].indices where board[r][c] == 0 {
                cells.append((r, c))
            }
        }
        return cells
    }

    /// ゲームオーバー判定: 空きが無く、上下左右いずれにも同値の隣接が無い。
    public static func isGameOver(_ board: [[Int]]) -> Bool {
        let n = board.count
        for r in 0..<n {
            for c in 0..<n {
                if board[r][c] == 0 { return false }
                if c + 1 < n, board[r][c] == board[r][c + 1] { return false }
                if r + 1 < n, board[r][c] == board[r + 1][c] { return false }
            }
        }
        return true
    }

    /// 空盤を生成する。
    public static func emptyBoard() -> [[Int]] {
        Array(repeating: Array(repeating: 0, count: size), count: size)
    }

    private static func transpose(_ b: [[Int]]) -> [[Int]] {
        let n = b.count
        var out = b
        for r in 0..<n {
            for c in 0..<n {
                out[r][c] = b[c][r]
            }
        }
        return out
    }
}
