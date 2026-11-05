import Testing
import GameKitTestSupport
import Foundation
import CoreEngine
@testable import GameCatPuzzle

/// 4×4・部屋 4 つ。答えは行の順に列 1・3・0・2 の 1 通りだけ（手で数え上げた。`solverCountsAlternatives` でも確かめる）。
private let sample = CatPuzzle(
    side: 4,
    rooms: [
        0, 0, 1, 1,
        0, 0, 1, 1,
        2, 2, 3, 1,
        2, 2, 3, 3,
    ],
    solution: [1, 3, 0, 2]
)

@Suite("おじさんちのねこさがしのロジック")
struct CatPuzzleLogicTests {

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（6×6）", arguments: 0..<20)
    func easyPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = CatPuzzleLogic.generate(size: .easy, using: &generator)
        #expect(puzzle.side == 6)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.isSolved(puzzle: puzzle, cats: puzzle.solutionCells), "持っている答えが正しい")
        // 2 つ目の解を探しに行っても見つからない（上限を 3 にして数え切る）。
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 3) == 1)
    }

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（7×7）", arguments: NightlyScale.range(ci: 0..<4, nightly: 0..<12))
    func normalPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(1000 + seed))
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        #expect(puzzle.side == 7)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 3) == 1)
    }

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（8×8）", arguments: NightlyScale.range(ci: 0..<3, nightly: 0..<8))
    func hardPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(2000 + seed))
        let puzzle = CatPuzzleLogic.generate(size: .hard, using: &generator)
        #expect(puzzle.side == 8)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 3) == 1)
    }

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（9×9）", arguments: NightlyScale.range(ci: 0..<2, nightly: 0..<6))
    func expertPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(3000 + seed))
        let puzzle = CatPuzzleLogic.generate(size: .expert, using: &generator)
        #expect(puzzle.side == 9)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 3) == 1)
    }

    @Test("同じ種からは同じ問題ができる（日替わり用）")
    func deterministicForSeed() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        #expect(CatPuzzleLogic.generate(size: .normal, using: &a) == CatPuzzleLogic.generate(size: .normal, using: &b))
        var c = SplitMix64(seed: 43)
        #expect(CatPuzzleLogic.generate(size: .normal, using: &c) != CatPuzzleLogic.generate(size: .normal, using: &a))
    }

    @Test("日替わりの種は同じ日なら同じ、日が変われば変わる")
    func dailySeed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 7))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 7))!
        #expect(CatPuzzleLogic.dailySeed(for: morning, calendar: calendar) == CatPuzzleLogic.dailySeed(for: night, calendar: calendar))
        #expect(CatPuzzleLogic.dailySeed(for: morning, calendar: calendar) != CatPuzzleLogic.dailySeed(for: tomorrow, calendar: calendar))
    }

    @Test("どの部屋も 2 マス以上・辺の 2 倍以下の 1 かたまりで、答えの猫は部屋ごとに 1 匹", arguments: 0..<6)
    func roomsAreConnectedAndBalanced(seed: Int) {
        var generator = SplitMix64(seed: UInt64(70 + seed))
        for size in CatPuzzleSize.allCases {
            let puzzle = CatPuzzleLogic.generate(size: size, using: &generator)
            for room in 0..<puzzle.side {
                let cells = puzzle.cells(inRoom: room)
                #expect(cells.count >= 2, "\(size): 部屋 \(room) が \(cells.count) マスしかない")
                #expect(cells.count <= CatPuzzleLogic.maxRoomSize(side: puzzle.side), "\(size): 部屋 \(room) が \(cells.count) マスもある")
                #expect(CatPuzzleLogic.isConnected(cells: cells, side: puzzle.side))
            }
            #expect(Set(puzzle.solutionCells.map { puzzle.rooms[$0] }).count == puzzle.side)
        }
    }

    /// 偏りの検査（#2250）: 以前は部屋 k の答えが必ず行 k にあり、7×7 の玄関（部屋 6）は必ず最下行だった。
    /// 多数の種で、部屋ごとに答えの行・列がほぼ一様に散ることを確かめる（期待値 1/N、許容は ±0.1）。
    @Test("部屋と答えの行・列の対応に偏りが無い", arguments: [CatPuzzleSize.easy, .normal])
    func roomToRowIsNotBiased(size: CatPuzzleSize) {
        let n = size.side
        // 偏りの割合を見るので試行数が要る。CI は 18 倍、夜間は 25 倍（#2952）
        let trials = NightlyScale.value(ci: 18, nightly: 25) * n
        var rowCounts = Array(repeating: Array(repeating: 0, count: n), count: n)
        var colCounts = Array(repeating: Array(repeating: 0, count: n), count: n)
        for seed in 0..<trials {
            var generator = SplitMix64(seed: UInt64(5000 + seed))
            let puzzle = CatPuzzleLogic.generate(size: size, using: &generator)
            for (row, col) in puzzle.solution.enumerated() {
                let room = puzzle.rooms[row * n + col]
                rowCounts[room][row] += 1
                colCounts[room][col] += 1
            }
        }
        let expected = 1.0 / Double(n)
        for room in 0..<n {
            for line in 0..<n {
                let rowRate = Double(rowCounts[room][line]) / Double(trials)
                let colRate = Double(colCounts[room][line]) / Double(trials)
                #expect(abs(rowRate - expected) < 0.1, "\(size): 部屋 \(room) の答えが行 \(line) にある割合 \(rowRate)")
                #expect(abs(colRate - expected) < 0.1, "\(size): 部屋 \(room) の答えが列 \(line) にある割合 \(colRate)")
            }
        }
        // 名指しの例: いちばん最後の部屋（7×7 では玄関）の答えが最下行にある割合が 1/N に近い。
        let lastRoomBottom = Double(rowCounts[n - 1][n - 1]) / Double(trials)
        #expect(abs(lastRoomBottom - expected) < 0.1, "\(size): 最後の部屋が最下行 \(lastRoomBottom)")
    }

    @Test("混ぜても問題は壊れない: 形が正しく、解は 1 つで、持っている答えが解のまま", arguments: 0..<16)
    func shuffleKeepsPuzzle(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let mixed = CatPuzzleLogic.shuffled(sample, using: &generator)
        #expect(CatPuzzleLogic.isWellFormed(mixed))
        #expect(CatPuzzleLogic.isSolved(puzzle: mixed, cats: mixed.solutionCells))
        #expect(CatPuzzleLogic.countSolutions(side: 4, rooms: mixed.rooms, limit: 3) == 1)
        let sizes = { (p: CatPuzzle) in (0..<4).map { p.cells(inRoom: $0).count }.sorted() }
        #expect(sizes(mixed) == sizes(sample), "部屋の広さの組は変わらない")
    }

    @Test("答えの形: 各列に 1 匹で、隣の行と隣り合わない")
    func placementValidity() {
        #expect(CatPuzzleLogic.isValidPlacement([1, 3, 0, 2], side: 4))
        #expect(!CatPuzzleLogic.isValidPlacement([0, 1, 2, 3], side: 4), "隣の行で隣り合う")
        #expect(!CatPuzzleLogic.isValidPlacement([0, 0, 2, 3], side: 4), "同じ列")
        #expect(!CatPuzzleLogic.isValidPlacement([0, 2], side: 4), "行が足りない")
        var generator = SplitMix64(seed: 3)
        for _ in 0..<20 {
            #expect(CatPuzzleLogic.isValidPlacement(CatPuzzleLogic.randomPlacement(side: 8, using: &generator), side: 8))
        }
    }

    @Test("数え上げ: 部屋を行ごとに切ると解が複数、見本の 4×4 は 1 つ、部屋が 1 列なら 0")
    func solverCountsAlternatives() {
        // 部屋 = 行（部屋の条件が効かない）。4×4 で隣り合わない並びは 2 通り（1302・2031）。
        let rowRooms = (0..<16).map { $0 / 4 }
        #expect(CatPuzzleLogic.countSolutions(side: 4, rooms: rowRooms, limit: 10) == 2)
        #expect(CatPuzzleLogic.countSolutions(side: 4, rooms: sample.rooms, limit: 10) == 1)
        #expect(CatPuzzleLogic.isWellFormed(sample))
        // 部屋 = 列（各列に 1 匹と同じ条件）で、上限で打ち切れる。
        let colRooms = (0..<16).map { $0 % 4 }
        #expect(CatPuzzleLogic.countSolutions(side: 4, rooms: colRooms, limit: 1) == 1)
        // 上 2 行がまるごと部屋 0 → 行 0 と行 1 の猫が同じ部屋になるので、解なし。
        let impossible = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 1, 1, 3, 3]
        #expect(CatPuzzleLogic.countSolutions(side: 4, rooms: impossible, limit: 10) == 0)
    }

    @Test("矛盾の判定: 同じ行・列・部屋・隣を種類ごとに拾い、両方の猫に印を付ける")
    func violationsAreDetected() {
        #expect(CatPuzzleLogic.violations(puzzle: sample, cats: []).isEmpty)
        #expect(CatPuzzleLogic.violations(puzzle: sample, cats: [1]).isEmpty)
        let row = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 3])
        #expect(row.kinds == [.row] && row.cells == [1, 3])
        #expect(row.rows == [0] && row.columns.isEmpty && row.rooms.isEmpty && row.adjacentPairs.isEmpty, "違反している行を帯で示す")
        let column = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 13])
        #expect(column.kinds == [.column] && column.cells == [1, 13])
        #expect(column.columns == [1] && column.rows.isEmpty)
        let room = CatPuzzleLogic.violations(puzzle: sample, cats: [0, 5])
        #expect(room.kinds == [.room, .adjacent] && room.cells == [0, 5], "同じ部屋でななめ隣")
        #expect(room.rooms == [0] && room.adjacentPairs == [.init(0, 5)])
        let adjacent = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 6])
        #expect(adjacent.kinds == [.adjacent] && adjacent.cells == [1, 6], "別の部屋でななめ隣")
        #expect(adjacent.adjacentPairs == [.init(6, 1)] && adjacent.rooms.isEmpty)
        let mixed = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 3, 8])
        #expect(mixed.kinds == [.row] && mixed.cells == [1, 3], "関係ない猫には印を付けない")
        #expect(mixed.rows == [0])
    }

    @Test("クリアの判定: 猫が部屋の数だけ置けて矛盾が無いときだけ")
    func solvedDetection() {
        #expect(CatPuzzleLogic.isSolved(puzzle: sample, cats: sample.solutionCells))
        #expect(!CatPuzzleLogic.isSolved(puzzle: sample, cats: Array(sample.solutionCells.prefix(3))), "1 匹足りない")
        #expect(!CatPuzzleLogic.isSolved(puzzle: sample, cats: [1, 7, 9, 14]), "4 匹でも同じ列がある")
    }

    @Test("隣の判定: ななめも隣、2 マス離れたら隣でない、同じマスは隣でない")
    func adjacency() {
        #expect(CatPuzzleLogic.isAdjacent(5, 10, side: 4))
        #expect(CatPuzzleLogic.isAdjacent(5, 6, side: 4))
        #expect(!CatPuzzleLogic.isAdjacent(5, 7, side: 4))
        #expect(!CatPuzzleLogic.isAdjacent(3, 4, side: 4), "行末と次の行の先頭は隣でない")
        #expect(!CatPuzzleLogic.isAdjacent(5, 5, side: 4))
    }

    @Test("形の検査: 部屋が切れている・答えが部屋に重なる・番号が外れた問題を弾く")
    func wellFormedRejectsBrokenPuzzles() {
        var split = sample.rooms
        split[15] = 0
        #expect(!CatPuzzleLogic.isWellFormed(CatPuzzle(side: 4, rooms: split, solution: [1, 3, 0, 2])), "部屋 0 が切れている")
        var shared = sample.rooms
        shared[14] = 2
        #expect(!CatPuzzleLogic.isWellFormed(CatPuzzle(side: 4, rooms: shared, solution: [1, 3, 0, 2])), "答えの 2 匹が同じ部屋")
        #expect(!CatPuzzleLogic.isWellFormed(CatPuzzle(side: 4, rooms: sample.rooms, solution: [1, 3, 0, 1])), "答えが壊れている")
        #expect(!CatPuzzleLogic.isWellFormed(CatPuzzle(side: 4, rooms: Array(sample.rooms.dropLast()), solution: [1, 3, 0, 2])), "マスが足りない")
        #expect(!CatPuzzleLogic.isWellFormed(CatPuzzle(side: 4, rooms: sample.rooms.map { $0 + 1 }, solution: [1, 3, 0, 2])), "部屋の番号が外れている")
    }
}
