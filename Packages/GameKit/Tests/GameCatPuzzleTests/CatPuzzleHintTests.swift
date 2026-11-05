import Testing
import GameKitTestSupport
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ヒント＝推理の 1 歩（会長 QA 2026-10-21・build 41、#2250）の検証。
/// どのヒントも「置いた × が答えのマスでない・置いた猫が答えのマス・必ず盤が 1 歩進む」ことを、
/// 生成直後の盤・ランダムな途中局面（違う猫・答えのマスの ×・余分な猫を含む）・中断から再開後・
/// 難易度切り替え後・新規ゲーム後のそれぞれで多数の種を回して確かめる。答えは解の数え上げとは別の全探索で確かめる。
@Suite("おじさんちのねこさがしのヒント")
struct CatPuzzleHintTests {

    /// 4×4 の見本（答えは行の順に列 1・3・0・2 → マス 1・7・8・14）。
    /// 部屋 0: 0,1,4,5 / 部屋 1: 2,3,6,7,11 / 部屋 2: 8,9,12,13 / 部屋 3: 10,14,15。
    static let sample = CatPuzzle(side: 4, rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3], solution: [1, 3, 0, 2])

    // MARK: - 部品

    /// 素朴な全探索（`CatPuzzleLogic.countSolutions` とは独立に書く）。
    static func allSolutions(_ puzzle: CatPuzzle) -> [[Int]] {
        let n = puzzle.side
        var found: [[Int]] = []
        var cats: [Int] = []
        func place(from cell: Int, rows: Set<Int>, cols: Set<Int>, rooms: Set<Int>) {
            if cats.count == n { found.append(cats); return }
            if cell >= n * n { return }
            let row = cell / n, col = cell % n, room = puzzle.rooms[cell]
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

    /// ヒントを盤に反映する（`CatPuzzleModel.useHint` と同じ手順）。
    static func apply(_ hint: CatPuzzleHint, to marks: inout [CatPuzzleModel.Mark]) {
        for cell in hint.removed + hint.crossed { marks[cell] = .cross }
        if let placed = hint.placed { marks[placed] = .cat }
    }

    /// ヒント 1 つの健全性: 答えと矛盾せず、必ず盤を変える。
    static func check(_ hint: CatPuzzleHint, puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark], hintMarks: Set<Int>, note: String) {
        let solution = Set(puzzle.solutionCells)
        #expect(hint.changesBoard, "\(note): 何も変えないヒント")
        if let placed = hint.placed {
            #expect(solution.contains(placed), "\(note): 置くマスが答えでない")
            #expect(marks[placed] != .cat, "\(note): すでに猫のあるマスに置こうとした")
        }
        for cell in hint.crossed {
            #expect(!solution.contains(cell), "\(note): 答えのマスに × を置いた")
            #expect(marks[cell] == .empty, "\(note): 空きでないマスに × を置いた（無駄なヒント）")
        }
        for cell in hint.removed {
            #expect(marks[cell] == .cat && !solution.contains(cell), "\(note): × にするのは答えでない位置の猫だけ")
            #expect(!hintMarks.contains(cell), "\(note): ヒントで置いた猫を外した")
        }
        if case .forced = hint.reason {
            #expect(hint.placed != nil && solution.contains(hint.placed!), "\(note): 最後の手段は答えの猫を置く")
        }
    }

    /// ヒントだけで解き切る。各歩を検査し、歩数と「最後の手段」の回数を返す。
    @discardableResult
    static func solveByHints(_ puzzle: CatPuzzle, marks start: [CatPuzzleModel.Mark], note: String) -> (steps: Int, forced: Int, reasons: [String]) {
        var marks = start
        var hintMarks = Set<Int>()
        var steps = 0, forced = 0
        var reasons: [String] = []
        let limit = puzzle.cellCount + puzzle.side * 2
        while !CatPuzzleLogic.isSolved(puzzle: puzzle, cats: marks.indices.filter { marks[$0] == .cat }) {
            steps += 1
            guard steps <= limit else { Issue.record("\(note): ヒントを繰り返しても解けない"); break }
            guard let hint = CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) else {
                Issue.record("\(note): 解けていないのにヒントが無い"); break
            }
            check(hint, puzzle: puzzle, marks: marks, hintMarks: hintMarks, note: "\(note) step \(steps)")
            let correctBefore = Set(marks.indices.filter { marks[$0] == .cat && puzzle.solutionCells.contains($0) })
            apply(hint, to: &marks)
            hintMarks.formUnion(hint.crossed)
            hintMarks.formUnion(hint.removed)
            if let placed = hint.placed { hintMarks.insert(placed) }
            let correctAfter = Set(marks.indices.filter { marks[$0] == .cat && puzzle.solutionCells.contains($0) })
            #expect(correctBefore.isSubset(of: correctAfter), "\(note): 正しい猫が消えた")
            if case .forced = hint.reason { forced += 1 }
            reasons.append(Self.name(of: hint.reason))
        }
        #expect(CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) == nil, "\(note): 解けた盤にヒントを出した")
        return (steps, forced, reasons)
    }

    static func name(of reason: CatPuzzleHint.Reason) -> String {
        switch reason {
        case .wrongCat: "wrongCat"
        case .confined: "confined"
        case .aroundCat: "aroundCat"
        case .onlyCell: "onlyCell"
        case .wouldBlock: "wouldBlock"
        case .wouldBlockChain: "wouldBlockChain"
        case .forced: "forced"
        }
    }

    // MARK: - 見本での決まりの確認

    @Test("手つかずの盤: 答えを置かず、推理の 1 歩（部屋 2 と 3 の猫は 3・4 行目にしかいない → 4 行目側の部屋 1 のマスは ×）")
    func freshSampleIsOneStep() {
        let marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        let hint = CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
        #expect(hint == CatPuzzleHint(
            reason: .confined(sources: [.room(2), .room(3)], targets: [.row(2), .row(3)]),
            crossed: [11], highlights: [.room(2), .room(3), .row(2), .row(3)]
        ))
        #expect(hint?.placed == nil, "ヒントは答えの猫を置かない")
    }

    @Test("(a) 答えでない位置の猫を先に外す。決まり違反なら違反の種類、違反が無ければ「答えと合わない」")
    func wrongCatFirst() {
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        marks[12] = .cat  // 部屋 2 の違う猫（答えは 8）。違反は無い。
        #expect(CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
                == CatPuzzleHint(reason: .wrongCat(cell: 12, violation: nil), removed: [12]))
        marks[12] = .empty
        marks[1] = .cat   // 正しい猫
        marks[3] = .cat   // 同じ行の違う猫
        #expect(CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
                == CatPuzzleHint(reason: .wrongCat(cell: 3, violation: .row), removed: [3], highlights: [.row(0)]))
        marks[3] = .empty
        marks[5] = .cat   // 同じ部屋でななめ隣の違う猫 → 部屋の違反を先に言う
        #expect(CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
                == CatPuzzleHint(reason: .wrongCat(cell: 5, violation: .room), removed: [5], highlights: [.room(0)]))
    }

    @Test("(b) 部屋が 1 行に収まる → その行のほかのマスは ×。(c) 行が 1 部屋に収まる → その部屋のほかのマスは ×")
    func confinedToLine() {
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        // 部屋 2（8,9,12,13）の 12・13 に × → 部屋 2 は 3 行目だけ → 3 行目の 10・11 は ×。
        marks[12] = .cross; marks[13] = .cross
        #expect(CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
                == CatPuzzleHint(reason: .confined(sources: [.room(2)], targets: [.row(2)]), crossed: [10, 11],
                                 highlights: [.room(2), .row(2)]))
        // 4 行目（12,13,14,15）の 12・13 が × → 4 行目の猫は部屋 3 の中だけ → 部屋 3 の 10 は ×（部屋→行の推理が先に 10・11 を消すので、10・11 を × にしてから）。
        marks[10] = .cross; marks[11] = .cross
        let hint = CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
        #expect(hint?.changesBoard == true && hint?.placed == nil)
    }

    @Test("(e) 入れるマスが 1 つだけになった部屋には猫を置く（確定したときだけ猫）")
    func onlyCellPlacesCat() {
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        for cell in [0, 4, 9, 10, 11, 12, 13] { marks[cell] = .cross }
        #expect(CatPuzzleLogic.hint(puzzle: Self.sample, marks: marks)
                == CatPuzzleHint(reason: .onlyCell(group: .room(2), cell: 8), placed: 8, highlights: [.room(2)]))
    }

    @Test("答えのマスに置いた × は信じない: その × があっても答えと矛盾する推理はしない")
    func crossOnAnswerIsIgnored() {
        var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: 16)
        marks[8] = .cross  // 部屋 2 の答えに ×
        for cell in [9, 12, 13] { marks[cell] = .cross }  // 部屋 2 の残りにも × → 信じると部屋 2 に猫が入れない
        let result = Self.solveByHints(Self.sample, marks: marks, note: "cross on answer")
        #expect(result.steps > 0)
    }

    @Test("見本はヒントだけで解け、最後の手段は使わない")
    func sampleSolvesByDeduction() {
        let result = Self.solveByHints(Self.sample, marks: Array(repeating: .empty, count: 16), note: "sample")
        #expect(result.forced == 0, "推理だけで解けるはず: \(result.reasons)")
    }

    // MARK: - 生成した盤

    @Test("生成直後: 解はただ 1 つで、ヒントだけで解け、答えと矛盾しない（6×6）", arguments: NightlyScale.range(ci: 0..<4, nightly: 0..<30))
    func freshEasy(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .easy, using: &generator)
        #expect(Self.allSolutions(puzzle) == [puzzle.solutionCells], "easy \(seed): 解がただ 1 つで答えと一致する")
        Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "easy \(seed)")
    }

    @Test("生成直後: 解はただ 1 つで、ヒントだけで解け、答えと矛盾しない（7×7）", arguments: NightlyScale.range(ci: 0..<3, nightly: 0..<24))
    func freshNormal(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        #expect(Self.allSolutions(puzzle) == [puzzle.solutionCells], "normal \(seed): 解がただ 1 つで答えと一致する")
        Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "normal \(seed)")
    }

    @Test("生成直後: 解はただ 1 つで、ヒントだけで解け、答えと矛盾しない（8×8）", arguments: NightlyScale.range(ci: 0..<2, nightly: 0..<10))
    func freshHard(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .hard, using: &generator)
        #expect(Self.allSolutions(puzzle) == [puzzle.solutionCells], "hard \(seed): 解がただ 1 つで答えと一致する")
        Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "hard \(seed)")
    }

    @Test("生成直後: 解はただ 1 つで、ヒントだけで解け、答えと矛盾しない（9×9）", arguments: NightlyScale.range(ci: 0..<1, nightly: 0..<6))
    func freshExpert(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .expert, using: &generator)
        #expect(Self.allSolutions(puzzle) == [puzzle.solutionCells], "expert \(seed): 解がただ 1 つで答えと一致する")
        Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "expert \(seed)")
    }

    @Test("生成した盤は推理だけで解け、最後の手段（答えを置く）は出ない")
    func deductionCoversGeneratedPuzzles() {
        var forcedTotal = 0, puzzles = 0
        var seen = Set<String>()
        // 問題作りと推理は Debug で 1 問 1 秒前後。CI は各サイズ数問、夜間は 42 問（#2952）
        for (size, seeds) in NightlyScale.value(
            ci: [(CatPuzzleSize.easy, 0..<4), (.normal, 0..<3), (.hard, 0..<2), (.expert, 0..<1)],
            nightly: [(CatPuzzleSize.easy, 0..<20), (.normal, 0..<16), (.hard, 0..<6), (.expert, 0..<4)]
        ) {
            for seed in seeds {
                var generator = SplitMix64(seed: UInt64(seed) &+ 7000)
                let puzzle = CatPuzzleLogic.generate(size: size, using: &generator)
                let result = Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "\(size) \(seed)")
                forcedTotal += result.forced
                puzzles += 1
                seen.formUnion(result.reasons)
            }
        }
        // 種は固定なので結果は決まっている。(a)〜(h) の推理で 42 問とも解け、最後の手段は 0 回（2026-10-21 時点）。
        // ここが崩れたら、生成器か推理の変更で「ヒント＝答え」に戻っている。
        #expect(forcedTotal == 0, "最後の手段が出た: \(forcedTotal)/\(puzzles)")
        #expect(seen.isSuperset(of: ["confined", "aroundCat", "onlyCell", "wouldBlock"]), "主な推理が一度も出ない: \(seen)")
    }

    // MARK: - ランダムな途中局面

    @Test("ランダムな途中局面（違う猫・答えのマスの ×・余分な猫を含む）: ヒントは毎回必ず進み、答えと矛盾せず、最後は解ける", arguments: NightlyScale.range(ci: 0..<9, nightly: 0..<60))
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
        Self.solveByHints(puzzle, marks: marks, note: "seed \(seed)")
    }

    // MARK: - 中断から再開・難易度切り替え・新規ゲーム（Model 経由）

    @Test("中断から再開・難易度切り替え・新規ゲームのあとも、ヒントは今の盤の答えと矛盾せず、ヒントの印は残る", arguments: NightlyScale.range(ci: 0..<2, nightly: 0..<8))
    @MainActor
    func hintAfterFlows(seed: Int) {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let first = CatPuzzleModel(services: services, size: .normal, seed: UInt64(seed) &+ 50)
        // 途中まで遊ぶ（正しい猫 1 匹・答えでないマスへの猫 1 回 = 赤い ×・×）。
        let answers = first.puzzle.solutionCells
        first.findCat(cell: answers[0])
        let wrong = first.puzzle.cells(inRoom: first.puzzle.rooms[answers[1]]).first { $0 != answers[1] }!
        first.findCat(cell: wrong)
        #expect(first.wrongCrosses == [wrong] && first.marks[wrong] == .cross, "答えでないマスには猫が残らず、赤い × になる")
        first.toggleCross(cell: first.marks.indices.first { first.marks[$0] == .empty && !answers.contains($0) }!)
        let hint = first.nextHint!
        Self.check(hint, puzzle: first.puzzle, marks: first.marks, hintMarks: [], note: "seed \(seed) 生成直後")
        #expect(hint.removed.isEmpty && !hint.crossed.contains(wrong), "赤い × は推理の前提（もう × なので触らない）")
        first.useHint()
        #expect(first.marks[wrong] == .cross && first.wrongCrosses == [wrong])
        #expect(store.exists(for: CatPuzzleModel.gameID))

        // 中断から再開（別の種・別の大きさを渡しても保存した盤が優先される）。
        let resumed = CatPuzzleModel(services: services, size: .easy, seed: 999)
        #expect(resumed.puzzle == first.puzzle && resumed.marks == first.marks)
        #expect(resumed.hintCells == first.hintCells && resumed.hintCrosses == first.hintCrosses)
        #expect(resumed.wrongCrosses == first.wrongCrosses && resumed.mistakes == first.mistakes)
        if let next = resumed.nextHint {
            Self.check(next, puzzle: resumed.puzzle, marks: resumed.marks, hintMarks: resumed.hintCrosses.union(resumed.hintCells), note: "seed \(seed) 再開後")
        }
        resumed.useHint()
        // ヒントの × はタップで変わらない。
        if let fixed = resumed.hintCrosses.first {
            resumed.tap(cell: fixed)
            resumed.tap(cell: fixed)
            #expect(resumed.marks[fixed] == .cross)
        }

        // 難易度切り替え → 新しい盤で判定され、ヒントの印は消える。
        resumed.newGame(size: .hard)
        #expect(resumed.puzzle.side == 8 && resumed.hintCells.isEmpty && resumed.hintCrosses.isEmpty && resumed.wrongCrosses.isEmpty)
        let hardHint = resumed.nextHint!
        Self.check(hardHint, puzzle: resumed.puzzle, marks: resumed.marks, hintMarks: [], note: "seed \(seed) 難易度切り替え後")
        resumed.useHint()
        #expect(resumed.hintsUsed == 1)

        // 新規ゲーム（同じ大きさ）。
        resumed.newGame()
        #expect(resumed.hintCells.isEmpty && resumed.hintCrosses.isEmpty && resumed.hintsUsed == 0)
        Self.check(resumed.nextHint!, puzzle: resumed.puzzle, marks: resumed.marks, hintMarks: [], note: "seed \(seed) 新規ゲーム後")
    }

    @Test("日替わりの種からの盤でも、ヒントだけで解ける")
    func dailySeedPuzzle() {
        let seed = CatPuzzleLogic.dailySeed(for: Date(timeIntervalSince1970: 1_792_000_000))
        var generator = SplitMix64(seed: seed)
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        Self.solveByHints(puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount), note: "daily")
    }

    @Test("理由の文: 行・列・部屋の呼び方と「〜なので、〜」の形")
    func messages() {
        let roomName: (Int) -> String = { ["居間", "押し入れ", "寝室", "書斎"][$0] }
        func text(_ hint: CatPuzzleHint) -> String { CatPuzzleAccessibility.message(for: hint, puzzle: Self.sample, roomName: roomName) }
        #expect(text(CatPuzzleHint(reason: .confined(sources: [.room(2)], targets: [.column(1)]), crossed: [5]))
                == "ヒント: 寝室の猫は2列目にしかいないので、2列目のほかのマスに猫はいない")
        #expect(text(CatPuzzleHint(reason: .confined(sources: [.row(2), .row(3)], targets: [.room(2), .room(3)]), crossed: [11]))
                == "ヒント: 3行目と4行目の猫は寝室と書斎にしかいないので、寝室と書斎のほかのマスに猫はいない")
        #expect(text(CatPuzzleHint(reason: .wrongCat(cell: 3, violation: .row), removed: [3]))
                == "ヒント: 同じ行に2匹はいないので、押し入れの猫を外すよ")
        #expect(text(CatPuzzleHint(reason: .wrongCat(cell: 12, violation: nil), removed: [12]))
                == "ヒント: 寝室の猫は答えと合わないので外すよ")
        #expect(text(CatPuzzleHint(reason: .aroundCat(cell: 1), crossed: [0]))
                == "ヒント: 居間の猫と同じ行・列・部屋と、その隣のマスに、ほかの猫はいない")
        #expect(text(CatPuzzleHint(reason: .onlyCell(group: .room(2), cell: 8), placed: 8))
                == "ヒント: 寝室で猫が入れるのはここだけ。猫はここ！")
        #expect(text(CatPuzzleHint(reason: .wouldBlock(cell: 5, blocked: .row(2)), crossed: [5]))
                == "ヒント: ここに猫がいると3行目に猫が入れなくなるので、ここに猫はいない")
        #expect(text(CatPuzzleHint(reason: .wouldBlockChain(cell: 5, blocked: .room(3)), crossed: [5]))
                == "ヒント: ここに猫がいると、決まるマスを埋めていくと書斎に猫が入れなくなるので、ここに猫はいない")
        #expect(text(CatPuzzleHint(reason: .forced(cell: 14), placed: 14))
                == "ヒント: ここは決まり。書斎の猫はここ！")
    }
}
