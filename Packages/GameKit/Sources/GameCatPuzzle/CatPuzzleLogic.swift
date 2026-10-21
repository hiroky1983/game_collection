import Foundation
import CoreEngine

/// 盤の大きさ（難易度・#2250）。かんたん 6×6・ふつう 7×7・むずかしい 8×8。
/// `rawValue` は記録の区分キー・中断データにそのまま使う。
public enum CatPuzzleSize: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard

    /// 1 辺のマス数 = 部屋の数 = 猫の数。
    public var side: Int {
        switch self {
        case .easy: 6
        case .normal: 7
        case .hard: 8
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

    /// 矛盾に関わっている猫のマス（両方の猫）。
    public var cells: Set<Int> = []
    public var kinds: Set<Kind> = []

    public init(cells: Set<Int> = [], kinds: Set<Kind> = []) {
        self.cells = cells
        self.kinds = kinds
    }

    public var isEmpty: Bool { cells.isEmpty }
}

/// ヒント 1 回ぶんの中身（`CatPuzzleLogic.hint`）。`placed` に猫を置き、`removed` の猫を × に変える。
public struct CatPuzzleHint: Equatable, Sendable {
    /// 対象の部屋（`CatPuzzle.rooms` の値）。
    public let room: Int
    /// 猫を置くマス。部屋の答えの猫がすでにあれば nil。
    public let placed: Int?
    /// × に変える、答えでない位置の猫のマス（昇順）。
    public let removed: [Int]

    public init(room: Int, placed: Int?, removed: [Int]) {
        self.room = room
        self.placed = placed
        self.removed = removed
    }
}

/// おじさんの飼い猫パズルの純粋ロジック（#2250）。生成・解の数え上げ・矛盾の判定・ヒント。
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
                if a / n == b / n { result.kinds.insert(.row); hit = true }
                if a % n == b % n { result.kinds.insert(.column); hit = true }
                if puzzle.rooms[a] == puzzle.rooms[b] { result.kinds.insert(.room); hit = true }
                if isAdjacent(a, b, side: n) { result.kinds.insert(.adjacent); hit = true }
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

    // MARK: - ヒント

    /// 次のヒントの中身（会長の決まり・2026-10-21、#2250）。ヒントは「マスを示す」のではなく
    /// **盤を 1 歩進める**: 猫を実際に置き、間違った猫があれば × に変える。
    ///
    /// 1. すでに正しい位置に猫がある部屋（＝その行・列）は対象にしない。
    /// 2. 答えでない位置に猫がある部屋があれば、まずそれを正す（違う猫を × にし、その部屋の答えの
    ///    マスに猫を置く。答えの猫がすでにあって余分な猫だけなら × にするだけ）。
    /// 3. それ以外は、まだ猫のいない部屋のうち、いま推理で決めやすい（候補マスが最も少ない）部屋の答えに置く。
    /// 4. 置いた猫は `CatPuzzleModel.hintCells` で印付き・消せない扱いにする。
    /// 5. 盤が解けていれば nil（ヒントは押せない）。
    /// 6. 返す値は必ず盤を変える（`placed` か `removed` のどちらかが空でない）。
    public static func hint(puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark]) -> CatPuzzleHint? {
        let n = puzzle.side
        let solution = Set(puzzle.solutionCells)
        let cats = marks.indices.filter { marks[$0] == .cat }
        /// 部屋ごとの答えのマス（`isWellFormed` により部屋 1 つに 1 マス）。
        func answer(ofRoom room: Int) -> Int? { puzzle.solutionCells.first { puzzle.rooms[$0] == room } }

        // 2. 答えでない位置の猫を正す。答えの猫がまだ無い部屋を優先し、同じなら部屋の番号の若い順。
        let wrong = cats.filter { !solution.contains($0) }
        if !wrong.isEmpty {
            let rooms = Set(wrong.map { puzzle.rooms[$0] })
            let room = rooms.min { a, b in
                let aMissing = answer(ofRoom: a).map { marks[$0] != .cat } ?? false
                let bMissing = answer(ofRoom: b).map { marks[$0] != .cat } ?? false
                return aMissing != bMissing ? aMissing : a < b
            }!
            let removed = wrong.filter { puzzle.rooms[$0] == room }.sorted()
            let placed = answer(ofRoom: room).flatMap { marks[$0] == .cat ? nil : $0 }
            return CatPuzzleHint(room: room, placed: placed, removed: removed)
        }

        // 3. 置いてある猫は全部正しい。まだ猫のいない部屋のうち、候補のマスが最も少ない部屋の答えに置く。
        //    候補 = その部屋で × でなく、置いた猫と同じ行・列になく、隣り合わないマス（答えのマスは常に候補）。
        var best: (room: Int, cell: Int, candidates: Int)?
        for cell in puzzle.solutionCells where marks[cell] != .cat {
            let room = puzzle.rooms[cell]
            let candidates = puzzle.cells(inRoom: room).filter { candidate in
                marks[candidate] != .cross && !cats.contains { cat in
                    cat / n == candidate / n || cat % n == candidate % n || isAdjacent(cat, candidate, side: n)
                }
            }.count
            if best == nil || candidates < best!.candidates || (candidates == best!.candidates && room < best!.room) {
                best = (room, cell, candidates)
            }
        }
        guard let best else { return nil }
        return CatPuzzleHint(room: best.room, placed: best.cell, removed: [])
    }

    // MARK: - 解の数え上げ

    /// 部屋割り `rooms` に対する解（各部屋・行・列に 1 匹・隣り合わない置き方）の数を `limit` まで数える。
    /// 行ごとに列を選ぶ深さ優先で、使った列・部屋をビットで持つ（8×8 でも一瞬）。
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
                    guard let move = randomMove(rooms: rooms, side: n, solution: solution, using: &generator) else { break }
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
                    return CatPuzzle(side: n, rooms: rooms, solution: solution)
                }
            }
        }
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
