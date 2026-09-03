import Testing
import Foundation
import Core
@testable import GameMinesweeper

/// テスト専用の中断データ置き場（`MinesweeperChordTests` と同じ手口。ファイルに書かない）。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ value: T, for key: String) throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func load<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(for key: String) { storage[key] = nil }
    func exists(for key: String) -> Bool { storage[key] != nil }

    /// 保存済みの生の JSON。**旧形式の互換フィールドが書かれ続けているか**を確かめるために覗く。
    func rawJSON(for key: String) -> [String: Any]? {
        guard let data = storage[key] else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// 任意の JSON をそのまま置く（旧形式の中断データを注入するため）。
    func inject(_ object: Any, for key: String) {
        storage[key] = try? JSONSerialization.data(withJSONObject: object)
    }
}

/// 旗の「?」状態（#444）。
///
/// 本家（Windows）と同じ「なし → 旗 → ? → なし」の循環を入れた。`?` は旗ではないので、
/// **残り地雷カウンタにもコード（#437）の旗数にも数えず、通常の未開放マスと同じく開ける**。
@Suite("マインスイーパーの ? マーク（#444）")
@MainActor
struct MinesweeperMarkTests {

    private static func makeServices() -> (GameServices, MemorySnapshotStore) {
        let store = MemorySnapshotStore()
        return (GameServices(snapshots: store, ads: NoopAdService()), store)
    }

