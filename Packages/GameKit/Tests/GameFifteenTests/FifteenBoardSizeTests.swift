import Testing
import Foundation
import Core
import GameKitTestSupport
import CoreTestSupport
import CoreEngine
@testable import GameFifteen

private func makeServices(store: MemorySnapshotStore = MemorySnapshotStore(), log: PlayLog? = nil) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService(), playLog: log)
}

@Suite("15パズルの盤の大きさ（#2869）")
struct FifteenBoardSizeLogicTests {

    @Test("選べる大きさは 3・4・5 で、既定は 4×4（従来の盤）", arguments: [3, 4, 5])
    func sizes(size: Int) {
        #expect(FifteenLogic.sizes == 3...5)
        #expect(FifteenLogic.defaultSize == 4)
        #expect(FifteenLogic.size(ofCellCount: size * size) == size)
        #expect(FifteenLogic.solved == FifteenLogic.solved(size: 4))
    }

    @Test("盤の長さが 3×3・4×4・5×5 のどれでもなければ盤として扱わない")
    func invalidLength() {
        #expect(FifteenLogic.size(ofCellCount: 15) == nil)
        #expect(!FifteenLogic.isPermutation(Array(0..<10)))
        #expect(!FifteenLogic.isSolvable(Array(0..<36)))
    }

    @Test("どの大きさでも揃った盤は解ける・揃っている", arguments: [3, 4, 5])
    func solvedBoard(size: Int) {
        let solved = FifteenLogic.solved(size: size)
        #expect(solved.count == size * size)
        #expect(FifteenLogic.isSolved(solved))
        #expect(FifteenLogic.isSolvable(solved))
    }

    @Test("幅が奇数の盤は、最後の 2 枚を入れ替えると解けない（偶奇は転倒数だけ）", arguments: [3, 5])
    func oddWidthParity(size: Int) {
        var tiles = FifteenLogic.solved(size: size)
        tiles.swapAt(size * size - 3, size * size - 2)
        #expect(!FifteenLogic.isSolvable(tiles))
        // 合法手（空白を動かす）では解ける性質が変わらない。
        let moved = FifteenLogic.slide(FifteenLogic.solved(size: size), at: size * size - 1 - size)!.tiles
        #expect(FifteenLogic.isSolvable(moved))
    }

    @Test("シャッフルはどの大きさでも必ず解け、揃ってもいない", arguments: [3, 4, 5])
    func shuffledIsSolvable(size: Int) {
        var generator = SplitMix64(seed: UInt64(size))
        for _ in 0..<300 {
            let tiles = FifteenLogic.shuffled(size: size, using: &generator)
            #expect(tiles.count == size * size)
            #expect(FifteenLogic.isSolvable(tiles))
            #expect(!FifteenLogic.isSolved(tiles))
        }
    }

    @Test("まとめて寄せる動きは大きさに合わせた行・列で判定する", arguments: [3, 5])
    func slideUsesBoardWidth(size: Int) {
        let solved = FifteenLogic.solved(size: size)
        let last = size * size - 1
        // 空白（右下）と同じ列の先頭のタイルを押すと、列の全部が 1 マスずつ下がる。
        let result = FifteenLogic.slide(solved, at: size - 1)
        #expect(result?.distance == size - 1)
        // 空白と行も列も違うタイルは動かない。
        #expect(FifteenLogic.slide(solved, at: 0) == nil)
        #expect(FifteenLogic.slide(solved, at: last) == nil)
    }
}

@Suite("15パズルのヒント（盤の大きさ別・#2869）")
struct FifteenBoardSizeHintTests {

    @Test("ヒントの通りに動かし続けると、3×3 の盤も揃う", arguments: 0..<6)
    func followingHintsSolvesThreeByThree(seed: Int) throws {
        var generator = SplitMix64(seed: UInt64(seed))
        var tiles = FifteenLogic.shuffled(size: 3, using: &generator)
        var steps = 0
        while !FifteenLogic.isSolved(tiles) {
            let index = try #require(FifteenHintSolver.nextIndex(tiles), "seed \(seed) step \(steps)")
            let slid = try #require(FifteenLogic.slide(tiles, at: index))
            #expect(slid.distance == 1)
            tiles = slid.tiles
            steps += 1
            try #require(steps <= 200, "seed \(seed) が収束しない")
        }
    }

    /// 5×5 を最後まで辿ると Debug ビルドでは数分かかるので、最初の数手が空白の隣を示すことだけを見る
    /// （最後まで揃うことは release ビルドの実測で確認済み・#2869）。
    @Test("5×5 のヒントは空白の隣の 1 枚を示し続ける", arguments: 0..<2)
    func fiveByFiveHintsAreLegalSteps(seed: Int) throws {
        var generator = SplitMix64(seed: UInt64(seed))
        var tiles = FifteenLogic.shuffled(size: 5, using: &generator)
        for step in 0..<3 {
            let index = try #require(FifteenHintSolver.nextIndex(tiles), "seed \(seed) step \(step)")
            let slid = try #require(FifteenLogic.slide(tiles, at: index))
            #expect(slid.distance == 1)
            tiles = slid.tiles
        }
        #expect(FifteenLogic.isSolvable(tiles))
    }
}

@MainActor
@Suite("15パズルの Model（盤の大きさ別・#2869）")
struct FifteenBoardSizeModelTests {

