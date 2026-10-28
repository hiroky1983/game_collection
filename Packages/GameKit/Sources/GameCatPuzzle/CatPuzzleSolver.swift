import Foundation

/// 解き手が測った 1 問の難しさ（#3048）。
///
/// `tier` は解くのに要った最上位の段（1〜5）、`counts[t - 1]` は段 `t` を使った回数。
/// 段 5（仮置きして矛盾 = 当て推量）が要る問題はステージに採らない。
/// 推理だけで解き切れなかった（段 5 でも進めなかった）ときは `solved` が false。
public struct CatPuzzleDifficulty: Equatable, Sendable {
    public let tier: Int
    public let counts: [Int]
    public let solved: Bool

    public init(tier: Int, counts: [Int], solved: Bool) {
        self.tier = tier
        self.counts = counts
        self.solved = solved
    }

    /// 段ごとの重み。上の段ほど 1 回が重い（段 1・2 は盤の広さぶんだけ必ず使う）。
    public static let weights = [1, 1, 4, 10, 30]

    /// 難しさの点数 = 段ごとの使用回数 × 重み の合計。盤が広いほど手数が増えて点数も上がる。
    public var score: Int { zip(counts, Self.weights).reduce(0) { $0 + $1.0 * $1.1 } }
}

/// 人の推理をまねた段で解く解き手（#3048・ステージの難しさの点数付け）。
///
/// - 段 1: ある部屋・行・列で猫が入れるマスが 1 つだけ → 猫が確定
/// - 段 2: 猫の周り 8 マス（ななめを含む）と同じ行・列・部屋を × で消す
/// - 段 3: ある部屋の候補が 1 行（1 列）に収まる → その行（列）のほかの部屋から消す。
///         逆に、ある行（列）の候補が 1 部屋に収まる → その部屋のほかのマスを消す
/// - 段 4: n 部屋の候補が n 行（列）に収まる組 → その行（列）のほかのマスを消す（逆向きも）
/// - 段 5: 仮に猫を置いて段 1〜4 で進めると矛盾する → そのマスは ×（当て推量）
///
/// いつも「使える中でいちばん下の段」を 1 回使ってから段 1 に戻る。推理はどれも正しいので、
/// 解き切れたときの猫の並びは答えそのもの。
public enum CatPuzzleSolver {

    /// 難しさを測る。`maxTier` より上の段は使わない（5 なら当て推量まで）。
    public static func rate(_ puzzle: CatPuzzle, maxTier: Int = 5) -> CatPuzzleDifficulty {
        var state = State(puzzle: puzzle)
        var counts = Array(repeating: 0, count: 5)
        let outcome = state.run(maxTier: maxTier, counts: &counts)
        let used = counts.lastIndex { $0 > 0 }.map { $0 + 1 } ?? 1
        return CatPuzzleDifficulty(tier: used, counts: counts, solved: outcome == .solved)
    }

    /// 解き手が解き切ったときの猫のマス（行の順）。解き切れなければ nil。
    public static func solve(_ puzzle: CatPuzzle, maxTier: Int = 5) -> [Int]? {
        var state = State(puzzle: puzzle)
        var counts = Array(repeating: 0, count: 5)
        guard state.run(maxTier: maxTier, counts: &counts) == .solved else { return nil }
        return state.cats.sorted()
    }

    enum Outcome { case solved, stuck, contradiction }

    struct State {
        let side: Int
        let rooms: [Int]
        /// 行・列・部屋（この順で `side` 個ずつ）のマス。
        let groups: [[Int]]
        /// まだ猫がいるかもしれないマス。
        var candidate: [Bool]
        var cats: [Int] = []
        /// 周りをもう消した猫。
        var cleared: Set<Int> = []

        init(puzzle: CatPuzzle) {
            let n = puzzle.side
            side = n
            rooms = puzzle.rooms
            var groups: [[Int]] = []
            for row in 0..<n { groups.append((0..<n).map { row * n + $0 }) }
            for col in 0..<n { groups.append((0..<n).map { $0 * n + col }) }
            for room in 0..<n { groups.append(puzzle.rooms.indices.filter { puzzle.rooms[$0] == room }) }
            self.groups = groups
            candidate = Array(repeating: true, count: n * n)
        }

        func hasCat(_ group: [Int]) -> Bool { group.contains { cats.contains($0) } }

        func candidates(_ group: [Int]) -> [Int] { group.filter { candidate[$0] && !cats.contains($0) } }

