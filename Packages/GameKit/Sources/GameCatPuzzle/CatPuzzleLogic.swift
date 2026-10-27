import Foundation
import CoreEngine

/// 盤の大きさ（難易度・#2250）。かんたん 6×6・ふつう 7×7・むずかしい 8×8・とことん 9×9。
/// `rawValue` は記録の区分キー・中断データにそのまま使う。
public enum CatPuzzleSize: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard, expert

    /// 1 辺のマス数 = 部屋の数 = 猫の数。
    public var side: Int {
        switch self {
        case .easy: 6
        case .normal: 7
        case .hard: 8
        case .expert: 9
        }
    }
}

/// 1 問ぶん。マスは行優先の番号（`row * side + col`）。
///
/// `rooms[cell]` がそのマスの部屋の番号（0 始まり・部屋の数は `side`）、`solution[row]` が
/// その行で猫がいる列（唯一の答え）。部屋は必ず上下左右につながった 1 かたまりで、
/// 答えの猫はそれぞれ別の部屋にいる。
public struct CatPuzzle: Codable, Equatable, Sendable {
    public let side: Int
    public let rooms: [Int]
    public let solution: [Int]

    public init(side: Int, rooms: [Int], solution: [Int]) {
        self.side = side
        self.rooms = rooms
        self.solution = solution
    }

    public var cellCount: Int { side * side }

    /// 答えの猫のマス（行の順）。
    public var solutionCells: [Int] { solution.enumerated().map { $0.offset * side + $0.element } }

    /// 部屋 `room` のマス（行優先の順）。
    public func cells(inRoom room: Int) -> [Int] {
        rooms.indices.filter { rooms[$0] == room }
    }
}

/// 置いた猫どうしの矛盾（#2250 の受け入れ条件「色だけでなく印でも示す」の元になる情報）。
/// 違反している行・列・部屋をまるごと帯で示せるよう、関わる猫のマスだけでなく、
/// 2 匹いる行・列・部屋の番号と、隣り合っている猫の組も持つ（会長 QA 2026-10-21・build 41）。
public struct CatPuzzleViolations: Equatable, Sendable {
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// 同じ行に 2 匹。
        case row
        /// 同じ列に 2 匹。
        case column
        /// 同じ部屋に 2 匹。
        case room
        /// 隣り合っている（ななめを含む）。
        case adjacent
    }

    /// 隣り合っている猫の組（`a` < `b`）。
    public struct Pair: Hashable, Sendable {
        public let a: Int
        public let b: Int
        public init(_ x: Int, _ y: Int) {
            a = min(x, y)
            b = max(x, y)
        }
    }

    /// 矛盾に関わっている猫のマス（両方の猫）。
    public var cells: Set<Int> = []
    public var kinds: Set<Kind> = []
    /// 2 匹以上いる行の番号。
    public var rows: Set<Int> = []
    /// 2 匹以上いる列の番号。
    public var columns: Set<Int> = []
    /// 2 匹以上いる部屋の番号。
    public var rooms: Set<Int> = []
    /// 隣り合っている猫の組。
    public var adjacentPairs: Set<Pair> = []

    public init(cells: Set<Int> = [], kinds: Set<Kind> = [],
                rows: Set<Int> = [], columns: Set<Int> = [], rooms: Set<Int> = [], adjacentPairs: Set<Pair> = []) {
        self.cells = cells
        self.kinds = kinds
        self.rows = rows
        self.columns = columns
        self.rooms = rooms
        self.adjacentPairs = adjacentPairs
    }

    public var isEmpty: Bool { cells.isEmpty }
}

/// おじさんちのねこさがしの純粋ロジック（#2250）。生成・解の数え上げ・矛盾の判定・ヒント。
///
/// 遊び方: 各部屋・各行・各列に猫がちょうど 1 匹。猫どうしは縦横ななめに隣り合わない。
public enum CatPuzzleLogic {

    // MARK: - 盤の基本

    /// 縦横ななめに隣り合っているか（同じマスは隣ではない）。
    public static func isAdjacent(_ a: Int, _ b: Int, side: Int) -> Bool {
        guard a != b else { return false }
        return abs(a / side - b / side) <= 1 && abs(a % side - b % side) <= 1
    }

