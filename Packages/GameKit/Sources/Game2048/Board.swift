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

    /// コンティニュー（リワード広告視聴後の復活）で確保する空きマス数。
    public static let continueEmptyCells = 4

    /// コンティニュー用の復活処理。空きマスが `targetEmpty` 個になるまで、盤上の最小値のタイルから
    /// 順に取り除く。取り除く順は「値の昇順 →（同値なら）行・列の昇順」で完全に決定的（乱数を使わない）。
    /// プレイヤーの成果を壊さないよう、盤上の最大値のタイルは取り除かない。
    ///
    /// 終局盤面は定義上必ず空きマス 0 なので、実際の挙動は「最小値のタイルを 4 個消す」になる。
    /// 空きマスが 1 個でもあれば動かせる方向が必ず存在する（4 方向すべてで不変 = 各行が
    /// 満杯か空、かつ各列も満杯か空 となり、空きマスとタイルが同時に存在する盤では矛盾する）ため、
    /// 1 手で沸くタイルが高々 1 個であることと併せて **最低 4 手** の続行が保証される（#122）。
    ///
    /// 最大タイルを保護しても除去候補が枯れることはない: 終局盤面で最大値のタイル同士は
    /// 隣接できない（隣接していればマージ可能で終局しない）ため 4x4 では高々 8 個、
    /// 残る 8 個以上が除去候補になる。
    public static func revive(_ board: [[Int]], targetEmpty: Int = continueEmptyCells) -> [[Int]] {
        var result = board
        let shortage = targetEmpty - emptyCells(board).count
        guard shortage > 0 else { return result }

        let tiles = board.indices.flatMap { r in
            board[r].indices.compactMap { c -> (value: Int, row: Int, col: Int)? in
                board[r][c] == 0 ? nil : (board[r][c], r, c)
            }
        }
        guard let highest = tiles.map(\.value).max() else { return result }

        let removable = tiles
            .filter { $0.value != highest }
            .sorted { ($0.value, $0.row, $0.col) < ($1.value, $1.row, $1.col) }

        for tile in removable.prefix(shortage) {
            result[tile.row][tile.col] = 0
        }
        return result
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
