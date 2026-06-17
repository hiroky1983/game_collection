import Foundation

public let gomokuBoardSize = 15

public enum GomokuStone: Int, Codable, Equatable, Sendable {
    case black = 0, white = 1
    public var opponent: GomokuStone { self == .black ? .white : .black }
}

public struct GomokuBoard: Equatable, Sendable {
    public private(set) var cells: [GomokuStone?]

    public init() {
        cells = Array(repeating: nil, count: gomokuBoardSize * gomokuBoardSize)
    }

    public init(cells: [GomokuStone?]) {
        self.cells = cells
    }

    public subscript(row: Int, col: Int) -> GomokuStone? {
        get { cells[row * gomokuBoardSize + col] }
        set { cells[row * gomokuBoardSize + col] = newValue }
    }

    public func checkWin(row: Int, col: Int) -> Bool {
        guard let stone = self[row, col] else { return false }
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var count = 1
            for sign in [-1, 1] {
                var r = row + dr * sign, c = col + dc * sign
                while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && self[r, c] == stone {
                    count += 1; r += dr * sign; c += dc * sign
                }
            }
            if count >= 5 { return true }
        }
        return false
    }

    public var isFull: Bool { !cells.contains(nil) }
    public var moveCount: Int { cells.compactMap { $0 }.count }
}
