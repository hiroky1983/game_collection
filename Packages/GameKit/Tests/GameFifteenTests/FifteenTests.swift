import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GameFifteen
import CoreTestSupport

@Suite("15パズルのロジック")
struct FifteenLogicTests {

    @Test("揃った盤は解ける・転倒数 0")
    func solvedBoard() {
        #expect(FifteenLogic.isSolved(FifteenLogic.solved))
        #expect(FifteenLogic.inversions(FifteenLogic.solved) == 0)
        #expect(FifteenLogic.isSolvable(FifteenLogic.solved))
    }

    @Test("14 と 15 だけを入れ替えた盤は解けない（有名な解けない配置）")
    func swappedFourteenFifteenIsUnsolvable() {
        var tiles = FifteenLogic.solved
        tiles.swapAt(13, 14)
        #expect(!FifteenLogic.isSolvable(tiles))
    }

    @Test("空白の位置も偶奇に効く（空白が 1 行上がると判定が反転する）")
    func blankRowMatters() {
        // 揃った盤から空白を 1 手上へ動かした盤は解ける（合法手で作れる）。
        let moved = FifteenLogic.slide(FifteenLogic.solved, at: 11)!.tiles
        #expect(FifteenLogic.isSolvable(moved))
        // そこから別のタイルを 1 枚だけ入れ替えると解けなくなる。
        var broken = moved
        broken.swapAt(0, 1)
        #expect(!FifteenLogic.isSolvable(broken))
    }

    @Test("並びが不正な盤（枚数違い・重複）は解けない扱い")
    func invalidBoards() {
        #expect(!FifteenLogic.isSolvable([1, 2, 3]))
        #expect(!FifteenLogic.isSolvable(Array(repeating: 1, count: 16)))
        #expect(!FifteenLogic.isPermutation(Array(0..<15) + [3]))
    }

    @Test("シャッフルは何度やっても必ず解け、揃ってもいない")
    func shuffleIsAlwaysSolvable() {
        for seed in 0..<500 {
            var generator = SplitMix64(seed: UInt64(seed))
            let tiles = FifteenLogic.shuffled(using: &generator)
            #expect(FifteenLogic.isPermutation(tiles), "seed \(seed)")
            #expect(FifteenLogic.isSolvable(tiles), "seed \(seed)")
            #expect(!FifteenLogic.isSolved(tiles), "seed \(seed)")
        }
    }

    @Test("対照: 単純な並べ替えだけだと、解けない配置が約半分出る")
    func naiveShuffleProducesUnsolvableBoards() {
        var generator = SplitMix64(seed: 7)
        let unsolvable = (0..<500).filter { _ in
            !FifteenLogic.isSolvable(Array(0..<16).shuffled(using: &generator))
        }.count
        // 補正なしの並べ替えでは半分前後が解けない。この対照が 0 なら上のテストは何も守っていない。
        #expect(unsolvable > 150)
    }

    @Test("空白の隣のタイルは 1 枚だけ動く")
    func slideAdjacent() throws {
        let result = try #require(FifteenLogic.slide(FifteenLogic.solved, at: 14))
        #expect(result.distance == 1)
        #expect(result.tiles[14] == 0)
        #expect(result.tiles[15] == 15)
    }

    @Test("空白と同じ行・列のタイルは間をまとめて寄せる")
    func slideMultiple() throws {
        // 空白は右下（15）。同じ行の左端（12）をタップすると 3 枚が右へ寄る。
        let row = try #require(FifteenLogic.slide(FifteenLogic.solved, at: 12))
        #expect(row.distance == 3)
        #expect(Array(row.tiles[12...15]) == [0, 13, 14, 15])
        // 同じ列の上端（3）をタップすると 3 枚が下へ寄る。
        let column = try #require(FifteenLogic.slide(FifteenLogic.solved, at: 3))
        #expect(column.distance == 3)
        let moved: [Int] = [column.tiles[3], column.tiles[7], column.tiles[11], column.tiles[15]]
        #expect(moved == [0, 4, 8, 12])
    }

    @Test("空白と行も列も違うタイル・空白自身・範囲外は動かない")
    func slideRejected() {
        #expect(FifteenLogic.slide(FifteenLogic.solved, at: 0) == nil)
        #expect(FifteenLogic.slide(FifteenLogic.solved, at: 15) == nil)
        #expect(FifteenLogic.slide(FifteenLogic.solved, at: 16) == nil)
        #expect(FifteenLogic.slide(FifteenLogic.solved, at: -1) == nil)
    }

    @Test("動かしても盤は 1〜15 と空白の並びのまま・解ける性質は保たれる")
    func slidePreservesSolvability() {
        var generator = SplitMix64(seed: 11)
        var tiles = FifteenLogic.shuffled(using: &generator)
        for step in 0..<200 {
            let index = Int.random(in: 0..<16, using: &generator)
            if let result = FifteenLogic.slide(tiles, at: index) { tiles = result.tiles }
            #expect(FifteenLogic.isSolvable(tiles), "step \(step)")
        }
    }
}

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil
) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService(), playLog: log)
}

