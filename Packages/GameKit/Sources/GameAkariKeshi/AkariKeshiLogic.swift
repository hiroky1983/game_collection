/// 明かり消しパズルの純粋ロジック（#1883）。盤は長さ 25 の配列（行優先）で、true が点灯。
///
/// マスを押すと、そのマスと上下左右（盤の中にあるものだけ）の明かりが入れ替わる。全部消えたらクリア。
/// 押す順番は結果に関係せず、同じマスを 2 回押すと元に戻るので、解は「押すマスの集合」で表せる。
public enum AkariKeshiLogic {
    public static let size = 5
    public static let cellCount = size * size

    /// 全部消えた盤。
    public static let cleared = [Bool](repeating: false, count: cellCount)

    /// `index` を押したときに入れ替わるマス（自分 + 盤の中にある上下左右）。
    public static func toggled(by index: Int) -> [Int] {
        guard (0..<cellCount).contains(index) else { return [] }
        let row = index / size
        let col = index % size
        var cells = [index]
        if row > 0 { cells.append(index - size) }
        if row < size - 1 { cells.append(index + size) }
        if col > 0 { cells.append(index - 1) }
        if col < size - 1 { cells.append(index + 1) }
        return cells
    }

    /// 盤の形が正しいか（中断データの健全性検査にも使う）。
    public static func isValid(_ board: [Bool]) -> Bool { board.count == cellCount }

    public static func isCleared(_ board: [Bool]) -> Bool { isValid(board) && !board.contains(true) }

    /// `index` を押したあとの盤。盤の外を押しても何も変わらない。
    public static func press(_ board: [Bool], at index: Int) -> [Bool] {
        guard isValid(board) else { return board }
        var result = board
        for cell in toggled(by: index) { result[cell].toggle() }
        return result
    }

    /// 全部消えた盤から `cells` を押した盤（逆生成）。この盤は `cells` を押せば必ず全部消える。
    public static func board(pressing cells: Set<Int>) -> [Bool] {
        cells.reduce(cleared) { press($0, at: $1) }
    }

    /// `board` を全部消せる押し方（押すマスの集合）をすべて返す。解けない盤は空。
    ///
    /// 「明かり追い」で求める: 1 行目の押し方（2⁵ = 32 通り）を決めると、2 行目以降は「真上が点いている
    /// マスだけ押す」で一意に決まる。最後の行まで消えた押し方だけが解。5×5 の盤は解けるなら解がちょうど
    /// 4 通りある（何も変えない押し方が 3 つあるため）。
    public static func solutions(_ board: [Bool]) -> [Set<Int>] {
        guard isValid(board) else { return [] }
        var result: [Set<Int>] = []
        for firstRow in 0..<(1 << size) {
            var lit = board
            var pressed = Set<Int>()
            for col in 0..<size where firstRow & (1 << col) != 0 {
                lit = press(lit, at: col)
                pressed.insert(col)
            }
            for row in 1..<size {
                for col in 0..<size where lit[(row - 1) * size + col] {
                    let index = row * size + col
                    lit = press(lit, at: index)
                    pressed.insert(index)
                }
            }
            if !lit.contains(true) { result.append(pressed) }
        }
        return result
    }

    /// 全部消せる盤か。
    public static func isSolvable(_ board: [Bool]) -> Bool { !solutions(board).isEmpty }

    /// 全部消すのに要る最少の押し数。解けない盤は nil。
    public static func minimumPresses(_ board: [Bool]) -> Int? {
        solutions(board).map(\.count).min()
    }

    /// 最少の押し数で消せる押し方がただ 1 通りか。
    public static func hasUniqueShortestSolution(_ board: [Bool]) -> Bool {
        let counts = solutions(board).map(\.count).sorted()
        guard let shortest = counts.first else { return false }
        return counts.dropFirst().first.map { $0 > shortest } ?? true
    }

    /// 問題を作る（逆生成）。全部消えた盤から、ばらばらのマスを `presses` 個押す。
    ///
    /// ランダムに点けた盤は解けないものが混ざるので使わない（Issue #1883）。さらに、押したマスの組が
    /// **ただ 1 つの最短の解**になる盤だけを採る（最短の押し方が 2 通りある盤や、もっと少ない手で消せる盤は
    /// 引き直す）。こうすると「最短 N 手」の表示がそのまま正しく、答えが 1 つに決まる。
    public static func generate<G: RandomNumberGenerator>(
        presses: Int, using generator: inout G
    ) -> (board: [Bool], solution: Set<Int>) {
        precondition((1...maxPresses).contains(presses), "押す数は 1〜\(maxPresses)")
        while true {
            let cells = Set(Array(0..<cellCount).shuffled(using: &generator).prefix(presses))
            let board = board(pressing: cells)
            let found = solutions(board)
            let shortest = found.map(\.count).min()
            if shortest == presses, found.filter({ $0.count == presses }) == [cells] {
                return (board, cells)
            }
        }
    }

    /// 生成で使える押す数の上限。何も変えない押し方（重さ 12・12・16）の半分を超えると、
    /// 最短の解が 1 つに決まる盤がほとんど作れなくなる。
    public static let maxPresses = 10
}
