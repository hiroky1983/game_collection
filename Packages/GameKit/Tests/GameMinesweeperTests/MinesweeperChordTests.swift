import Testing
import Foundation
import Core
@testable import GameMinesweeper

/// テスト専用の中断データ置き場（ファイルに書かず、プロセス内だけで完結させる）。
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
}

/// コード = 開いている数字マスのタップで周囲を一括開放する操作（#437）。
///
/// 地雷の配置は `placeMines` が乱数で決めるため、通常の `newGame` + `tap` では
/// 「旗が正しい／誤っている」を作り分けられない。**中断スナップショットを自作して注入**し、
/// 盤面を完全に決め打ちしたうえで検証する（麻雀・2048 の既存テストと同じ手口）。
@Suite("マインスイーパーのコード（#437）")
@MainActor
struct MinesweeperChordTests {

    // MARK: - 盤面の組み立て

    /// 地雷の配置から `adjacentMines` を計算し、開放・旗の状態を指定した盤を作る。
    private static func makeModel(
        rows: Int,
        cols: Int,
        mines: [(row: Int, col: Int)],
        revealed: [(row: Int, col: Int)] = [],
        flagged: [(row: Int, col: Int)] = []
    ) -> MinesweeperModel {
        let index: ((row: Int, col: Int)) -> Int = { $0.row * cols + $0.col }
        let mineSet     = Set(mines.map(index))
        let revealedSet = Set(revealed.map(index))
        let flaggedSet  = Set(flagged.map(index))

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
                return MinesweeperSnapshot.CellData(
                    isRevealed: revealedSet.contains(r * cols + c),
                    isFlagged: flaggedSet.contains(r * cols + c),
                    isMine: mineSet.contains(r * cols + c),
                    adjacentMines: adjacent,
                    isContinuedMine: false
                )
            }
        }

        let snapshot = MinesweeperSnapshot(
            rows: rows,
            cols: cols,
            totalMines: mines.count,
            cells: cells,
            flagCount: flaggedSet.count,
            revealedCount: revealedSet.count,
            elapsedSeconds: 0
        )
        let store = MemorySnapshotStore()
        try? store.save(snapshot, for: "minesweeper")
        return MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))
    }

    /// 5×5。行3 が地雷の壁になっていて、連鎖が行4 まで届かない盤。
    ///
    /// ```text
    ///   0 1 2 3 4
    /// 0 X . . . .      X = 地雷（(0,0) と行3 の5マス）
    /// 1 . 1 . . .      (1,1) は adjacentMines == 1（(0,0) だけ）
    /// 2 . . . . .
    /// 3 X X X X X
    /// 4 . . . . .
    /// ```
    private static let wallMines: [(row: Int, col: Int)] =
        [(0, 0), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4)]

    private static func makeWallBoard(flagged: [(row: Int, col: Int)]) -> MinesweeperModel {
        makeModel(rows: 5, cols: 5, mines: wallMines, revealed: [(1, 1)], flagged: flagged)
    }

    // MARK: - 受け入れ条件1: 旗数一致で一括開放

    @Test("旗の数が数字と一致していれば、周囲の未開放マスが一括で開く")
    func chordOpensNeighborsWhenFlagsMatch() {
        let model = Self.makeWallBoard(flagged: [(0, 0)])
        #expect(model.cells[1][1].adjacentMines == 1, "前提: (1,1) の数字は1")
        #expect(model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        // (1,1) の周囲8マスのうち、地雷でも旗でもない7マスは必ず開く。
        for (r, c) in [(0, 1), (0, 2), (1, 0), (1, 2), (2, 0), (2, 1), (2, 2)] {
            #expect(model.cells[r][c].isRevealed, "(\(r),\(c)) が開いていない")
        }
        #expect(!model.cells[0][0].isRevealed, "旗を立てた地雷は開かない")
        #expect(model.gameState == .playing, "まだ安全マスが残っているので続行する")
    }

    /// 受け入れ条件4。コードで開いた (0,2) / (1,2) は `adjacentMines == 0` なので、
    /// そこから既存の BFS が右半分へ波及する。地雷の壁の向こう（行4）へは届かない。
    @Test("コードで開いた 0 マスからゼロ連鎖が波及する")
    func chordTriggersZeroCascade() {
        let model = Self.makeWallBoard(flagged: [(0, 0)])
        #expect(model.cells[0][2].adjacentMines == 0, "前提: (0,2) は 0 マス（連鎖の起点）")

        model.tap(row: 1, col: 1)

        // 連鎖はコードの標的でない行0〜2 の右側まで届く。
        for (r, c) in [(0, 3), (0, 4), (1, 3), (1, 4), (2, 3), (2, 4)] {
            #expect(model.cells[r][c].isRevealed, "連鎖が (\(r),\(c)) まで届いていない")
        }
        // 地雷の壁の向こうは開かない（連鎖が壁を越えていないことの裏取り）。
        for c in 0..<5 {
            #expect(!model.cells[4][c].isRevealed, "(4,\(c)) が開いている（壁を越えている）")
        }
        #expect(model.revealedCount == 14, "行0〜2 の安全マス14個だけが開く")
    }

    @Test("盤の最後の安全マスをコードで開けば勝ちになる")
    func chordCanWinTheGame() {
        // 3×3・地雷は対角の2つ。中央 (1,1) をコードすると残り6マスが一度に開いて全開になる。
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0), (2, 2)],
            revealed: [(1, 1)],
            flagged: [(0, 0), (2, 2)]
        )
        #expect(model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        #expect(model.gameState == .won)
        #expect(model.revealedCount == model.safeCellCount)
    }

    // MARK: - 受け入れ条件2: 旗数が一致しないときは盤面が変化しない

    @Test("旗が足りないときは何も起こらない")
    func chordDoesNothingWhenFlagsAreMissing() {
        let model = Self.makeWallBoard(flagged: [])
        #expect(!model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        #expect(model.revealedCount == 1, "開いているのは元の (1,1) だけ")
        #expect(model.gameState == .playing)
        for r in 0..<5 {
            for c in 0..<5 where !(r == 1 && c == 1) {
                #expect(!model.cells[r][c].isRevealed, "(\(r),\(c)) が開いている")
            }
        }
    }

    @Test("旗が多すぎるときも何も起こらない")
    func chordDoesNothingWhenFlagsAreTooMany() {
        // (0,0) は地雷だが (0,1) は違う。旗2本に対して数字は1なので不一致。
        let model = Self.makeWallBoard(flagged: [(0, 0), (0, 1)])
        #expect(!model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        #expect(model.revealedCount == 1)
        #expect(model.gameState == .playing)
    }

    @Test("開く先が残っていない数字マスではコードが成立しない")
    func chordNeedsSomethingToOpen() {
        // 3×3 の中央を、周囲がすべて開き済み or 旗の状態にする。
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0), (2, 2)],
            revealed: [(1, 1), (0, 1), (0, 2), (1, 0), (1, 2), (2, 0), (2, 1)],
            flagged: [(0, 0), (2, 2)]
        )
        #expect(!model.canChord(row: 1, col: 1), "開く先が無い操作は案内しない（#188）")
    }

    @Test("未開放マス・0 マスではコードが成立しない")
    func chordOnlyAppliesToRevealedNumberCells() {
        let model = Self.makeWallBoard(flagged: [(0, 0)])
        #expect(!model.canChord(row: 2, col: 2), "未開放のマスは対象外")

        model.tap(row: 1, col: 1)   // 連鎖で 0 マスが開く
        #expect(model.cells[0][2].isRevealed && model.cells[0][2].adjacentMines == 0)
        #expect(!model.canChord(row: 0, col: 2), "0 マスは周囲に開くものが無いので対象外")
    }

    // MARK: - 受け入れ条件3: 誤った旗でコードすると地雷を踏む

    @Test("誤った旗でコードすると地雷を踏んで負ける")
    func chordOnWrongFlagHitsMine() {
        // (0,1) は地雷ではないのに旗を立てている。数は合うのでコードは成立し、
        // 標的に含まれる本物の地雷 (0,0) を踏む（本家と同じ挙動・安全化しない）。
        let model = Self.makeWallBoard(flagged: [(0, 1)])
        #expect(model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        #expect(model.gameState == .lost)
        #expect(model.hitMine?.row == 0 && model.hitMine?.col == 0)
        #expect(model.cells[0][0].isRevealed, "踏んだ地雷は露出する")
        for mine in Self.wallMines where !(mine.row == 0 && mine.col == 0) {
            #expect(model.cells[mine.row][mine.col].isRevealed, "他の地雷も一斉に公開される")
        }
    }

    @Test("標的に地雷が複数あっても終局処理は1回で、全部が公開される")
    func chordWithSeveralMinesInTargets() {
        // 上辺の2つが地雷なのに、下辺の2マスへ旗を立てている。数は合うのでコードは成立し、
        // 標的 (0,0) と (0,2) の**両方**が地雷になる。
        let model = Self.makeModel(
            rows: 3, cols: 3,
            mines: [(0, 0), (0, 2)],
            revealed: [(1, 1)],
            flagged: [(2, 0), (2, 2)]
        )
        #expect(model.cells[1][1].adjacentMines == 2, "前提: (1,1) の数字は2")
        #expect(model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)

        #expect(model.gameState == .lost)
        #expect(model.hitMine?.row == 0 && model.hitMine?.col == 0, "走査順で最初の地雷を踏んだ扱いにする")
        #expect(model.cells[0][0].isRevealed)
        #expect(model.cells[0][2].isRevealed, "踏まなかったほうの地雷も一斉公開される")
    }

    @Test("コードで負けたあともコンティニュー導線が正常に動く")
    func continueWorksAfterChordLoss() {
        let model = Self.makeWallBoard(flagged: [(0, 1)])
        model.tap(row: 1, col: 1)
        #expect(model.gameState == .lost, "前提: コードで負けている")
        let flagsBefore = model.flagCount

        model.continueAfterAd()

        #expect(model.gameState == .playing)
        #expect(model.hitMine == nil)
        #expect(model.cells[0][0].isContinuedMine, "踏んだ地雷は確定爆弾として残る")
        #expect(model.cells[0][0].isFlagged)
        #expect(!model.cells[0][0].isRevealed, "露出した地雷は隠し直される")
        #expect(model.flagCount == flagsBefore + 1)
        #expect(model.isTimerRunning, "計時が再開する")

        model.pauseTimer()   // テストが計時 Task を残さないようにする
    }

    @Test("コードで負けた盤は確定爆弾を旗として数え、続きのコードに使える")
    func continuedMineCountsAsFlag() {
        let model = Self.makeWallBoard(flagged: [(0, 1)])
        model.tap(row: 1, col: 1)
        model.continueAfterAd()
        model.pauseTimer()

        // (0,0) は確定爆弾（= 旗扱い）、(0,1) の誤旗はそのまま残っている。
        // (1,1) の数字1 に対し旗が2本になるので、コードは成立しない。
        #expect(!model.canChord(row: 1, col: 1))

        model.toggleFlag(row: 0, col: 1)   // 誤旗を下ろすと数が合う
        #expect(model.canChord(row: 1, col: 1))

        model.tap(row: 1, col: 1)
        #expect(model.gameState == .playing, "今度は正しい旗なので踏まない")
        #expect(model.cells[0][1].isRevealed)
    }

    // MARK: - 既存の操作を壊していないこと

    @Test("終局後のコードは何も起こさない")
    func chordIsInertAfterGameOver() {
        let model = Self.makeWallBoard(flagged: [(0, 0)])
        model.giveUp()
        let revealedBefore = model.revealedCount

        model.tap(row: 1, col: 1)

        #expect(model.gameState == .lost)
        #expect(model.revealedCount == revealedBefore)
        #expect(!model.canChord(row: 1, col: 1))
    }

    @Test("未開放マスのタップは従来どおり1マスだけ開く")
    func tappingUnrevealedCellStillRevealsOne() {
        let model = Self.makeWallBoard(flagged: [(0, 0)])

        model.tap(row: 2, col: 1)   // adjacentMines == 3 なので連鎖しない

        #expect(model.cells[2][1].isRevealed)
        #expect(model.revealedCount == 2, "(1,1) と (2,1) の2マスだけ")
    }
}
