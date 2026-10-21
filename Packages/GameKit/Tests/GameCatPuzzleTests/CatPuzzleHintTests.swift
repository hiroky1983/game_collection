import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ヒントの決まり（会長 2026-10-21・#2250）と「ヒントのマス＝今の盤のただ 1 つの解」の検証。
/// 会長 QA「ヒントが玄関の答えでないマスを指した」を受け、解の数え上げとは別の素朴な全探索で答えを確かめ、
/// 生成直後・中断から再開後・難易度切り替え後・新規ゲーム後のそれぞれで多数の種を回す。
@Suite("おじさんの飼い猫パズルのヒント")
struct CatPuzzleHintTests {

    // MARK: - 部品

    /// 素朴な全探索（`CatPuzzleLogic.countSolutions` とは独立に書く）。
    /// マスを 0 から順に「猫を置く / 置かない」で分け、置くたびに行・列・部屋・隣を確かめる。
    static func allSolutions(_ puzzle: CatPuzzle) -> [[Int]] {
        let n = puzzle.side
        var found: [[Int]] = []
        var cats: [Int] = []
        func place(from cell: Int, rows: Set<Int>, cols: Set<Int>, rooms: Set<Int>) {
            if cats.count == n { found.append(cats); return }
            if cell >= n * n { return }
            let row = cell / n, col = cell % n, room = puzzle.rooms[cell]
            // 残りの行数より猫が足りなければ打ち切る。
            if n - row < n - cats.count { return }
            if !rows.contains(row), !cols.contains(col), !rooms.contains(room),
               !cats.contains(where: { CatPuzzleLogic.isAdjacent($0, cell, side: n) }) {
                cats.append(cell)
                place(from: cell + 1, rows: rows.union([row]), cols: cols.union([col]), rooms: rooms.union([room]))
                cats.removeLast()
            }
            place(from: cell + 1, rows: rows, cols: cols, rooms: rooms)
        }
        place(from: 0, rows: [], cols: [], rooms: [])
        return found
    }

