import CoreEngine

/// 盤の大きさ（#2235）。5×5 と 7×7 の 2 段階。`rawValue` は記録の区分キー・中断データにそのまま使う。
public enum TsunagiSize: String, CaseIterable, Codable, Sendable {
    case small = "5x5"
    case large = "7x7"

    /// 1 辺のマス数。
    public var side: Int {
        switch self {
        case .small: 5
        case .large: 7
        }
    }

    /// 生成する数字の組の数の範囲。少ないほど 1 本が長くなり、解が 1 つに絞りにくくなる。
    var pairRange: ClosedRange<Int> {
        switch self {
        case .small: 5...7
        case .large: 9...11
        }
    }
}

/// 1 問ぶん。マスは行優先の番号（`row * side + col`）。
///
/// `endpoints[k]` が数字 `k + 1` の 2 つの点、`solution[k]` がその点どうしを結ぶ唯一の線
/// （`endpoints[k][0]` から `endpoints[k][1]` まで、両端を含む）。
public struct TsunagiPuzzle: Codable, Equatable, Sendable {
    public let side: Int
    public let endpoints: [[Int]]
    public let solution: [[Int]]

    public init(side: Int, endpoints: [[Int]], solution: [[Int]]) {
        self.side = side
        self.endpoints = endpoints
        self.solution = solution
    }

    public var cellCount: Int { side * side }
    public var pairCount: Int { endpoints.count }

    /// `cell` が点なら、その数字の番号（0 始まり）。
    public func endpointColor(at cell: Int) -> Int? {
        endpoints.firstIndex { $0.contains(cell) }
    }
}

/// 線つなぎの純粋ロジック（#2235）。生成・解の数え上げ・盤の検査。
public enum TsunagiLogic {

    // MARK: - 盤の基本

    /// 上下左右の隣のマス。
    public static func neighbors(of cell: Int, side: Int) -> [Int] {
        let row = cell / side, col = cell % side
        var result: [Int] = []
        result.reserveCapacity(4)
        if row > 0 { result.append(cell - side) }
        if row < side - 1 { result.append(cell + side) }
        if col > 0 { result.append(cell - 1) }
        if col < side - 1 { result.append(cell + 1) }
        return result
    }

    public static func isAdjacent(_ a: Int, _ b: Int, side: Int) -> Bool {
        let dr = abs(a / side - b / side), dc = abs(a % side - b % side)
        return dr + dc == 1
    }

    /// 1 問として正しい形か（中断データの健全性検査にも使う）。点が重ならず、解が全マスを
    /// ちょうど 1 回ずつ通り、各線が隣どうしでつながって両端が点になっていること。
    public static func isWellFormed(_ puzzle: TsunagiPuzzle) -> Bool {
        let side = puzzle.side
        guard side >= 2, puzzle.pairCount >= 1, puzzle.endpoints.count == puzzle.solution.count else { return false }
        var seen = Array(repeating: false, count: puzzle.cellCount)
        for (k, path) in puzzle.solution.enumerated() {
            let ends = puzzle.endpoints[k]
            guard ends.count == 2, path.count >= 2,
                  path.first == ends[0], path.last == ends[1] else { return false }
            for (i, cell) in path.enumerated() {
                guard (0..<puzzle.cellCount).contains(cell), !seen[cell] else { return false }
                seen[cell] = true
                if i > 0, !isAdjacent(path[i - 1], cell, side: side) { return false }
            }
        }
        return seen.allSatisfy { $0 }
    }

    /// 描いた線（数字ごと）が、全部つながって全マスを埋めているか。
    public static func isSolved(puzzle: TsunagiPuzzle, paths: [[Int]]) -> Bool {
        guard paths.count == puzzle.pairCount else { return false }
        var filled = Array(repeating: false, count: puzzle.cellCount)
        for (k, path) in paths.enumerated() {
            guard isComplete(path: path, endpoints: puzzle.endpoints[k], side: puzzle.side) else { return false }
            for cell in path {
                guard !filled[cell] else { return false }
                filled[cell] = true
            }
        }
        return filled.allSatisfy { $0 }
    }