    /// 地雷の配置と開放・マークを決め打ちした盤を、中断スナップショット経由で作る。
    private static func makeModel(
        rows: Int,
        cols: Int,
        mines: [(row: Int, col: Int)],
        revealed: [(row: Int, col: Int)] = [],
        marks: [(row: Int, col: Int, mark: MinesweeperMark)] = [],
        store: MemorySnapshotStore = MemorySnapshotStore()
    ) -> MinesweeperModel {
        let mineSet     = Set(mines.map { $0.row * cols + $0.col })
        let revealedSet = Set(revealed.map { $0.row * cols + $0.col })
        var markMap: [Int: MinesweeperMark] = [:]
        for m in marks { markMap[m.row * cols + m.col] = m.mark }

        let cells = (0..<rows).map { r in
            (0..<cols).map { c -> MinesweeperSnapshot.CellData in
                var adjacent = 0
                for dr in -1...1 {
                    for dc in -1...1 where !(dr == 0 && dc == 0) {
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, mineSet.contains(nr * cols + nc) {
                            adjacent += 1
                        }
                    }
                }
                let mark = markMap[r * cols + c] ?? .none
                return MinesweeperSnapshot.CellData(
                    isRevealed: revealedSet.contains(r * cols + c),
                    isFlagged: mark == .flag,
                    isMine: mineSet.contains(r * cols + c),
                    adjacentMines: adjacent,
                    isContinuedMine: false,
                    mark: mark
                )
            }
        }

        let snapshot = MinesweeperSnapshot(
            rows: rows,
            cols: cols,
            totalMines: mines.count,
            cells: cells,
            flagCount: markMap.values.filter { $0 == .flag }.count,
            revealedCount: revealedSet.count,
            elapsedSeconds: 0
        )
        try? store.save(snapshot, for: "minesweeper")
        return MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))
    }

    // MARK: - 受け入れ条件: なし → 旗 → ? → なし で循環する

    @Test("マークは なし → 旗 → ? → なし の3状態で循環する")
    func markCyclesThroughThreeStates() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        #expect(model.cells[0][0].mark == .none, "初期状態はマーク無し")

        model.toggleFlag(row: 0, col: 0)
        #expect(model.cells[0][0].mark == .flag)
        #expect(model.cells[0][0].isFlagged)

        model.toggleFlag(row: 0, col: 0)
        #expect(model.cells[0][0].mark == .question)
        #expect(!model.cells[0][0].isFlagged, "? は旗ではない")

        model.toggleFlag(row: 0, col: 0)
        #expect(model.cells[0][0].mark == .none, "3回目で元に戻る")
    }

    // MARK: - 受け入れ条件: ? は残り地雷カウンタに数えない

    @Test("? は残り地雷カウンタに数えない")
    func questionMarkIsNotCountedAsFlag() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        #expect(model.remainingMines == 10)

        model.toggleFlag(row: 0, col: 0)              // → 旗
        #expect(model.flagCount == 1)
        #expect(model.remainingMines == 9, "旗はカウンタを減らす")

        model.toggleFlag(row: 0, col: 0)              // → ?
        #expect(model.flagCount == 0)
        #expect(model.remainingMines == 10, "? に変えたらカウンタは戻る")

        model.toggleFlag(row: 0, col: 0)              // → なし
        #expect(model.flagCount == 0, "? から外しても二重に減らさない")
        #expect(model.remainingMines == 10)
    }

    @Test("複数のマスに ? を置いてもカウンタは動かない")
    func manyQuestionMarksLeaveCounterAlone() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        for c in 0..<5 {
            model.toggleFlag(row: 0, col: c)   // 旗
            model.toggleFlag(row: 0, col: c)   // ?
        }
        #expect(model.flagCount == 0)
        #expect(model.remainingMines == 10)
    }

    // MARK: - 受け入れ条件: ? はコード（#437）の旗数にも数えない

    /// 5×5。行3 が地雷の壁になっていて連鎖が行4 まで届かない盤（`MinesweeperChordTests` と同じ形）。
    ///
    /// ```text
    ///   0 1 2 3 4
    /// 0 X . . . .      X = 地雷（(0,0) と行3 の5マス）
    /// 1 . 1 . . .      (1,1) は adjacentMines == 1（(0,0) だけ）
    /// 2 . . . . .
    /// 3 X X X X X
    /// 4 . . . . .
    /// ```
    ///
    /// **連鎖しても全開にならない**ので、途中で勝ってしまってテストの主旨がぼやけない。
    private static let wallMines: [(row: Int, col: Int)] =
        [(0, 0), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4)]

    private static func makeWallBoard(
        revealed: [(row: Int, col: Int)] = [(1, 1)],
        marks: [(row: Int, col: Int, mark: MinesweeperMark)]
    ) -> MinesweeperModel {
        makeModel(rows: 5, cols: 5, mines: wallMines, revealed: revealed, marks: marks)
    }

    /// (0,0) に **? を置いてもコードは成立しない**（旗が0本だから）。
    @Test("? はコードの旗数に数えないので、? だけではコードが成立しない")
    func questionMarkDoesNotEnableChord() {
        let model = Self.makeWallBoard(marks: [(0, 0, .question)])
        #expect(model.cells[1][1].adjacentMines == 1, "前提: (1,1) の数字は1")
        #expect(!model.canChord(row: 1, col: 1), "? は旗ではないのでコードは成立しない")

        model.tap(row: 1, col: 1)
        #expect(model.revealedCount == 1, "盤面は一切変わらない")
        #expect(model.gameState == .playing)
    }

    /// 旗が数字ぶん揃っていれば、別のマスに ? があってもコードは成立する
    /// （? を「旗が多すぎる」と数えてしまう退行の検出）。
    @Test("旗が揃っていれば、余分な ? があってもコードは成立する")
    func chordIgnoresQuestionMarksWhenCounting() {
        let model = Self.makeWallBoard(marks: [(0, 0, .flag), (0, 1, .question)])
        #expect(model.canChord(row: 1, col: 1), "旗1本 = 数字1 で成立する")

        model.tap(row: 1, col: 1)

        #expect(model.gameState == .playing, "地雷は踏まない")
        #expect(model.cells[0][1].isRevealed, "? のマスもコードの標的として開く（本家と同じ）")
    }

    // MARK: - ? のマスは開ける（旗との違い）

    @Test("? のマスは開けるが、旗のマスは開けない")
    func questionMarkedCellsCanBeRevealed() {
        // (2,4) は ? / (2,3) は旗。どちらも地雷ではないが、開けるのは ? のほうだけ。
        let model = Self.makeWallBoard(marks: [(2, 4, .question), (2, 3, .flag)])
        #expect(model.canReveal(row: 2, col: 4), "? は保留のメモなので開ける")
        #expect(!model.canReveal(row: 2, col: 3), "旗のマスは誤爆防止で開けない")

        model.tap(row: 2, col: 4)
        #expect(model.cells[2][4].isRevealed)
        #expect(model.cells[2][4].mark == .question, "開いてもマークの値自体は残る（表示は数字が優先）")
        #expect(model.gameState == .playing, "前提: まだ勝負はついていない")

        model.tap(row: 2, col: 3)
        #expect(!model.cells[2][3].isRevealed, "旗のマスはタップしても開かない")
    }

    @Test("連鎖は ? のマスを通り抜けて開く（旗のマスは避ける）")
    func floodRevealPassesThroughQuestionMarks() {
        // (0,2) は 0 マスなので連鎖の起点になる。連鎖は (1,1) の ? を開き、(2,2) の旗は避ける。
        let model = Self.makeWallBoard(revealed: [], marks: [(1, 1, .question), (2, 2, .flag)])
        #expect(model.cells[0][2].adjacentMines == 0, "前提: (0,2) は連鎖の起点")

        model.tap(row: 0, col: 2)

        #expect(model.cells[1][1].isRevealed, "? のマスは連鎖で開く")
        #expect(!model.cells[2][2].isRevealed, "旗のマスは連鎖でも開かない")
    }

    // MARK: - 終局時の扱い

    @Test("勝利時に ? のままの地雷も旗に変わり、旗数が合う")
    func winningConvertsQuestionMarksToFlags() {
        // 3×3・地雷は (0,0) の1つだけ。(0,0) に ? を置いたまま残り8マスを開けば勝ち。
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0)],
            marks: [(0, 0, .question)]
        )
        #expect(model.flagCount == 0, "前提: ? は数えられていない")

        for r in 0..<3 {
            for c in 0..<3 where !(r == 0 && c == 0) {
                model.tap(row: r, col: c)
            }
        }

        #expect(model.gameState == .won)
        #expect(model.cells[0][0].mark == .flag, "残った地雷は旗で埋められる")
        #expect(model.flagCount == 1, "? を数えていなかったぶんだけ増える（二重計上しない）")
        #expect(model.remainingMines == 0)
    }

    @Test("? のマスで地雷を踏んでコンティニューすると、確定爆弾として旗1本ぶん数える")
    func continueAfterHittingQuestionMarkedMine() {
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0)],
            revealed: [(2, 2)],
            marks: [(0, 0, .question)]
        )
        let flagsBefore = model.flagCount
        #expect(flagsBefore == 0)

        model.tap(row: 0, col: 0)   // ? のマスは開けるので地雷を踏む
        #expect(model.gameState == .lost)

        model.continueAfterAd()
        model.pauseTimer()          // 計時 Task を残さない

        #expect(model.cells[0][0].isContinuedMine)
        #expect(model.cells[0][0].isFlagged, "確定爆弾は旗として扱う")
        #expect(model.flagCount == flagsBefore + 1, "? は数えていなかったので +1 で合う")
    }

    // MARK: - 受け入れ条件: 旧形式のスナップショットが読める

    @Test("? を知らない旧形式の中断データが読める（旗はそのまま復元される）")
    func loadsLegacySnapshotWithoutMarkField() {
        let store = MemorySnapshotStore()
        // `mark` フィールドを一切持たない、#444 以前の形式をそのまま注入する。
        let legacyCell: (Bool, Bool) -> [String: Any] = { revealed, flagged in
            [
                "isRevealed": revealed,
                "isFlagged": flagged,
                "isMine": false,
                "adjacentMines": 0,
                "isContinuedMine": false,
            ]
        }
        var cells: [[[String: Any]]] = (0..<3).map { _ in (0..<3).map { _ in legacyCell(false, false) } }
        cells[0][0] = legacyCell(false, true)    // 旗
        cells[1][1] = legacyCell(true, false)    // 開放済み

        store.inject([
            "rows": 3, "cols": 3, "totalMines": 1,
            "cells": cells,
            "flagCount": 1, "revealedCount": 1, "elapsedSeconds": 42,
        ], for: "minesweeper")

        let model = MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))

        #expect(model.rows == 3 && model.cols == 3)
        #expect(model.gameState == .playing, "旧形式でも復元してプレイ中になる")
        #expect(model.cells[0][0].mark == .flag, "旧形式の旗は `mark` へ移し替えられる")
        #expect(model.cells[0][0].isFlagged)
        #expect(model.cells[1][1].isRevealed)
        #expect(model.cells[2][2].mark == .none, "旗が無いマスはマーク無しになる")
        #expect(model.flagCount == 1)
        #expect(model.elapsedSeconds == 42)
    }

    @Test("旧プリセット（12×12・地雷25）で保存された中断データも壊れずに復元できる")
    func loadsSnapshotSavedWithOldDifficultyPreset() {
        let store = MemorySnapshotStore()
        let cell: [String: Any] = [
            "isRevealed": false, "isFlagged": false,
            "isMine": false, "adjacentMines": 0, "isContinuedMine": false,
        ]
        store.inject([
            "rows": 12, "cols": 12, "totalMines": 25,
            "cells": (0..<12).map { _ in (0..<12).map { _ in cell } },
            "flagCount": 0, "revealedCount": 0, "elapsedSeconds": 7,
        ], for: "minesweeper")

        let model = MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))

        // プリセットの値が変わっても、盤の寸法はスナップショット側の値で復元される（#444）。
        #expect(model.rows == 12 && model.cols == 12 && model.totalMines == 25)
        #expect(model.remainingMines == 25)
        #expect(model.safeCellCount == 12 * 12 - 25)
        #expect(model.gameState == .playing)
    }

    @Test("保存した中断データは旧形式の isFlagged も書き続ける（前方互換）")
    func persistsLegacyFlagFieldAlongsideMark() throws {
        let (services, store) = Self.makeServices()
        let model = MinesweeperModel(services: services, rows: 3, cols: 3, mines: 1)
        model.tap(row: 1, col: 1)       // 地雷を置いてプレイ中にする（ここで保存が走る）
        model.pauseTimer()
        model.toggleFlag(row: 0, col: 0)   // 旗
        model.toggleFlag(row: 0, col: 2)   // 旗
        model.toggleFlag(row: 0, col: 2)   // → ?

        let json = try #require(store.rawJSON(for: "minesweeper"))
        let cells = try #require(json["cells"] as? [[[String: Any]]])
        #expect(cells[0][0]["isFlagged"] as? Bool == true)
        #expect(cells[0][0]["mark"] as? String == "flag")
        #expect(cells[0][2]["isFlagged"] as? Bool == false, "? は旧形式では旗ではない")
        #expect(cells[0][2]["mark"] as? String == "question")

        // 書いたものが自分で読み直せること（往復）。
        let restored = MinesweeperModel(services: services)
        #expect(restored.cells[0][0].mark == .flag)
        #expect(restored.cells[0][2].mark == .question)
        #expect(restored.flagCount == 1, "? は数えない")
    }

    // MARK: - 確定爆弾マスは循環に入らない

    @Test("確定爆弾のマスはマークを切り替えられない")
    func continuedMineIsNotPartOfTheCycle() {
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0)],
            revealed: [(2, 2)]
        )
        model.tap(row: 0, col: 0)
        model.continueAfterAd()
        model.pauseTimer()
        #expect(model.cells[0][0].isContinuedMine)

        model.toggleFlag(row: 0, col: 0)

        #expect(model.cells[0][0].mark == .flag, "確定爆弾は旗のまま動かない")
        #expect(model.flagCount == 1)
    }
}