    private func makeLog(_ name: String) -> PlayLog {
        let defaults = UserDefaults(suiteName: "asobiba.fifteen.tests.size.\(name)")!
        defaults.removePersistentDomain(forName: "asobiba.fifteen.tests.size.\(name)")
        return PlayLog(defaults: defaults)
    }

    @Test("指定した大きさで始まり、新規ゲームは同じ大きさで始め直す", arguments: [3, 4, 5])
    func startsWithSize(size: Int) {
        let model = FifteenModel(services: makeServices(), seed: 7, size: size)
        #expect(model.size == size)
        #expect(model.tiles.count == size * size)
        #expect(FifteenLogic.isSolvable(model.tiles))
        model.newGame()
        #expect(model.size == size)
    }

    @Test("新規ゲームで大きさを切り替えられ、範囲外の指定は無視する")
    func switchSize() {
        let model = FifteenModel(services: makeServices(), seed: 3)
        #expect(model.size == 4)
        model.newGame(size: 5)
        #expect(model.size == 5)
        #expect(model.moves == 0)
        model.newGame(size: 9)
        #expect(model.size == 5)
        model.newGame(size: 3)
        #expect(model.size == 3)
        #expect(FifteenLogic.isSolvable(model.tiles))
    }

    @Test("範囲外の大きさで開始したら 4×4")
    func invalidStartSize() {
        #expect(FifteenModel(services: makeServices(), seed: 1, size: 7).size == 4)
    }

    @Test("中断データは盤の長さの大きさで復元される（3×3・5×5）", arguments: [3, 5])
    func restoreKeepsSize(size: Int) throws {
        let store = MemorySnapshotStore()
        let first = FifteenModel(services: makeServices(store: store), seed: 5, size: size)
        let index = try #require(first.tiles.indices.first { FifteenLogic.slide(first.tiles, at: $0) != nil })
        first.tap(at: index)
        let restored = FifteenModel(services: makeServices(store: store), seed: 1)
        #expect(restored.size == size)
        #expect(restored.tiles == first.tiles)
        #expect(restored.moves == first.moves)
    }

    @Test("16 枚の従来の中断データは 4×4 のまま読める")
    func legacySnapshotIsFourByFour() throws {
        let store = MemorySnapshotStore()
        let tiles = FifteenLogic.slide(FifteenLogic.solved, at: 11)!.tiles
        try store.save(FifteenSnapshot(tiles: tiles, moves: 3), for: "fifteen")
        let model = FifteenModel(services: makeServices(store: store), size: 5)
        #expect(model.size == 4)
        #expect(model.tiles == tiles)
    }

    @Test("記録は盤の大きさごとに分かれる（4×4 は従来の保存先）")
    func recordsAreSeparatedBySize() throws {
        #expect(FifteenModel.recordVariant(size: 4) == nil)
        #expect(FifteenModel.recordVariant(size: 3) == "3x3")
        #expect(FifteenModel.recordVariant(size: 5) == "5x5")

        let log = makeLog("record")
        for size in [3, 4, 5] {
            let solved = FifteenLogic.solved(size: size)
            let almost = try #require(FifteenLogic.slide(solved, at: size * size - 1 - size)).tiles
            let model = FifteenModel(services: makeServices(log: log), tiles: almost)
            model.tap(at: size * size - 1)
            #expect(model.isSolved)
        }
        #expect(log.record(gameID: "fifteen")?.fewestMoves == 1)
        #expect(log.record(gameID: "fifteen", variant: "3x3")?.fewestMoves == 1)
        #expect(log.record(gameID: "fifteen", variant: "5x5")?.fewestMoves == 1)
        #expect(log.record(gameID: "fifteen", variant: "3x3")?.variantLabel == "3×3")
        #expect(log.record(gameID: "fifteen")?.wins == 1, "3×3・5×5 の勝ちは 4×4 の記録に混ざらない")
    }

    @Test("自己ベストは今の盤の大きさの記録を出す")
    func savedBestFollowsSize() {
        let log = makeLog("best")
        _ = log.recordResult(gameID: "fifteen", outcome: .win, score: GameScore(metric: .fewestMoves, moves: 80))
        _ = log.recordResult(gameID: "fifteen", outcome: .win,
                             score: GameScore(metric: .fewestMoves, moves: 20, variant: "3x3", variantLabel: "3×3"))
        let model = FifteenModel(services: makeServices(log: log), seed: 1)
        #expect(model.savedBestMoves == 80)
        model.newGame(size: 3)
        #expect(model.savedBestMoves == 20)
        model.newGame(size: 5)
        #expect(model.savedBestMoves == nil)
    }

    @Test("区分の表示名は言語で変わらない")
    func variantLabels() {
        #expect(RecordVariantLabels.label(recordKey: "fifteen#3x3", language: .english) == "3×3")
        #expect(RecordVariantLabels.label(recordKey: "fifteen#5x5", language: .japanese) == "5×5")
        #expect(RecordVariantLabels.label(recordKey: "fifteen#4x4") == nil)
    }

    @Test("読み上げ文は盤の大きさに合わせた行・列")
    func accessibilityUsesSize() {
        #expect(FifteenAccessibility.cellLabel(index: 7, value: 3, size: 5) == tr("%1$lld行%2$lld列、%3$lld", 2, 3, 3))
    }
}