    /// 上下左右の隣のマス。
    public static func neighbors4(of cell: Int, side: Int) -> [Int] {
        let row = cell / side, col = cell % side
        var result: [Int] = []
        result.reserveCapacity(4)
        if row > 0 { result.append(cell - side) }
        if row < side - 1 { result.append(cell + side) }
        if col > 0 { result.append(cell - 1) }
        if col < side - 1 { result.append(cell + 1) }
        return result
    }

    /// 行ごとの列の並びが「各列に 1 匹・隣の行と隣り合わない」答えの形か。
    public static func isValidPlacement(_ cols: [Int], side: Int) -> Bool {
        guard cols.count == side, Set(cols).count == side,
              cols.allSatisfy({ (0..<side).contains($0) }) else { return false }
        for row in 1..<side where abs(cols[row] - cols[row - 1]) <= 1 { return false }
        return true
    }

    /// `cells` が上下左右で 1 かたまりにつながっているか（空なら false）。
    static func isConnected(cells: [Int], side: Int) -> Bool {
        guard let start = cells.first else { return false }
        let members = Set(cells)
        var seen: Set<Int> = [start]
        var stack = [start]
        while let cell = stack.popLast() {
            for next in neighbors4(of: cell, side: side) where members.contains(next) && !seen.contains(next) {
                seen.insert(next)
                stack.append(next)
            }
        }
        return seen.count == members.count
    }

    /// 1 問として正しい形か（中断データの健全性検査にも使う）。部屋の番号が範囲内で、どの部屋も
    /// 空でなく 1 かたまり、答えが正しい並びで、答えの猫がそれぞれ別の部屋にいること。
    public static func isWellFormed(_ puzzle: CatPuzzle) -> Bool {
        let n = puzzle.side
        guard n >= 4, puzzle.rooms.count == n * n,
              puzzle.rooms.allSatisfy({ (0..<n).contains($0) }),
              isValidPlacement(puzzle.solution, side: n) else { return false }
        for room in 0..<n where !isConnected(cells: puzzle.cells(inRoom: room), side: n) { return false }
        return Set(puzzle.solutionCells.map { puzzle.rooms[$0] }).count == n
    }

    // MARK: - 判定

    /// 置いた猫どうしの矛盾。`cats` は猫を置いたマス。
    public static func violations(puzzle: CatPuzzle, cats: [Int]) -> CatPuzzleViolations {
        let n = puzzle.side
        var result = CatPuzzleViolations()
        guard cats.count >= 2 else { return result }
        for i in 0..<(cats.count - 1) {
            for j in (i + 1)..<cats.count {
                let a = cats[i], b = cats[j]
                var hit = false
                if a / n == b / n { result.kinds.insert(.row); result.rows.insert(a / n); hit = true }
                if a % n == b % n { result.kinds.insert(.column); result.columns.insert(a % n); hit = true }
                if puzzle.rooms[a] == puzzle.rooms[b] { result.kinds.insert(.room); result.rooms.insert(puzzle.rooms[a]); hit = true }
                if isAdjacent(a, b, side: n) { result.kinds.insert(.adjacent); result.adjacentPairs.insert(.init(a, b)); hit = true }
                if hit {
                    result.cells.insert(a)
                    result.cells.insert(b)
                }
            }
        }
        return result
    }

    /// 全部の猫が置けて矛盾が無いか。猫が `side` 匹で同じ行・列・部屋に 2 匹いなければ、
    /// 鳩の巣原理でどの行・列・部屋にもちょうど 1 匹になる。
    public static func isSolved(puzzle: CatPuzzle, cats: [Int]) -> Bool {
        cats.count == puzzle.side && violations(puzzle: puzzle, cats: cats).isEmpty
    }

    // MARK: - 解の数え上げ

