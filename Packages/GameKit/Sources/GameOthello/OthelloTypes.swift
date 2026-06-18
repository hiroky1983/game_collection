import Foundation

public let othelloBoardSize = 8

public enum OthelloStone: Int, Codable, Equatable, Sendable {
    case black = 0, white = 1
    public var opponent: OthelloStone { self == .black ? .white : .black }
}

public struct OthelloBoard: Equatable, Sendable {
    public private(set) var cells: [OthelloStone?]

    public init() {
        var c = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        let m = othelloBoardSize / 2
        c[(m-1) * othelloBoardSize + (m-1)] = .white
        c[(m-1) * othelloBoardSize +  m   ] = .black
        c[ m    * othelloBoardSize + (m-1)] = .black
        c[ m    * othelloBoardSize +  m   ] = .white
        cells = c
    }

    public init(cells: [OthelloStone?]) { self.cells = cells }

    public subscript(row: Int, col: Int) -> OthelloStone? {
        get { cells[row * othelloBoardSize + col] }
        set { cells[row * othelloBoardSize + col] = newValue }
    }

    private static let dirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

    public func flippable(row: Int, col: Int, stone: OthelloStone) -> [(Int, Int)] {
        guard self[row, col] == nil else { return [] }
        var result: [(Int, Int)] = []
        for (dr, dc) in Self.dirs {
            var r = row + dr, c = col + dc
            var line: [(Int, Int)] = []
            while r >= 0, r < othelloBoardSize, c >= 0, c < othelloBoardSize,
                  self[r, c] == stone.opponent {
                line.append((r, c)); r += dr; c += dc
            }
            if !line.isEmpty, r >= 0, r < othelloBoardSize, c >= 0, c < othelloBoardSize,
               self[r, c] == stone {
                result.append(contentsOf: line)
            }
        }
        return result
    }

    public func isValid(row: Int, col: Int, stone: OthelloStone) -> Bool {
        !flippable(row: row, col: col, stone: stone).isEmpty
    }

    public func validMoves(for stone: OthelloStone) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for r in 0..<othelloBoardSize {
            for c in 0..<othelloBoardSize where isValid(row: r, col: c, stone: stone) {
                result.append((r, c))
            }
        }
        return result
    }

    public mutating func place(row: Int, col: Int, stone: OthelloStone) {
        let toFlip = flippable(row: row, col: col, stone: stone)
        self[row, col] = stone
        for (r, c) in toFlip { self[r, c] = stone }
    }

    public func count(for stone: OthelloStone) -> Int { cells.filter { $0 == stone }.count }
    public var totalPieces: Int { cells.compactMap { $0 }.count }
    public var isFull: Bool { !cells.contains(nil) }
}
