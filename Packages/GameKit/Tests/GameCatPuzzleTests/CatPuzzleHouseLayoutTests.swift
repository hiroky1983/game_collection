import Testing
import Core
import CoreTestSupport
@testable import GameCatPuzzle

/// 家具・ドア・窓の自動配置（`CatPuzzleHouseLayout`・#2250 ドールハウス）。
/// 6×6 / 7×7 / 8×8 の多数の種で、家具が部屋からはみ出さない・ドアが共有壁の上にある・全部屋がつながる、を確かめる。
@Suite("おじさんの飼い猫パズルの家の配置")
@MainActor
struct CatPuzzleHouseLayoutTests {
    private static func services() -> GameServices {
        GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    }

    /// 問題作りはデバッグビルドだと 1 問 1 秒ほどかかるので、大きい盤は種を絞る（`CatPuzzleRenderTests` と同じ配分）。
    private static let seeds: [(CatPuzzleSize, ClosedRange<UInt64>)] = [(.easy, 1...30), (.normal, 1...30), (.hard, 1...8)]

    private static func puzzles() -> [(seed: UInt64, puzzle: CatPuzzle)] {
        seeds.flatMap { size, range in
            range.map { ($0, CatPuzzleModel(services: services(), size: size, seed: $0).puzzle) }
        } + [(0, CatPuzzleHowToFigures.sample)]
    }

    @Test("家具は部屋ごとに 1 つ、部屋のマスだけを覆い、盤からはみ出さない")
    func furnitureStaysInsideRoom() {
        for (seed, puzzle) in Self.puzzles() {
            let n = puzzle.side
            let layout = CatPuzzleHouseLayout.compute(for: puzzle)
            #expect(layout.furniture.count == n, "種 \(seed)（\(n)×\(n)）の家具の数")
            #expect(Set(layout.furniture.map(\.room)).count == n)
            for item in layout.furniture {
                #expect(item.kind == CatPuzzleHouse.room(item.room).furniture)
                #expect((1...2).contains(item.width) && (1...2).contains(item.height))
                // 2×2 はこたつ・縁側だけ（2×2 が入らない部屋では 2×1 / 1×2 / 1×1 になる）。
                if !item.kind.isSquare { #expect(item.width == 1 || item.height == 1) }
                #expect(item.row >= 0 && item.col >= 0 && item.row + item.height <= n && item.col + item.width <= n,
                        "種 \(seed) の部屋 \(item.room) の家具が盤の外")
                for cell in item.cells(side: n) {
                    #expect(puzzle.rooms[cell] == item.room, "種 \(seed) の部屋 \(item.room) の家具が隣の部屋にはみ出す")
                }
            }
            // 1 マスだけの部屋には 1×1。
            for room in 0..<n where puzzle.cells(inRoom: room).count == 1 {
                let item = layout.furniture.first { $0.room == room }
                #expect(item?.width == 1 && item?.height == 1)
            }
        }
    }

    @Test("ドアは 2 部屋の共有壁の上にあり、全域木（部屋の数 − 1 枚）で全部屋がつながる")
    func doorsConnectEveryRoom() {
        for (seed, puzzle) in Self.puzzles() {
            let n = puzzle.side
            let layout = CatPuzzleHouseLayout.compute(for: puzzle)
            #expect(layout.doors.count == n - 1, "種 \(seed)（\(n)×\(n)）のドアの数")
            let wallSet = Set(layout.walls)
            // 素集合データ構造で、ドアでつながる部屋をまとめる。
            var parent = Array(0..<n)
            func find(_ x: Int) -> Int { var x = x; while parent[x] != x { x = parent[x] }; return x }
            for door in layout.doors {
                let s = door.segment
                #expect(wallSet.contains(s), "種 \(seed) のドアが壁の上にない")
                let cells = s.cells(side: n)
                #expect(puzzle.rooms[cells.a] == s.roomA && puzzle.rooms[cells.b] == s.roomB && s.roomA != s.roomB)
                let (ra, rb) = (find(s.roomA), find(s.roomB))
                #expect(ra != rb, "種 \(seed) のドアが同じ組の部屋をもう一度つなぐ（木になっていない）")
                parent[ra] = rb
            }
            #expect(Set((0..<n).map(find)).count == 1, "種 \(seed) でドアを通って行けない部屋がある")
            // 同じ壁の辺に 2 枚は置かない。
            #expect(layout.doorSegments.count == layout.doors.count)
        }
    }