@MainActor
@Suite("15パズルの Model")
struct FifteenModelTests {

    /// あと 1 手（15 を左へ）で揃う盤。
    private static let oneMoveAway: [Int] = Array(1...14) + [0, 15]

    @Test("開始直後の盤は解ける配置で、手数は 0")
    func freshBoard() {
        let model = FifteenModel(services: makeServices(), seed: 2026)
        #expect(FifteenLogic.isSolvable(model.tiles))
        #expect(!model.isSolved)
        #expect(model.moves == 0)
    }

    @Test("新規ゲームのたびに解ける配置になり、手数と決着が戻る")
    func newGameResets() {
        let model = FifteenModel(services: makeServices(), seed: 1)
        for _ in 0..<50 {
            model.newGame()
            #expect(FifteenLogic.isSolvable(model.tiles))
            #expect(!model.isSolved)
        }
        let start = FifteenModel(services: makeServices(), tiles: Self.oneMoveAway)
        start.tap(at: 15)
        #expect(start.isSolved)
        start.newGame()
        #expect(!start.isSolved)
        #expect(start.moves == 0)
        #expect(start.recordResult == nil)
    }

    @Test("揃えると決着し、手数を最少手数として記録する")
    func solvingRecordsMoves() throws {
        let defaults = UserDefaults(suiteName: "asobiba.fifteen.tests.record")!
        defaults.removePersistentDomain(forName: "asobiba.fifteen.tests.record")
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        let model = FifteenModel(services: makeServices(store: store, log: log), tiles: Self.oneMoveAway)
        model.tap(at: 15)
        #expect(model.isSolved)
        #expect(model.moves == 1)
        #expect(log.record(gameID: "fifteen")?.metric == .fewestMoves)
        #expect(log.record(gameID: "fifteen")?.fewestMoves == 1)
        #expect(log.record(gameID: "fifteen")?.wins == 1)
        #expect(store.load(FifteenSnapshot.self, for: "fifteen") == nil, "決着で中断データを消す")
    }

    @Test("決着後のタップは盤も手数も動かさず、二重に記録しない")
    func tapAfterSolvedIsIgnored() {
        let defaults = UserDefaults(suiteName: "asobiba.fifteen.tests.twice")!
        defaults.removePersistentDomain(forName: "asobiba.fifteen.tests.twice")
        let log = PlayLog(defaults: defaults)
        let model = FifteenModel(services: makeServices(log: log), tiles: Self.oneMoveAway)
        model.tap(at: 15)
        model.tap(at: 14)
        #expect(model.moves == 1)
        #expect(FifteenLogic.isSolved(model.tiles))
        #expect(log.record(gameID: "fifteen")?.plays == 1)
    }

    @Test("動かせないタップは手数を増やさない")
    func rejectedTapDoesNotCountMove() {
        let model = FifteenModel(services: makeServices(), tiles: FifteenLogic.slide(FifteenLogic.solved, at: 14)!.tiles)
        let before = model.tiles
        model.tap(at: 0)
        #expect(model.tiles == before)
        #expect(model.moves == 0)
    }

    @Test("まとめて寄せた手数は動いたタイルの枚数")
    func multiSlideCountsEachTile() {
        // 揃った盤から始めると決着済みでタップが効かないので、先頭 2 枚を入れ替えた盤を使う（動かす部分には無関係）。
        var tiles = FifteenLogic.solved
        tiles.swapAt(0, 1)
        let model = FifteenModel(services: makeServices(), tiles: tiles)
        model.tap(at: 12)
        #expect(model.moves == 3)
    }

    @Test("途中の局は中断データから復元される（手数ごと）")
    func restoresInProgress() {
        let store = MemorySnapshotStore()
        let first = FifteenModel(services: makeServices(store: store), seed: 5)
        first.tap(at: first.tiles.firstIndex(of: 0)! == 0 ? 1 : 0)
        let restored = FifteenModel(services: makeServices(store: store), seed: 99)
        #expect(restored.tiles == first.tiles)
        #expect(restored.moves == first.moves)
    }

    @Test("解けない配置・揃った盤・壊れた盤の中断データは捨てて新しい盤にする")
    func rejectsBadSnapshots() throws {
        var unsolvable = FifteenLogic.solved
        unsolvable.swapAt(13, 14)
        let bad: [[Int]] = [unsolvable, FifteenLogic.solved, [1, 2, 3], Array(repeating: 1, count: 16)]
        for tiles in bad {
            let store = MemorySnapshotStore()
            try store.save(FifteenSnapshot(tiles: tiles, moves: 3), for: "fifteen")
            let model = FifteenModel(services: makeServices(store: store), seed: 3)
            #expect(model.tiles != tiles)
            #expect(FifteenLogic.isSolvable(model.tiles))
            #expect(model.moves == 0)
        }
    }

    @Test("読み上げ文は行・列と値（空白は「空き」）")
    func accessibilityLabels() {
        #expect(FifteenAccessibility.cellLabel(index: 6, value: 7) == "2行3列、7")
        #expect(FifteenAccessibility.cellLabel(index: 15, value: 0) == "4行4列、空き")
    }
}