/// 難易度プリセット（#444）。業界慣行（Windows 標準）の**地雷密度**に寄せた。
@Suite("マインスイーパーの難易度プリセット（#444）")
@MainActor
struct MinesweeperDifficultyPresetTests {

    /// **`MinesweeperDifficulty` を直接見る**（新規対局シートと同じ出どころ）。
    /// テスト側に数値を写し取ると、View だけ戻したときに検出できない空振りになる。
    private static let presets = MinesweeperDifficulty.allCases

    @Test("新規対局シートの難易度は3種のまま")
    func thereAreThreePresets() {
        #expect(Self.presets.map(\.label) == ["初級", "中級", "上級"])
    }

    @Test("プリセットの地雷密度が Windows 標準と同じ水準にある")
    func presetDensitiesMatchIndustryStandard() {
        // Windows 標準: 初級 9×9/10 = 12.35% / 中級 16×16/40 = 15.63% / 上級 30×16/99 = 20.63%
        let expected = [0.1235, 0.1563, 0.2063]
        for (preset, want) in zip(Self.presets, expected) {
            let density = Double(preset.mines) / Double(preset.rows * preset.cols)
            #expect(abs(density - want) < 0.005,
                    "\(preset.label) の密度 \(density) が業界標準 \(want) から離れている")
        }
    }

    @Test("盤は正方形のまま（縦画面で1マスが潰れないための制約）")
    func presetsStaySquare() {
        for preset in Self.presets {
            #expect(preset.rows == preset.cols, "\(preset.label) が正方形でない")
        }
    }

    @Test("難易度が上がるほど盤が広く、密度も上がる")
    func presetsAreMonotonic() {
        let areas = Self.presets.map { $0.rows * $0.cols }
        let densities = Self.presets.map { Double($0.mines) / Double($0.rows * $0.cols) }
        #expect(areas == areas.sorted(), "盤の広さが単調増加していない")
        #expect(densities == densities.sorted(), "地雷密度が単調増加していない")
    }

    @Test("副題は盤サイズと地雷数をそのまま表示する（シートの表示と実際の盤が食い違わない）")
    func subtitleMatchesTheBoardItStarts() {
        #expect(Self.presets.map(\.subtitle)
                == ["9×9  10地雷", "16×16  40地雷", "20×20  82地雷"])
    }

    @Test("各プリセットで盤が作れて、地雷が指定数だけ置かれる")
    func eachPresetBuildsAPlayableBoard() {
        for preset in Self.presets {
            let model = MinesweeperModel(rows: preset.rows, cols: preset.cols, mines: preset.mines)
            model.tap(row: 0, col: 0)   // 最初のタップで地雷が配置される
            model.pauseTimer()

            let placed = model.cells.flatMap { $0 }.filter(\.isMine).count
            #expect(placed == preset.mines, "\(preset.label) の地雷数が \(placed) になっている")
            #expect(model.safeCellCount == preset.rows * preset.cols - preset.mines)
            #expect(!model.cells[0][0].isMine, "最初のタップは必ず安全（既存の保証）")
        }
    }

    @Test("プリセットの記録区分に日本語名が付く")
    func presetsHaveJapaneseRecordLabels() {
        for preset in Self.presets {
            let model = MinesweeperModel(rows: preset.rows, cols: preset.cols, mines: preset.mines)
            #expect(model.recordVariantLabel == preset.label)
        }
    }

    /// 旧プリセットは区分としては別物になったので、日本語名を共有させない（自己ベストが混ざらない）。
    @Test("旧プリセットは盤サイズで表示され、新しい難易度名と混ざらない")
    func oldPresetsFallBackToBoardSizeLabel() {
        let old = MinesweeperModel(rows: 12, cols: 12, mines: 25)
        #expect(old.recordVariantLabel == "12×12・地雷25")

        let oldAdvanced = MinesweeperModel(rows: 15, cols: 15, mines: 40)
        #expect(oldAdvanced.recordVariantLabel == "15×15・地雷40")
    }
}