    /// 部屋割り `rooms` に対する解（各部屋・行・列に 1 匹・隣り合わない置き方）の数を `limit` まで数える。
    /// 行ごとに列を選ぶ深さ優先で、使った列・部屋をビットで持つ（9×9 でも一瞬）。
    public static func countSolutions(side: Int, rooms: [Int], limit: Int) -> Int {
        var count = 0
        func search(row: Int, usedCols: Int, usedRooms: Int, previousCol: Int) {
            if count >= limit { return }
            if row == side {
                count += 1
                return
            }
            for col in 0..<side where usedCols & (1 << col) == 0 {
                if previousCol >= 0 && abs(col - previousCol) <= 1 { continue }
                let room = rooms[row * side + col]
                if usedRooms & (1 << room) != 0 { continue }
                search(row: row + 1, usedCols: usedCols | (1 << col), usedRooms: usedRooms | (1 << room), previousCol: col)
            }
        }
        search(row: 0, usedCols: 0, usedRooms: 0, previousCol: -1)
        return count
    }

    // MARK: - 生成

    /// 解がちょうど 1 つの問題を作る。同じ種（乱数の状態）からは同じ問題ができる（日替わり用）。
    ///
    /// 1. 答え（各列に 1 匹・隣の行と隣り合わない並び）を乱数で 1 つ置く。
    /// 2. 答えの猫のマスを種にして部屋を育てる（空きマスを、隣の部屋のうち接している面が多い部屋へ
    ///    足していく。部屋は必ず 1 かたまりになる）。
    /// 3. 解の数を数え、2 つ以上あれば部屋の境目のマスを隣の部屋へ付け替えて減らす（山登り）。
    ///    答えの猫のマスは動かさず、部屋は 2 マス以上・1 かたまりを保つ。
    ///    一定回数で 1 つにならなければ答えから作り直す。
    /// 4. 盤を乱数で回す・裏返し（8 通り）、部屋の番号を乱数で振り直す（`shuffled`）。
    ///    育てる段階では部屋 k の種が行 k の答えなので、そのままだと「玄関（部屋 6）の猫は必ず最下行」の
    ///    ように部屋と行の対応が毎回同じになり、慣れた解き手に答えが読めてしまう（#2250）。
    public static func generate<G: RandomNumberGenerator>(size: CatPuzzleSize, using generator: inout G) -> CatPuzzle {
        let n = size.side
        while true {
            let solution = randomPlacement(side: n, using: &generator)
            // 同じ答えで部屋を育て直すのは数回まで。育て方が悪ければ答えから変える。
            for _ in 0..<8 {
                var rooms = growRooms(side: n, solution: solution, using: &generator)
                var count = countSolutions(side: n, rooms: rooms, limit: 64)
                var stale = 0
                while count != 1 && stale < 150 {
                    stale += 1
                    // 盤が広いと、でたらめな付け替えでは別解がなかなか消えない。別解を 1 つ探し、
                    // それを壊す付け替え（別解の猫のマスを、別解の別の猫がいる部屋へ移す）を優先する。
                    let directed = count <= directedThreshold ? otherSolution(side: n, rooms: rooms, excluding: solution) : nil
                    guard let move = directed.flatMap({ directedMove(rooms: rooms, side: n, solution: solution, other: $0, using: &generator) })
                            ?? randomMove(rooms: rooms, side: n, solution: solution, using: &generator) else { break }
                    var trial = rooms
                    trial[move.cell] = move.room
                    let vacated = rooms[move.cell]
                    guard isConnected(cells: trial.indices.filter { trial[$0] == vacated }, side: n) else { continue }
                    let trialCount = countSolutions(side: n, rooms: trial, limit: 64)
                    // 減る手は必ず採り、同じ数の手はたまに採る（行き詰まりを抜けるため。毎回採ると部屋の形が崩れる）。
                    // 部屋の広さの偏りは `randomMove` の上限で抑える。
                    if trialCount < count || (trialCount == count && Int.random(in: 0..<3, using: &generator) == 0) {
                        if trialCount < count { stale = 0 }
                        rooms = trial
                        count = trialCount
                    }
                }
                if count == 1 {
                    return shuffled(CatPuzzle(side: n, rooms: rooms, solution: solution), using: &generator)
                }
            }
        }
    }

    /// 別解の数がこの値以下なら、別解を壊す付け替えを狙う（それより多いうちは、でたらめな付け替えで十分減る）。
    static let directedThreshold = 64

