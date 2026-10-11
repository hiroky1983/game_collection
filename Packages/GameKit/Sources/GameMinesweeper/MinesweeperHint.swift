import Foundation

/// 盤のマスの位置（ヒントの出力・ヒントの印に使う・#2024）。
public struct MinesweeperPoint: Hashable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// マインスイーパーのヒント（#2024）。開いている数字だけから「理屈で安全と言えるマス」を探す純粋関数。
///
/// **地雷の場所は推論に使わない**。入力の `Observation` に地雷の有無を載せる口が無い（型で閉じている）ので、
/// 呼び出し側が誤って `isMine` を渡すことはできない。旗はプレイヤーの推測で間違いうるため、
/// 推論では「未開のマス」として扱い（旗が正しいと信じない）、答えの候補からだけ外す。
///
/// 推論は「数字 = 確定地雷数なら残りは安全」「数字 = 未開の数なら全部地雷」の繰り返しと、
/// 2 つの数字の包含関係（片方の未開マスがもう片方の部分集合なら、差の部分の地雷数が決まる）。
/// 決められる限り繰り返す。これで決まらない局面は `safeCells` が空を返し、モデルが運任せの扱いに倒す。
public enum MinesweeperHint {
    /// 推論に渡すマスの見え方。
    public enum Observation: Equatable, Sendable {
        /// 未開で旗なし（`?` を含む）。開けるマス。
        case hidden
        /// 旗が立っている。推論では未開として扱い、答えの候補にはしない。
        case flagged
        /// 開いている数字（0 も含む）。
        case number(Int)
    }

    /// 理屈で安全と言えるマスを行・列の昇順で返す。旗のマスは含めない。無ければ空。
    public static func safeCells(in grid: [[Observation]]) -> [MinesweeperPoint] {
        let rows = grid.count
        guard rows > 0, let cols = grid.first?.count, cols > 0,
              grid.allSatisfy({ $0.count == cols }) else { return [] }

        // 数字の制約: 「この未開マスの集合に、ちょうど n 個の地雷がある」。
        var constraints: [Constraint] = []
        for r in 0..<rows {
            for c in 0..<cols {
                guard case .number(let n) = grid[r][c] else { continue }
                var cells = Set<Int>()
                for dr in -1...1 {
                    for dc in -1...1 where !(dr == 0 && dc == 0) {
                        let nr = r + dr, nc = c + dc
                        guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                        if case .number = grid[nr][nc] { continue }
                        cells.insert(nr * cols + nc)
                    }
                }
                if !cells.isEmpty { constraints.append(Constraint(cells: cells, mines: n)) }
            }
        }

        var safe = Set<Int>()
        var mines = Set<Int>()
        var changed = true
        while changed {
            changed = false
            // 確定したマスを取り除き、残りが 0 個 / 全部地雷なら新しく確定させる。
            for i in constraints.indices {
                constraints[i].cells.subtract(safe)
                let knownMines = constraints[i].cells.intersection(mines)
                constraints[i].cells.subtract(knownMines)
                constraints[i].mines -= knownMines.count
                let c = constraints[i]
                if c.cells.isEmpty { continue }
                if c.mines == 0 {
                    safe.formUnion(c.cells); changed = true
                } else if c.mines == c.cells.count {
                    mines.formUnion(c.cells); changed = true
                }
            }
            if changed { continue }
            // 包含関係: A ⊂ B なら、B − A の地雷数は B − A の差。
            outer: for a in constraints where !a.cells.isEmpty {
                for b in constraints where b.cells.count > a.cells.count && a.cells.isSubset(of: b.cells) {
                    let diff = b.cells.subtracting(a.cells)
                    let diffMines = b.mines - a.mines
                    if diffMines == 0 {
                        safe.formUnion(diff); changed = true; break outer
                    } else if diffMines == diff.count {
                        mines.formUnion(diff); changed = true; break outer
                    }
                }
            }
        }

        return safe.sorted().compactMap { index in
            let r = index / cols, c = index % cols
            // 旗は推論に使わないが、旗のマスを「開け」と指すのは旗を外させる指図になるので外す。
            guard grid[r][c] == .hidden else { return nil }
            return MinesweeperPoint(row: r, col: c)
        }
    }

    private struct Constraint {
        var cells: Set<Int>
        var mines: Int
    }
}
