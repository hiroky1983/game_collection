import Foundation
@testable import GameGo

/// テスト用の盤面リテラル。
///
/// ルールの正誤は「どの石が取られるか」を目で追えないと確かめようがないので、参照局面は
/// 図のまま書けるようにする（`.` 空点 / `X` 黒 / `O` 白）。行数 = 列数 = 路数。
enum GoDiagram {
    static func board(_ rows: [String]) -> GoBoard {
        let size = rows.count
        var board = GoBoard(size: size)
        for (row, line) in rows.enumerated() {
            let chars = Array(line)
            precondition(chars.count == size, "\(row) 行目の長さが \(size) ではありません: \(line)")
            for (col, char) in chars.enumerated() {
                switch char {
                case "X", "x", "#": board[row, col] = .black
                case "O", "o", "@": board[row, col] = .white
                case ".", " ":      board[row, col] = nil
                default: preconditionFailure("知らない記号: \(char)")
                }
            }
        }
        return board
    }

    static func state(_ rows: [String], to sideToMove: GoStone, tracksSuperko: Bool = true) -> GoState {
        GoState(board: board(rows), sideToMove: sideToMove, tracksSuperko: tracksSuperko)
    }

    /// 盤面を図に戻す（`#expect` が落ちたときに読める形で出すため）。
    static func text(_ board: GoBoard) -> String {
        (0..<board.size).map { row in
            (0..<board.size).map { col -> String in
                switch board[row, col] {
                case .black: return "X"
                case .white: return "O"
                case nil:    return "."
                }
            }.joined()
        }.joined(separator: "\n")
    }
}
