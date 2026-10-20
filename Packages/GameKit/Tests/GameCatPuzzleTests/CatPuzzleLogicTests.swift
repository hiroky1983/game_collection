import Testing
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

@Suite("おじさんの飼い猫パズルのロジック")
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

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（7×7）", arguments: 0..<12)
    func normalPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(1000 + seed))
        let puzzle = CatPuzzleLogic.generate(size: .normal, using: &generator)
        #expect(puzzle.side == 7)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 3) == 1)
    }

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（8×8）", arguments: 0..<8)
    func hardPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(2000 + seed))
        let puzzle = CatPuzzleLogic.generate(size: .hard, using: &generator)
        #expect(puzzle.side == 8)
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
        let column = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 13])
        #expect(column.kinds == [.column] && column.cells == [1, 13])
        let room = CatPuzzleLogic.violations(puzzle: sample, cats: [0, 5])
        #expect(room.kinds == [.room, .adjacent] && room.cells == [0, 5], "同じ部屋でななめ隣")
        let adjacent = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 6])
        #expect(adjacent.kinds == [.adjacent] && adjacent.cells == [1, 6], "別の部屋でななめ隣")
        let mixed = CatPuzzleLogic.violations(puzzle: sample, cats: [1, 3, 8])
        #expect(mixed.kinds == [.row] && mixed.cells == [1, 3], "関係ない猫には印を付けない")
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