    /// 盤の「答えからの距離」: まだ置けていない答えの猫 ＋ 答えでない位置の猫。
    static func distance(_ puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark]) -> Int {
        let solution = Set(puzzle.solutionCells)
        let cats = marks.indices.filter { marks[$0] == .cat }
        return solution.subtracting(cats).count + cats.filter { !solution.contains($0) }.count
    }

    /// ヒントが「盤のただ 1 つの解の猫の位置」を置き、置いても正しい猫と矛盾しないこと。
    static func checkHintMatchesSolution(_ puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark], note: String) {
        let solutions = allSolutions(puzzle)
        #expect(solutions == [puzzle.solutionCells], "\(note): 解がただ 1 つで、持っている答えと一致する")
        guard let hint = CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) else {
            #expect(CatPuzzleLogic.isSolved(puzzle: puzzle, cats: marks.indices.filter { marks[$0] == .cat }), "\(note): 解けていないのにヒントが無い")
            return
        }
        #expect(hint.placed != nil || !hint.removed.isEmpty, "\(note): 何も変えないヒント")
        if let placed = hint.placed {
            #expect(puzzle.solutionCells.contains(placed), "\(note): 置くマスが答えでない")
            #expect(puzzle.rooms[placed] == hint.room, "\(note): 置くマスが対象の部屋にない")
            #expect(marks[placed] != .cat, "\(note): すでに猫のあるマスに置こうとした")
            let correctCats = marks.indices.filter { marks[$0] == .cat && puzzle.solutionCells.contains($0) }
            #expect(CatPuzzleLogic.violations(puzzle: puzzle, cats: correctCats + [placed]).isEmpty, "\(note): 置いた猫が正しい猫と矛盾する")
        }
        for cell in hint.removed {
            #expect(marks[cell] == .cat && !puzzle.solutionCells.contains(cell), "\(note): × にするのは答えでない位置の猫だけ")
            #expect(puzzle.rooms[cell] == hint.room, "\(note): × にする猫が対象の部屋にない")
        }
    }

    // MARK: - 生成直後

    @Test("生成直後: 全探索の解はただ 1 つで答えと一致し、最初のヒントはその猫を置く（6×6）", arguments: 0..<40)
    func freshEasy(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .easy, using: &generator)
        Self.checkHintMatchesSolution(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "easy \(seed)")
    }

    @Test("生成直後: 全探索の解はただ 1 つで答えと一致し、最初のヒントはその猫を置く（7×7）", arguments: 0..<30)
    func freshNormal(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        Self.checkHintMatchesSolution(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "normal \(seed)")
    }

    @Test("生成直後: 全探索の解はただ 1 つで答えと一致し、最初のヒントはその猫を置く（8×8）", arguments: 0..<12)
    func freshHard(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .hard, using: &generator)
        Self.checkHintMatchesSolution(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "hard \(seed)")
    }

    // MARK: - ランダムな途中局面

    @Test("ランダムな途中局面: ヒントは毎回必ず盤を答えへ 1 歩以上進め、正しい猫・ヒントの猫には触れず、最後は解ける", arguments: 0..<60)
    func randomStatesAlwaysProgress(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed) &+ 1000)
        let size = CatPuzzleSize.allCases[seed % CatPuzzleSize.allCases.count]
        let puzzle = CatPuzzleLogic.generate(size: size, using: &generator)
        let solution = Set(puzzle.solutionCells)
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: puzzle.cellCount)
        // 部屋ごとに: 正しい位置に猫 / 違う位置に猫 / 何も無し。空きマスの一部を × に（答えのマスにも × を置きうる）。
        for room in 0..<puzzle.side {
            let cells = puzzle.cells(inRoom: room)
            switch Int.random(in: 0..<4, using: &generator) {
            case 0: marks[cells.first { solution.contains($0) }!] = .cat
            case 1:
                if let wrong = cells.filter({ !solution.contains($0) }).randomElement(using: &generator) { marks[wrong] = .cat }
            default: break
            }
            if Int.random(in: 0..<3, using: &generator) == 0,
               let extra = cells.filter({ !solution.contains($0) && marks[$0] == .empty }).randomElement(using: &generator) {
                marks[extra] = .cat
            }
        }
        for cell in marks.indices where marks[cell] == .empty && Int.random(in: 0..<4, using: &generator) == 0 {
            marks[cell] = .cross
        }

        var hintCells = Set<Int>()
        var steps = 0
        while !CatPuzzleLogic.isSolved(puzzle: puzzle, cats: marks.indices.filter { marks[$0] == .cat }) {
            steps += 1
            #expect(steps <= puzzle.side * 3, "seed \(seed): ヒントを繰り返しても解けない")
            if steps > puzzle.side * 3 { return }
            let before = Self.distance(puzzle, marks: marks)
            Self.checkHintMatchesSolution(puzzle, marks: marks, note: "seed \(seed) step \(steps)")
            guard let hint = CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) else { return }
            let correctBefore = Set(marks.indices.filter { marks[$0] == .cat && solution.contains($0) })
            for cell in hint.removed {
                #expect(!hintCells.contains(cell), "seed \(seed): ヒントで置いた猫を × にした")
                marks[cell] = .cross
            }
            if let placed = hint.placed {
                marks[placed] = .cat
                hintCells.insert(placed)
            }
            let correctAfter = Set(marks.indices.filter { marks[$0] == .cat && solution.contains($0) })
            #expect(correctBefore.isSubset(of: correctAfter), "seed \(seed): 正しい猫が消えた")
            #expect(Self.distance(puzzle, marks: marks) < before, "seed \(seed): ヒントで盤が進んでいない")
        }
        #expect(CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) == nil, "seed \(seed): 解けた盤にヒントを出した")
    }

    @Test("決まり 2: 違う位置の猫がある部屋を先に正す。答えの猫がすでにある部屋の余分な猫は × にするだけ")
    func wrongCatsFirst() {
        // 4×4 の見本（答えは 1・7・8・14）。
        let puzzle = CatPuzzle(side: 4, rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3], solution: [1, 3, 0, 2])
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        marks[1] = .cat   // 部屋 0 の正しい猫
        marks[4] = .cat   // 部屋 0 の余分な猫
        marks[10] = .cat  // 部屋 3 の違う猫（答えは 14）
        // 答えの猫が無い部屋 3 を優先し、× にして置く。
        #expect(CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) == CatPuzzleHint(room: 3, placed: 14, removed: [10]))
        marks[10] = .cross
        marks[14] = .cat
        // 残るのは部屋 0 の余分な猫 → × にするだけ（置く猫は無い）。
        #expect(CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) == CatPuzzleHint(room: 0, placed: nil, removed: [4]))
        marks[4] = .cross
        // 違う猫が無くなれば、候補の少ない部屋の答えを置く。
        let next = CatPuzzleLogic.hint(puzzle: puzzle, marks: marks)
        #expect(next?.removed.isEmpty == true)
        #expect(next.flatMap(\.placed).map { [7, 8].contains($0) } == true)
    }

    // MARK: - 中断から再開・難易度切り替え・新規ゲーム（Model 経由）

    @Test("中断から再開・難易度切り替え・新規ゲームのあとも、ヒントは今の盤のただ 1 つの解の猫を置く", arguments: 0..<10)
    @MainActor
    func hintAfterFlows(seed: Int) {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let first = CatPuzzleModel(services: services, size: .normal, seed: UInt64(seed) &+ 50)
        // 途中まで遊ぶ（正しい猫 1 匹・違う猫 1 匹・×）。
        let answers = first.puzzle.solutionCells
        first.tap(cell: answers[0]); first.tap(cell: answers[0])
        let wrong = first.puzzle.cells(inRoom: first.puzzle.rooms[answers[1]]).first { $0 != answers[1] }!
        first.tap(cell: wrong); first.tap(cell: wrong)
        first.tap(cell: answers[2] == 0 ? 1 : 0)
        first.useHint()
        Self.checkHintMatchesSolution(first.puzzle, marks: first.marks, note: "seed \(seed) 生成直後")
        #expect(store.exists(for: CatPuzzleModel.gameID))

        // 中断から再開（別の種・別の大きさを渡しても保存した盤が優先される）。
        let resumed = CatPuzzleModel(services: services, size: .easy, seed: 999)
        #expect(resumed.puzzle == first.puzzle && resumed.marks == first.marks && resumed.hintCells == first.hintCells)
        Self.checkHintMatchesSolution(resumed.puzzle, marks: resumed.marks, note: "seed \(seed) 再開後")
        resumed.useHint()
        Self.checkHintMatchesSolution(resumed.puzzle, marks: resumed.marks, note: "seed \(seed) 再開後にヒント")

        // 難易度切り替え → 新しい盤の解で判定される。
        resumed.newGame(size: .hard)
        #expect(resumed.puzzle.side == 8 && resumed.hintCells.isEmpty)
        resumed.useHint()
        #expect(resumed.hintCells.count == 1 && resumed.puzzle.solutionCells.contains(resumed.hintCells.first!))
        Self.checkHintMatchesSolution(resumed.puzzle, marks: resumed.marks, note: "seed \(seed) 難易度切り替え後")

        // 新規ゲーム（同じ大きさ）。
        resumed.newGame()
        #expect(resumed.hintCells.isEmpty && resumed.hintsUsed == 0)
        resumed.useHint()
        Self.checkHintMatchesSolution(resumed.puzzle, marks: resumed.marks, note: "seed \(seed) 新規ゲーム後")
    }

    @Test("日替わりの種からの盤でも、ヒントは答えの猫を置く")
    func dailySeedPuzzle() {
        let seed = CatPuzzleLogic.dailySeed(for: Date(timeIntervalSince1970: 1_792_000_000))
        var generator = SplitMix64(seed: seed)
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        Self.checkHintMatchesSolution(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "daily")
    }
}
