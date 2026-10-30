import Foundation
import CoreEngine

/// 数独の難易度。盤から取り除くマスの数が違う。`expert` はそれに加えて、解くのに基本の消去法
/// （`SudokuEngine.isSolvableBySingles`）だけでは足りない盤だけを出す（#3099）。
public enum SudokuDifficulty: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard, expert

    /// 画面に出す難易度名（表示言語に従う）。記録の区分名には `recordLabel` を使う。
    public var label: String {
        switch self {
        case .easy:   return tr("かんたん")
        case .normal: return tr("ふつう")
        case .hard:   return tr("むずかしい")
        case .expert: return tr("上級")
        }
    }

    /// 記録の区分名（`GameScore.variantLabel`・ハブ・リザルトの 1 行に添える）。保存されるので表示言語によらず日本語のまま。
    public var recordLabel: String {
        RecordVariantLabels.stored(gameID: "sudoku", variant: rawValue)
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
        case .expert: return 52...56
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

        if difficulty == .expert {
            return generateExpert(solution: solution, using: &rng)
        }
        let board = carve(solution, count: Int.random(in: difficulty.removalRange, using: &rng), using: &rng)
        return Puzzle(board: board, solution: solution)
    }

    /// 上級の盤を作る。空きが範囲の下限に届き、かつ基本の消去法だけでは解けない盤が出るまで、
    /// 同じ完成グリッドから削り直す（数十回試せばほぼ必ず当たる。実測は PR 本文）。
    /// 試行の上限に達したら、その中で最も条件に近い盤（手筋の条件 → 空きの多さの順）を返す。
    private static func generateExpert<G: RandomNumberGenerator>(
        solution: [Int],
        using rng: inout G
    ) -> Puzzle {
        let range = SudokuDifficulty.expert.removalRange
        var best: (board: [Int], score: Int)?
        for _ in 0..<expertAttemptLimit {
            let board = carve(solution, count: Int.random(in: range, using: &rng), using: &rng)
            let blanks = board.filter { $0 == 0 }.count
            let needsMore = !isSolvableBySingles(board)
            if needsMore && blanks >= range.lowerBound { return Puzzle(board: board, solution: solution) }
            // 手筋の条件を空きの多さより優先して比べる（空きは 81 未満なので 100 を掛けて足せばよい）。
            let score = (needsMore ? 100 : 0) + blanks
            if let current = best, current.score >= score { continue }
            best = (board, score)
        }
        return Puzzle(board: best?.board ?? solution, solution: solution)
    }

    /// 上級の削り直しの上限。
    private static let expertAttemptLimit = 40

    /// 完成グリッドからマスを `count` 個を目安に削る。**唯一解を保てないマスは戻す**ので、届かないことがある。
    private static func carve<G: RandomNumberGenerator>(
        _ solution: [Int],
        count removeCount: Int,
        using rng: inout G
    ) -> [Int] {
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
        return board
    }

    /// 基本の消去法だけで最後まで解けるか。
    ///
    /// 使う手筋は 2 つだけ（上級の「手筋の下限」の判定に使う・#3099）:
    /// - 単独候補: そのマスに入る数字が、行・列・ブロックの消去の結果 1 つしか残らない
    /// - 隠れた単独: 行・列・ブロックのどこかで、その数字を置けるマスが 1 つしか残らない
    /// これで詰まる盤（ペア・ポインティング・仮置きなどが要る盤）は `false`。
    /// 唯一解の盤を渡す前提で、矛盾（候補が尽きたマス）に当たったときも `false` を返す。
    public static func isSolvableBySingles(_ grid: [Int]) -> Bool {
        var values = grid
        var candidates = [Int](repeating: 0, count: cellCount)   // 下位 9 ビットが数字 1〜9
        let all = (1 << size) - 1
        for index in 0..<cellCount where values[index] == 0 {
            var mask = all
            for peer in peers(of: index) where values[peer] != 0 { mask &= ~(1 << (values[peer] - 1)) }
            candidates[index] = mask
        }
        func place(_ digit: Int, at index: Int) {
            values[index] = digit
            candidates[index] = 0
            for peer in peers(of: index) { candidates[peer] &= ~(1 << (digit - 1)) }
        }
        var progressed = true
        while progressed {
            progressed = false
            for index in 0..<cellCount where values[index] == 0 {
                let mask = candidates[index]
                if mask == 0 { return false }
                if mask & (mask - 1) == 0 {
                    place(mask.trailingZeroBitCount + 1, at: index)
                    progressed = true
                }
            }
            for unit in 0..<unitCount {
                let cells = self.cells(ofUnit: unit)
                for digit in 1...size {
                    let bit = 1 << (digit - 1)
                    if cells.contains(where: { values[$0] == digit }) { continue }
                    let spots = cells.filter { candidates[$0] & bit != 0 }
                    if spots.count == 1 {
                        place(digit, at: spots[0])
                        progressed = true
                    }
                }
            }
        }
        return !values.contains(0)
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

    /// 行・列・3×3 ブロックを 1 本の通し番号で表した「ユニット」の数（行 0〜8・列 9〜17・ブロック 18〜26）。
    /// 揃った行・列・ブロックを光らせる判定（#666）で使う。
    public static let unitCount = size * 3

    /// `index` のマスが属する 3 つのユニット（行・列・ブロックの順）。
    public static func units(of index: Int) -> [Int] {
        let row = index / size, col = index % size
        return [row, size + col, size * 2 + (row / 3) * 3 + col / 3]
    }

    /// ユニットに含まれる 9 マス。
    public static func cells(ofUnit unit: Int) -> [Int] {
        switch unit {
        case 0..<size:
            return (0..<size).map { unit * size + $0 }
        case size..<(size * 2):
            return (0..<size).map { $0 * size + (unit - size) }
        default:
            let block = unit - size * 2
            let blockRow = (block / 3) * 3, blockCol = (block % 3) * 3
            return (0..<size).map { (blockRow + $0 / 3) * size + blockCol + $0 % 3 }
        }
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

    /// 行・列・ブロックごとに「入っている数字」をビットで持ち、**候補がいちばん少ない空きマス**から
    /// 試す探索（#3099）。上級は空きが 52 以上で、先頭の空きマスから順に試す素朴な探索では
    /// 唯一解の判定が重すぎるため。数える結果は素朴な探索と同じ。
    private static func count(_ grid: inout [Int], limit: Int) -> Int {
        var rows = [Int](repeating: 0, count: size)
        var cols = [Int](repeating: 0, count: size)
        var boxes = [Int](repeating: 0, count: size)
        for index in 0..<cellCount where grid[index] != 0 {
            let bit = 1 << (grid[index] - 1)
            rows[index / size] |= bit
            cols[index % size] |= bit
            boxes[(index / size / 3) * 3 + index % size / 3] |= bit
        }
        return search(&grid, &rows, &cols, &boxes, limit: limit)
    }

    private static func search(
        _ grid: inout [Int], _ rows: inout [Int], _ cols: inout [Int], _ boxes: inout [Int], limit: Int
    ) -> Int {
        let all = (1 << size) - 1
        var best = -1, bestMask = 0, bestCount = size + 1
        for index in 0..<cellCount where grid[index] == 0 {
            let row = index / size, col = index % size, box = (row / 3) * 3 + col / 3
            let mask = all & ~(rows[row] | cols[col] | boxes[box])
            let n = mask.nonzeroBitCount
            if n < bestCount {
                best = index; bestMask = mask; bestCount = n
                if n <= 1 { break }
            }
        }
        guard best >= 0 else { return 1 }
        let row = best / size, col = best % size, box = (row / 3) * 3 + col / 3
        var found = 0
        var remaining = bestMask
        while remaining != 0 {
            let bit = remaining & -remaining
            remaining &= remaining - 1
            grid[best] = bit.trailingZeroBitCount + 1
            rows[row] |= bit; cols[col] |= bit; boxes[box] |= bit
            found += search(&grid, &rows, &cols, &boxes, limit: limit)
            rows[row] &= ~bit; cols[col] &= ~bit; boxes[box] &= ~bit
            grid[best] = 0
            if found >= limit { break }
        }
        return found
    }
}

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
/// 実体は CoreEngine の `SplitMix64`（#916 で 5 ゲームぶんのコピーを 1 本に寄せた）。
typealias SudokuSeededGenerator = SplitMix64