    @Test("ドアは扉の前に家具が無い側へ開く")
    func doorsOpenAwayFromFurniture() {
        for (seed, puzzle) in Self.puzzles() {
            let n = puzzle.side
            let layout = CatPuzzleHouseLayout.compute(for: puzzle)
            let occupied = Set(layout.furniture.flatMap { $0.cells(side: n) })
            for door in layout.doors {
                let cells = door.segment.cells(side: n)
                if occupied.contains(cells.b) && !occupied.contains(cells.a) {
                    #expect(!door.opensTowardB, "種 \(seed) のドアが家具のある側へ開く")
                } else if occupied.contains(cells.a) && !occupied.contains(cells.b) {
                    #expect(door.opensTowardB, "種 \(seed) のドアが家具のある側へ開く")
                }
            }
        }
    }

    @Test("窓は外周に接する部屋ごとに 1 つ、外周のマスの外側の辺に付く（押し入れは無し・玄関は玄関戸）")
    func windowsSitOnOuterWall() {
        for (seed, puzzle) in Self.puzzles() {
            let n = puzzle.side
            let layout = CatPuzzleHouseLayout.compute(for: puzzle)
            let roomsOnEdge = Set((0..<puzzle.cellCount).filter { cell in
                let r = cell / n, c = cell % n
                return r == 0 || r == n - 1 || c == 0 || c == n - 1
            }.map { puzzle.rooms[$0] })
            let expected = roomsOnEdge.filter { CatPuzzleHouse.room($0).furniture != .oshiire }
            #expect(Set(layout.windows.map(\.room)) == expected, "種 \(seed)（\(n)×\(n)）の窓のある部屋")
            #expect(layout.windows.count == expected.count, "種 \(seed) で 1 部屋に窓が 2 つ")
            for window in layout.windows {
                #expect(puzzle.rooms[window.cell] == window.room)
                let r = window.cell / n, c = window.cell % n
                switch window.side {
                case .top: #expect(r == 0)
                case .bottom: #expect(r == n - 1)
                case .left: #expect(c == 0)
                case .right: #expect(c == n - 1)
                }
                #expect(window.isEntrance == (CatPuzzleHouse.room(window.room).furniture == .genkan))
            }
        }
    }

    @Test("同じ盤なら同じ配置（キャッシュも同じものを返す）")
    func layoutIsDeterministic() {
        let puzzle = CatPuzzleModel(services: Self.services(), size: .normal, seed: 3).puzzle
        let a = CatPuzzleHouseLayout.compute(for: puzzle)
        let b = CatPuzzleHouseLayout.compute(for: puzzle)
        #expect(a == b)
        #expect(CatPuzzleHouseLayout.cached(for: puzzle) == a)
        #expect(CatPuzzleHouseLayout.cached(for: puzzle) == a)
    }

    @Test("遊び方の 4×4 の見本: こたつは 2×2、押し入れの窓は無く、ドアは 3 枚")
    func sampleLayout() {
        let layout = CatPuzzleHouseLayout.compute(for: CatPuzzleHowToFigures.sample)
        let kotatsu = layout.furniture.first { $0.kind == .kotatsu }
        #expect(kotatsu?.width == 2 && kotatsu?.height == 2 && kotatsu?.row == 0 && kotatsu?.col == 0)
        #expect(layout.doors.count == 3)
        #expect(!layout.windows.contains { $0.room == 1 })
    }
}
