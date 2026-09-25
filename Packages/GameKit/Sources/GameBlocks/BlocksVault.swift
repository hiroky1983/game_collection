import Foundation

/// 金庫ブロック（#1250）: 壊れない壁（`BlockKind.vaultWall`）で囲った箱と、その中身のグループ。
///
/// **グループはレイアウトから自動で決まる**（別の記法は持たない）。地続き（上下左右）の
/// `w` を 1 つの金庫とみなし、その外接矩形に入っている壊せるブロックが中身になる。
/// 入り口は「壁の輪の切れ目」で、レイアウトでは `.`（または壊せるブロック）として書く。
/// 隣り合う金庫は壁が繋がらないよう 1 マス以上あけること（繋がると 1 つの金庫になる）。
///
/// 壁は中身を壊した数に比例して 1 枚ずつ開き、中身が空になった時点で残りがすべて消える。
public struct BlocksVault: Equatable, Sendable {
    public struct Cell: Hashable, Sendable {
        public let row: Int
        public let column: Int
    }

    /// 壁のマス。**開く順**に並べてある（下の行から、同じ行では左から）。
    /// 球は下から来るので、入り口のある下の段から広がるようにする。
    public let wallCells: [Cell]
    /// 中身（壊せるブロック）のマス。
    public let contentCells: Set<Cell>
    /// これまでに壊した中身の数。
    public private(set) var destroyedContents = 0
    /// これまでに開いた壁の数。
    public private(set) var wallsOpened = 0

    public var isEmpty: Bool { destroyedContents >= contentCells.count }

    /// 壊した中身の数に対して、開いているべき壁の数。
    ///
    /// 中身 N 個・壁 W 枚なら、i 個壊した時点で `i * W / N` 枚（切り捨て）。N 個目で W 枚に届くので、
    /// 空にした瞬間に壁は残らない。
    var wallsDue: Int {
        guard !contentCells.isEmpty else { return wallCells.count }
        return destroyedContents * wallCells.count / contentCells.count
    }

    /// 中身を 1 個壊したことを数え、新しく開く壁のマスを返す。
    mutating func recordDestroyed() -> [Cell] {
        destroyedContents += 1
        let due = min(wallsDue, wallCells.count)
        let opened = Array(wallCells[wallsOpened..<due])
        wallsOpened = due
        return opened
    }

    /// レイアウトから金庫を検出する。
    static func detect(in blocks: [[Block?]]) -> [BlocksVault] {
        var visited = Set<Cell>()
        var vaults: [BlocksVault] = []
        for row in blocks.indices {
            for column in blocks[row].indices {
                let start = Cell(row: row, column: column)
                guard isWall(start, in: blocks), !visited.contains(start) else { continue }
                var component: [Cell] = []
                var stack = [start]
                visited.insert(start)
                while let cell = stack.popLast() {
                    component.append(cell)
                    for next in [
                        Cell(row: cell.row - 1, column: cell.column), Cell(row: cell.row + 1, column: cell.column),
                        Cell(row: cell.row, column: cell.column - 1), Cell(row: cell.row, column: cell.column + 1),
                    ] where isWall(next, in: blocks) && !visited.contains(next) {
                        visited.insert(next)
                        stack.append(next)
                    }
                }
                let rows = component.map(\.row)
                let columns = component.map(\.column)
                var contents = Set<Cell>()
                for r in rows.min()!...rows.max()! {
                    for c in columns.min()!...columns.max()! where blocks[r][c]?.isBreakable == true {
                        contents.insert(Cell(row: r, column: c))
                    }
                }
                let ordered = component.sorted { ($0.row, -$0.column) > ($1.row, -$1.column) }
                vaults.append(BlocksVault(wallCells: ordered, contentCells: contents))
            }
        }
        return vaults
    }

    private static func isWall(_ cell: Cell, in blocks: [[Block?]]) -> Bool {
        guard cell.row >= 0, cell.row < blocks.count,
              cell.column >= 0, cell.column < blocks[cell.row].count else { return false }
        return blocks[cell.row][cell.column]?.kind == .vaultWall
    }
}