        /// 行・列・部屋のどれかで猫がいないのに入れるマスが無い。
        var isContradiction: Bool {
            groups.contains { !hasCat($0) && candidates($0).isEmpty }
        }

        /// 段を順に試し、いちばん下の段で 1 歩進めることを繰り返す。
        mutating func run(maxTier: Int, counts: inout [Int]) -> Outcome {
            while true {
                if isContradiction { return .contradiction }
                if cats.count == side { return .solved }
                guard let tier = step(maxTier: maxTier) else { return .stuck }
                counts[tier - 1] += 1
            }
        }

        /// 1 歩進めて使った段を返す。進めなければ nil。
        mutating func step(maxTier: Int) -> Int? {
            if clearAroundCat() { return 2 }
            if placeOnlyCell() { return 1 }
            if maxTier >= 3, confine(size: 1) { return 3 }
            if maxTier >= 4 {
                let remaining = side - cats.count
                if remaining > 2 {
                    for size in 2..<remaining where confine(size: size) { return 4 }
                }
            }
            if maxTier >= 5, eliminateByTrial() { return 5 }
            return nil
        }

        /// 段 2: まだ周りを消していない猫 1 匹の行・列・部屋と隣のマスを消す。
        mutating func clearAroundCat() -> Bool {
            guard let cat = cats.first(where: { !cleared.contains($0) }) else { return false }
            cleared.insert(cat)
            let n = side
            for cell in 0..<(n * n) where cell != cat && candidate[cell] {
                if cell / n == cat / n || cell % n == cat % n || rooms[cell] == rooms[cat]
                    || CatPuzzleLogic.isAdjacent(cell, cat, side: n) {
                    candidate[cell] = false
                }
            }
            return true
        }

        /// 段 1: 入れるマスが 1 つだけの行・列・部屋に猫を置く。
        mutating func placeOnlyCell() -> Bool {
            for group in groups where !hasCat(group) {
                let open = candidates(group)
                if open.count == 1 {
                    cats.append(open[0])
                    return true
                }
            }
            return false
        }

        /// 段 3・4: 種類 `source`（部屋 / 行 / 列）の `size` 個の候補が、種類 `target` の `size` 個に収まる →
        /// その `target` のほかのマスを消す。部屋 → 行・列、行・列 → 部屋の 4 通り。
        mutating func confine(size: Int) -> Bool {
            let n = side
            // 0: 行、1: 列、2: 部屋（`groups` の並び）。
            for (source, target) in [(2, 0), (2, 1), (0, 2), (1, 2)] {
                let open = (0..<n).filter { !hasCat(groups[source * n + $0]) }
                guard open.count > size else { continue }
                for subset in combinations(open, size) {
                    var targets = Set<Int>()
                    var members = Set<Int>()
                    for index in subset {
                        for cell in candidates(groups[source * n + index]) {
                            members.insert(cell)
                            targets.insert(groupIndex(of: cell, kind: target))
                        }
                    }
                    guard targets.count == size else { continue }
                    var removed = false
                    for t in targets {
                        for cell in groups[target * n + t] where candidate[cell] && !cats.contains(cell) && !members.contains(cell) {
                            candidate[cell] = false
                            removed = true
                        }
                    }
                    if removed { return true }
                }
            }
            return false
        }

        func groupIndex(of cell: Int, kind: Int) -> Int {
            switch kind {
            case 0: cell / side
            case 1: cell % side
            default: rooms[cell]
            }
        }

        /// 段 5: 仮に猫を置いて段 1〜4 で進めると矛盾するマスを 1 つ消す。
        mutating func eliminateByTrial() -> Bool {
            for cell in 0..<(side * side) where candidate[cell] && !cats.contains(cell) {
                var trial = self
                trial.cats.append(cell)
                var scratch = Array(repeating: 0, count: 5)
                if trial.run(maxTier: 4, counts: &scratch) == .contradiction {
                    candidate[cell] = false
                    return true
                }
            }
            return false
        }
    }

    /// `items` から `k` 個選ぶ組み合わせ（並びは辞書順）。
    static func combinations(_ items: [Int], _ k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[Int]] = []
        var current: [Int] = []
        func walk(_ start: Int) {
            if current.count == k {
                result.append(current)
                return
            }
            for i in start..<items.count where items.count - i >= k - current.count {
                current.append(items[i])
                walk(i + 1)
                current.removeLast()
            }
        }
        walk(0)
        return result
    }
}