    /// 1 本の線が、片方の点から始まりもう片方の点で終わる、隣どうしのつながった線か。
    public static func isComplete(path: [Int], endpoints: [Int], side: Int) -> Bool {
        guard path.count >= 2, let first = path.first, let last = path.last,
              Set([first, last]) == Set(endpoints) else { return false }
        for i in 1..<path.count where !isAdjacent(path[i - 1], path[i], side: side) { return false }
        return Set(path).count == path.count
    }

    // MARK: - 生成

    /// 解がちょうど 1 つの問題を作る。
    ///
    /// 盤全体を 1 筆で通る道（はじめは行ごとに折り返す蛇行）を「後ろ噛み（backbite）」で崩してから
    /// 長さ 3 以上の区間に切り分け、各区間の両端を点にする。切り分けた線は必ず 1 つの解になるが、
    /// 別の解があり得るので、`countSolutions` で 1 つに絞れた問題だけを採る。
    public static func generate<G: RandomNumberGenerator>(size: TsunagiSize, using generator: inout G) -> TsunagiPuzzle {
        let side = size.side
        while true {
            let route = randomHamiltonianPath(side: side, using: &generator)
            let pairs = Int.random(in: size.pairRange, using: &generator)
            guard let segments = cut(route, into: pairs, minLength: 3, using: &generator) else { continue }
            let puzzle = TsunagiPuzzle(
                side: side,
                endpoints: segments.map { [$0.first!, $0.last!] },
                solution: segments
            )
            if countSolutions(puzzle, limit: 2) == 1 { return puzzle }
        }
    }

    /// 全マスを 1 回ずつ通る道。蛇行から始めて後ろ噛みを繰り返し、形を崩す。
    static func randomHamiltonianPath<G: RandomNumberGenerator>(side: Int, using generator: inout G) -> [Int] {
        var path: [Int] = []
        for row in 0..<side {
            let cols = row.isMultiple(of: 2) ? Array(0..<side) : Array((0..<side).reversed())
            path += cols.map { row * side + $0 }
        }
        let n = path.count
        var position = Array(repeating: 0, count: n)
        for (i, cell) in path.enumerated() { position[cell] = i }
        for _ in 0..<(n * 30) {
            // どちらかの端を選び、その端の隣（道の上で隣でないマス）へつないで、輪になった部分を逆向きにする。
            if Bool.random(using: &generator) {
                path.reverse()
                for (i, cell) in path.enumerated() { position[cell] = i }
            }
            let head = path[n - 1]
            let options = neighbors(of: head, side: side).filter { position[$0] != n - 2 }
            guard let pick = options.randomElement(using: &generator) else { continue }
            let j = position[pick]
            // path[j] と head をつなぐ → path[j+1...n-1] を逆順にする。
            path[(j + 1)...].reverse()
            for i in (j + 1)..<n { position[path[i]] = i }
        }
        return path
    }

    /// 道を `count` 本の区間（各 `minLength` マス以上）に切る。切れなければ nil。
    static func cut<G: RandomNumberGenerator>(_ route: [Int], into count: Int, minLength: Int, using generator: inout G) -> [[Int]]? {
        let n = route.count
        guard count * minLength <= n else { return nil }
        // 各区間の長さ = minLength + 余りの配分。余りを count 個にランダムに振り分ける。
        var lengths = Array(repeating: minLength, count: count)
        for _ in 0..<(n - count * minLength) {
            lengths[Int.random(in: 0..<count, using: &generator)] += 1
        }
        var segments: [[Int]] = []
        var start = 0
        for length in lengths {
            segments.append(Array(route[start..<(start + length)]))
            start += length
        }
        return segments
    }

    // MARK: - 解の数え上げ

    /// 解（全マスを埋め、同じ数字どうしを交差せずにつなぐ線の組）の数を `limit` まで数える。
    public static func countSolutions(_ puzzle: TsunagiPuzzle, limit: Int) -> Int {
        var solver = Solver(puzzle: puzzle, limit: limit)
        return solver.run()
    }

    /// 端から線を 1 マスずつ伸ばす深さ優先の探索。行き止まりのマス・分断された領域を早めに切る。
    struct Solver {
        let side: Int
        let cellCount: Int
        let limit: Int
        let targets: [Int]
        let adjacency: [[Int]]
        /// マスの持ち主（-1 は空き）。
        var owner: [Int]
        var heads: [Int]
        var done: [Bool]
        var count = 0

