import Foundation

/// 数独の難易度。盤から取り除くマスの数だけが違う。
public enum SudokuDifficulty: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard

    /// 記録の区分名（ハブ・リザルトの 1 行に添える）。
    public var label: String {
        switch self {
        case .easy:   return "かんたん"
        case .normal: return "ふつう"
        case .hard:   return "むずかしい"
        }
    }

    /// 盤から取り除くマスの数の範囲。旧実装（#5・`fa4377a`）の値をそのまま踏襲する。
    ///
    /// 唯一解を保てないマスは削れずに戻すため、**実際の空きマス数は上限に届かないことがある**
    /// （特に `hard`）。難易度の大小関係は保たれる。
    public var removalRange: ClosedRange<Int> {
        switch self {
        case .easy:   return 30...35
        case .normal: return 40...45
        case .hard:   return 46...50
        }
    }
}

/// バックトラッキングで完成グリッドを作り、**唯一解を保ちながら**セルを削るパズル生成エンジン。
///
/// 旧実装（#5・`fa4377a`）のアルゴリズムをそのまま引き継いだ純粋ロジック。UI の規約に一切
/// 依存しないので、View を作り直すのに合わせて書き直す理由が無い（Issue #262 の実装方針）。
/// 乱数だけは注入できるようにして、テストで盤面を固定できるようにしてある
/// （麻雀ソリティア `MahjongSolitaireRules.generate(using:)` と同じ形）。
public enum SudokuEngine {
    /// 1 辺のマス数。
    public static let size = 9
    /// 盤全体のマス数。
    public static let cellCount = size * size

    /// 生成されたパズル。
    public struct Puzzle: Equatable, Sendable {
        /// 出題（空きマスは 0）。
        public let board: [Int]
        /// 完全な正解。
        public let solution: [Int]

        public init(board: [Int], solution: [Int]) {
            self.board = board
            self.solution = solution
        }

        /// 空きマスの数。
        public var blankCount: Int { board.filter { $0 == 0 }.count }
    }

    /// 本番用。システムの乱数で生成する。
    public static func generate(difficulty: SudokuDifficulty) -> Puzzle {
        var rng = SystemRandomNumberGenerator()
        return generate(difficulty: difficulty, using: &rng)
    }

    /// 乱数を注入して生成する（テストで盤面を固定するため）。
    public static func generate<G: RandomNumberGenerator>(
        difficulty: SudokuDifficulty,
        using rng: inout G
    ) -> Puzzle {
        var solution = [Int](repeating: 0, count: cellCount)
        _ = fill(&solution, from: 0, using: &rng)

        let removeCount = Int.random(in: difficulty.removalRange, using: &rng)
        var board = solution
        var removed = 0
        for index in (0..<cellCount).shuffled(using: &rng) {
            guard removed < removeCount else { break }
            let backup = board[index]
            board[index] = 0
            // 解が 2 通り以上に増えるマスは削らずに戻す（＝出題は必ず唯一解）。
            if solutionCount(board, limit: 2) == 1 {
                removed += 1
            } else {
                board[index] = backup
            }
        }
        return Puzzle(board: board, solution: solution)
    }

    /// 解の個数。`limit` に達した時点で数えるのをやめる（唯一解の判定は `limit: 2` で足りる）。
    public static func solutionCount(_ grid: [Int], limit: Int) -> Int {
        var work = grid
        return count(&work, limit: limit)
    }

    /// `index` のマスに `digit` を置いても、行・列・3×3 ブロックで衝突しないか。
    public static func isValid(_ grid: [Int], at index: Int, digit: Int) -> Bool {
        let row = index / size, col = index % size
        for i in 0..<size {
            if grid[row * size + i] == digit { return false }
            if grid[i * size + col] == digit { return false }
        }
        let blockRow = (row / 3) * 3, blockCol = (col / 3) * 3
        for dr in 0..<3 {
            for dc in 0..<3 {
                if grid[(blockRow + dr) * size + blockCol + dc] == digit { return false }
            }
        }
        return true
    }

    /// 同じ行・列・3×3 ブロックにあるマス（自分自身は含まない）。
    /// 選択マスのハイライトと、数字を確定したときのメモ消しで共有する。
    public static func peers(of index: Int) -> Set<Int> {
        let row = index / size, col = index % size
        let blockRow = (row / 3) * 3, blockCol = (col / 3) * 3
        var result = Set<Int>()
        for i in 0..<size {
            result.insert(row * size + i)
            result.insert(i * size + col)
        }
        for dr in 0..<3 {
            for dc in 0..<3 {
                result.insert((blockRow + dr) * size + blockCol + dc)
            }
        }
        result.remove(index)
        return result
    }

    // MARK: - Private

    /// 先頭のマスから順に、シャッフルした数字を試して埋める。
    private static func fill<G: RandomNumberGenerator>(
        _ grid: inout [Int],
        from position: Int,
        using rng: inout G
    ) -> Bool {
        if position == cellCount { return true }
        for digit in (1...size).shuffled(using: &rng) where isValid(grid, at: position, digit: digit) {
            grid[position] = digit
            if fill(&grid, from: position + 1, using: &rng) { return true }
            grid[position] = 0
        }
        return false
    }

    private static func count(_ grid: inout [Int], limit: Int) -> Int {
        guard let position = grid.firstIndex(of: 0) else { return 1 }
        var found = 0
        for digit in 1...size where isValid(grid, at: position, digit: digit) {
            grid[position] = digit
            found += count(&grid, limit: limit)
            grid[position] = 0
            if found >= limit { break }
        }
        return found
    }
}

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
struct SudokuSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