    /// 答え `excluding` 以外の解を 1 つ返す（無ければ nil）。
    static func otherSolution(side: Int, rooms: [Int], excluding solution: [Int]) -> [Int]? {
        var cols: [Int] = []
        func search(row: Int, usedCols: Int, usedRooms: Int) -> Bool {
            if row == side { return cols != solution }
            for col in 0..<side where usedCols & (1 << col) == 0 {
                if let previous = cols.last, abs(col - previous) <= 1 { continue }
                let room = rooms[row * side + col]
                if usedRooms & (1 << room) != 0 { continue }
                cols.append(col)
                if search(row: row + 1, usedCols: usedCols | (1 << col), usedRooms: usedRooms | (1 << room)) { return true }
                cols.removeLast()
            }
            return false
        }
        return search(row: 0, usedCols: 0, usedRooms: 0) ? cols : nil
    }

    /// 別解 `other` を壊す付け替え: 別解の猫のマス（答えの猫ではないもの）を、別解の別の猫がいる隣の部屋へ移す。
    /// 移すと別解の 1 つの部屋に猫が 2 匹になり、別解でなくなる。
    static func directedMove<G: RandomNumberGenerator>(
        rooms: [Int], side n: Int, solution: [Int], other: [Int], using generator: inout G
    ) -> (cell: Int, room: Int)? {
        var sizes = Array(repeating: 0, count: n)
        for room in rooms { sizes[room] += 1 }
        let limit = maxRoomSize(side: n)
        let otherCells = other.enumerated().map { $0.offset * n + $0.element }
        let otherRooms = Set(otherCells.map { rooms[$0] })
        var moves: [(cell: Int, room: Int)] = []
        for cell in otherCells where solution[cell / n] != cell % n && sizes[rooms[cell]] > 2 {
            for next in neighbors4(of: cell, side: n)
            where rooms[next] != rooms[cell] && otherRooms.contains(rooms[next]) && sizes[rooms[next]] < limit {
                moves.append((cell, rooms[next]))
            }
        }
        return moves.randomElement(using: &generator)
    }

    /// 解を変えずに見た目の並びを乱数で混ぜる: 盤の回転・裏返し（8 通りのどれか）と、部屋の番号の振り直し。
    /// 回転・裏返しでも「各行・各列に 1 匹」「ななめを含めて隣り合わない」「部屋は 1 かたまり」は保たれ、
    /// 解の数も変わらない。部屋の番号は名前・床の柄の割り当て（`CatPuzzleHouse`）に直結する。
    static func shuffled<G: RandomNumberGenerator>(_ puzzle: CatPuzzle, using generator: inout G) -> CatPuzzle {
        let n = puzzle.side
        let transpose = Bool.random(using: &generator)
        let flipRows = Bool.random(using: &generator)
        let flipCols = Bool.random(using: &generator)
        // 元の (row, col) → 新しい (row, col)。
        func map(_ row: Int, _ col: Int) -> (row: Int, col: Int) {
            var (r, c) = transpose ? (col, row) : (row, col)
            if flipRows { r = n - 1 - r }
            if flipCols { c = n - 1 - c }
            return (r, c)
        }
        var relabel = Array(0..<n)
        relabel.shuffle(using: &generator)
        var rooms = Array(repeating: 0, count: n * n)
        var solution = Array(repeating: 0, count: n)
        for row in 0..<n {
            for col in 0..<n {
                let to = map(row, col)
                rooms[to.row * n + to.col] = relabel[puzzle.rooms[row * n + col]]
            }
            let cat = map(row, puzzle.solution[row])
            solution[cat.row] = cat.col
        }
        return CatPuzzle(side: n, rooms: rooms, solution: solution)
    }

    /// 部屋の広さの上限（マス数）。これより広い部屋は作らない（間取りとして偏りすぎないように）。
    static func maxRoomSize(side: Int) -> Int { side * 2 }