        init(puzzle: TsunagiPuzzle, limit: Int) {
            side = puzzle.side
            cellCount = puzzle.cellCount
            self.limit = limit
            adjacency = (0..<puzzle.cellCount).map { TsunagiLogic.neighbors(of: $0, side: puzzle.side) }
            owner = Array(repeating: -1, count: puzzle.cellCount)
            for (k, ends) in puzzle.endpoints.enumerated() {
                for cell in ends { owner[cell] = k }
            }
            heads = puzzle.endpoints.map { $0[0] }
            targets = puzzle.endpoints.map { $0[1] }
            done = Array(repeating: false, count: puzzle.pairCount)
        }

        mutating func run() -> Int {
            search()
            return count
        }

        private mutating func search() {
            if count >= limit { return }
            // 伸ばせる先がいちばん少ない線から試す（1 通りしかない線を先に決める）。
            var best = -1
            var bestMoves: [Int] = []
            for k in heads.indices where !done[k] {
                var moves: [Int] = []
                for next in adjacency[heads[k]] where owner[next] == -1 || next == targets[k] {
                    moves.append(next)
                }
                if moves.isEmpty { return }
                if best == -1 || moves.count < bestMoves.count {
                    best = k
                    bestMoves = moves
                    if moves.count == 1 { break }
                }
            }
            if best == -1 {
                if !owner.contains(-1) { count += 1 }
                return
            }
            let k = best
            let previousHead = heads[k]
            for next in bestMoves {
                if next == targets[k] {
                    done[k] = true
                    heads[k] = next
                    if isFeasible() { search() }
                    done[k] = false
                    heads[k] = previousHead
                } else {
                    owner[next] = k
                    heads[k] = next
                    if isFeasible() { search() }
                    owner[next] = -1
                    heads[k] = previousHead
                }
                if count >= limit { return }
            }
        }

        /// 空きマスごとに「まだ通れる出入口」が 2 つ以上あるか、各線の先端と行き先が空きマスを通ってつながるか、
        /// 空きの領域ごとにそこを埋められる線があるか。
        private func isFeasible() -> Bool {
            // 未完成の線の先端と行き先（線の出入口）。
            var isOpenEnd = Array(repeating: -1, count: cellCount)
            for k in heads.indices where !done[k] {
                isOpenEnd[heads[k]] = k
                isOpenEnd[targets[k]] = k
            }
            for cell in 0..<cellCount where owner[cell] == -1 {
                var exits = 0
                for next in adjacency[cell] where owner[next] == -1 || isOpenEnd[next] >= 0 { exits += 1 }
                if exits < 2 { return false }
            }
            // 空きマスの連結成分に番号を振る。
            var component = Array(repeating: -1, count: cellCount)
            var componentCount = 0
            var stack: [Int] = []
            for start in 0..<cellCount where owner[start] == -1 && component[start] == -1 {
                component[start] = componentCount
                stack.append(start)
                while let cell = stack.popLast() {
                    for next in adjacency[cell] where owner[next] == -1 && component[next] == -1 {
                        component[next] = componentCount
                        stack.append(next)
                    }
                }
                componentCount += 1
            }
            var served = Array(repeating: false, count: componentCount)
            for k in heads.indices where !done[k] {
                let head = heads[k], target = targets[k]
                if adjacency[head].contains(target) {
                    // 直接つなげられる。領域を埋める役も、隣り合う共通の領域があれば担える。
                    markShared(head: head, target: target, component: component, served: &served)
                    continue
                }
                if !markShared(head: head, target: target, component: component, served: &served) { return false }
            }
            return served.allSatisfy { $0 }
        }

        /// 先端と行き先の両方が接している領域に印を付ける。共通の領域が 1 つも無ければ false。
        @discardableResult
        private func markShared(head: Int, target: Int, component: [Int], served: inout [Bool]) -> Bool {
            var found = false
            for a in adjacency[head] where owner[a] == -1 {
                let c = component[a]
                if adjacency[target].contains(where: { owner[$0] == -1 && component[$0] == c }) {
                    served[c] = true
                    found = true
                }
            }
            return found
        }
    }
}