    /// 日替わり問題の種。同じ日（端末のカレンダーの日付）なら同じ値。
    /// 日付の数字（20261021）をそのまま種にせず、`SplitMix64` で 1 回かき混ぜる（隣の日で似た問題にならないように）。
    public static func dailySeed(for date: Date, calendar: Calendar = .current) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = UInt64((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
        var mixer = SplitMix64(seed: day &+ 2250)
        return mixer.next()
    }

    /// 答えを乱数で 1 つ置く（行ごとに列の候補をシャッフルして深さ優先）。
    static func randomPlacement<G: RandomNumberGenerator>(side: Int, using generator: inout G) -> [Int] {
        var cols: [Int] = []
        _ = placeRow(side: side, cols: &cols, using: &generator)
        return cols
    }

    private static func placeRow<G: RandomNumberGenerator>(side: Int, cols: inout [Int], using generator: inout G) -> Bool {
        if cols.count == side { return true }
        let previous = cols.last
        var candidates = (0..<side).filter { col in
            !cols.contains(col) && (previous.map { abs(col - $0) > 1 } ?? true)
        }
        candidates.shuffle(using: &generator)
        for col in candidates {
            cols.append(col)
            if placeRow(side: side, cols: &cols, using: &generator) { return true }
            cols.removeLast()
        }
        return false
    }

    /// 答えの猫のマスを種に、部屋を育てて全マスを割り当てる。
    /// いちばん小さい部屋から順に 1 マスずつ広げる（部屋の広さが揃う）。広げる先は、その部屋と
    /// 接している面が多い空きマスを優先する（部屋が四角に近くなり、間取りらしく見える）。
    static func growRooms<G: RandomNumberGenerator>(side n: Int, solution: [Int], using generator: inout G) -> [Int] {
        var rooms = Array(repeating: -1, count: n * n)
        var sizes = Array(repeating: 1, count: n)
        for row in 0..<n { rooms[row * n + solution[row]] = row }
        var remaining = n * n - n
        while remaining > 0 {
            // 広げられる部屋（空きマスに接している部屋）のうち、いちばん小さいもの。同じ広さなら乱数で。
            var frontier: [Int: [Int]] = [:]
            for cell in 0..<(n * n) where rooms[cell] == -1 {
                for next in neighbors4(of: cell, side: n) where rooms[next] >= 0 {
                    frontier[rooms[next], default: []].append(cell)
                }
            }
            guard !frontier.isEmpty else { break }
            // 上限まで広がった部屋は、他に広げられる部屋がある限り広げない。
            let limit = maxRoomSize(side: n)
            if frontier.keys.contains(where: { sizes[$0] < limit }) {
                frontier = frontier.filter { sizes[$0.key] < limit }
            }
            let smallest = frontier.keys.map { sizes[$0] }.min()!
            let room = frontier.keys.filter { sizes[$0] == smallest }.sorted().randomElement(using: &generator)!
            // 同じマスが複数回入っている = その部屋と接している面が多い。面の数が最大のマスから選ぶ。
            var tally: [Int: Int] = [:]
            for cell in frontier[room]! { tally[cell, default: 0] += 1 }
            let best = tally.values.max()!
            let threshold = Int.random(in: 0..<4, using: &generator) == 0 ? 1 : best
            let cell = tally.filter { $0.value >= threshold }.keys.sorted().randomElement(using: &generator)!
            rooms[cell] = room
            sizes[room] += 1
            remaining -= 1
        }
        return rooms
    }

    /// 山登りの 1 手: 部屋の境目にあるマスを、隣の部屋へ付け替える候補を 1 つ選ぶ。
    /// 答えの猫のマスと、2 マスしかない部屋のマスは動かさず、上限まで広がった部屋へは足さない。
    static func randomMove<G: RandomNumberGenerator>(
        rooms: [Int], side n: Int, solution: [Int], using generator: inout G
    ) -> (cell: Int, room: Int)? {
        let fixed = Set(solution.enumerated().map { $0.offset * n + $0.element })
        var sizes = Array(repeating: 0, count: n)
        for room in rooms { sizes[room] += 1 }
        let limit = maxRoomSize(side: n)
        var moves: [(cell: Int, room: Int)] = []
        for cell in 0..<(n * n) where !fixed.contains(cell) && sizes[rooms[cell]] > 2 {
            for next in neighbors4(of: cell, side: n) where rooms[next] != rooms[cell] && sizes[rooms[next]] < limit {
                moves.append((cell, rooms[next]))
            }
        }
        return moves.randomElement(using: &generator)
    }
}
