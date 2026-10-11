import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 純粋な推論 `MinesweeperHint`（#2024）。地雷の場所を渡す口が無いので、見えている数字だけで決まる。
@Suite("マインスイーパー ヒントの推論（#2024）")
struct MinesweeperHintDeductionTests {

    /// `#` 未開、`F` 旗、数字は開いている数字。
    private static func grid(_ lines: [String]) -> [[MinesweeperHint.Observation]] {
        lines.map { line in
            line.map { ch -> MinesweeperHint.Observation in
                switch ch {
                case "#": return .hidden
                case "F": return .flagged
                default: return .number(Int(String(ch))!)
                }
            }
        }
    }

    private static func points(_ pairs: [(Int, Int)]) -> [MinesweeperPoint] {
        pairs.map { MinesweeperPoint(row: $0.0, col: $0.1) }
    }

    @Test("0 の数字の周りは全部安全")
    func zeroMakesNeighborsSafe() {
        let safe = MinesweeperHint.safeCells(in: Self.grid(["0#", "##"]))
        #expect(safe == Self.points([(0, 1), (1, 0), (1, 1)]))
    }

    @Test("1-2-1 は包含関係で真ん中の未開だけが安全と決まる")
    func oneTwoOneByInclusion() {
        let safe = MinesweeperHint.safeCells(in: Self.grid(["121", "###"]))
        #expect(safe == Self.points([(1, 1)]))
    }

    @Test("数字 = 未開の数なら全部地雷。そのマスは安全と言わず、満たされた別の数字の残りが安全")
    func allMinesThenRestSafe() {
        // (0,0)=1 の未開は (0,1) だけ → 地雷。(1,0)=1 の未開 (0,1),(2,0),(2,1) は (0,1) で満たされ (2,0),(2,1) が安全。
        let safe = MinesweeperHint.safeCells(in: Self.grid(["1#", "1#", "##"]))
        #expect(safe == Self.points([(2, 0), (2, 1)]))
    }

    @Test("旗は推論に使わない（旗が正しいと信じて周りを安全と言わない）")
    func flagsAreNotTrusted() {
        #expect(MinesweeperHint.safeCells(in: Self.grid(["1#", "F#"])).isEmpty)
    }

    @Test("旗のマスは安全と決まっても答えにしない")
    func flaggedCellIsNeverTheAnswer() {
        let safe = MinesweeperHint.safeCells(in: Self.grid(["0F", "##"]))
        #expect(safe == Self.points([(1, 0), (1, 1)]))
    }

    @Test("理屈で決まらない局面は空")
    func undecidableIsEmpty() {
        #expect(MinesweeperHint.safeCells(in: Self.grid(["1#", "##"])).isEmpty)
    }

    @Test("乱数の盤を大量に回しても、地雷を指さない")
    @MainActor
    func neverPointsAtAMine() {
        var deducedAtLeastOnce = 0
        for game in 0..<80 {
            let model = MinesweeperModel(rows: 16, cols: 16, mines: 40)
            model.tap(row: 8, col: 8)
            var steps = 0
            while model.gameState == .playing, steps < 300 {
                steps += 1
                let safe = MinesweeperHint.safeCells(in: model.observations())
                guard let p = safe.first else { break }
                deducedAtLeastOnce += 1
                for q in safe {
                    #expect(!model.cells[q.row][q.col].isMine, "盤 \(game) で地雷 (\(q.row),\(q.col)) を安全と言った")
                }
                model.tap(row: p.row, col: p.col)
                #expect(model.gameState != .lost, "ヒントに従って地雷を踏んだ（盤 \(game)）")
            }
        }
        #expect(deducedAtLeastOnce > 0, "前提: 推論が一度も働かないテストでは何も確かめていない")
    }
}

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
        completion(true)
    }
}

/// モデルへの結線（#2024）。地雷の配置は乱数なので、中断データを自作して盤面を決め打ちする（`MinesweeperChordTests` と同じ手口）。
@Suite("マインスイーパー ヒント（#2024）")
@MainActor
struct MinesweeperHintTests {

    private struct Fixture {
        let model: MinesweeperModel
        let store: MemorySnapshotStore
        let services: GameServices
        let center: SpyGameCenterService
    }

    private static func makeFixture(
        rows: Int, cols: Int, mines: [(row: Int, col: Int)],
        revealed: [(row: Int, col: Int)] = [], flagged: [(row: Int, col: Int)] = [],
        hintsUsed: Int? = nil, elapsed: Int = 0
    ) -> Fixture {
        let mineSet = Set(mines.map { $0.row * cols + $0.col })
        let revealedSet = Set(revealed.map { $0.row * cols + $0.col })
        let flaggedSet = Set(flagged.map { $0.row * cols + $0.col })
        let cells = (0..<rows).map { r in
            (0..<cols).map { c -> MinesweeperSnapshot.CellData in
                var adjacent = 0
                for dr in -1...1 {
                    for dc in -1...1 where !(dr == 0 && dc == 0) {
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, mineSet.contains(nr * cols + nc) { adjacent += 1 }
                    }
                }
                return MinesweeperSnapshot.CellData(
                    isRevealed: revealedSet.contains(r * cols + c), isFlagged: flaggedSet.contains(r * cols + c),
                    isMine: mineSet.contains(r * cols + c), adjacentMines: adjacent, isContinuedMine: false
                )
            }
        }
        let snapshot = MinesweeperSnapshot(
            rows: rows, cols: cols, totalMines: mines.count, cells: cells,
            flagCount: flaggedSet.count, revealedCount: revealedSet.count, elapsedSeconds: elapsed,
            hintsUsed: hintsUsed
        )
        let store = MemorySnapshotStore()
        try? store.save(snapshot, for: "minesweeper")
        let name = "asobiba.minesweeper.hint.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let center = SpyGameCenterService()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults),
            gameCenter: GameCenterReporter(service: center, allowedGameIDs: ["minesweeper"], isAvailable: { true })
        )
        return Fixture(model: MinesweeperModel(services: services), store: store, services: services, center: center)
    }

    /// 4×4。地雷は (0,0) だけ。(0,0)(0,1)(1,0) 以外は開いている。
    /// (0,2) と (2,0) が 0 なので、(0,1) と (1,0) は理屈で安全と決まる。(1,1)=1 は 3 マスのどれか 1 個で決まらない。
    private static func deducibleBoard(flagged: [(row: Int, col: Int)] = []) -> Fixture {
        let hidden = Set([0, 1, 4])
        let revealed = (0..<16).filter { !hidden.contains($0) }.map { (row: $0 / 4, col: $0 % 4) }
        return makeFixture(rows: 4, cols: 4, mines: [(0, 0)], revealed: revealed, flagged: flagged)
    }

    /// 5×5。地雷は (0,0) と行3 の壁。(1,1)=1 だけ開いていて、理屈で決まるマスが無い（運任せ）。
    private static func guessBoard(hintsUsed: Int? = nil) -> Fixture {
        makeFixture(
            rows: 5, cols: 5, mines: [(0, 0), (3, 0), (3, 1), (3, 2), (3, 3), (3, 4)],
            revealed: [(1, 1)], hintsUsed: hintsUsed
        )
    }

    @Test("理屈で安全なマスを紫の枠で示す。開けるのはプレイヤーで、盤は変わらない")
    func highlightsADeducedSafeCell() throws {
        let f = Self.deducibleBoard()
        let revealedBefore = f.model.revealedCount
        let outcome = try #require(f.model.useHint())

        #expect(outcome == .highlighted(MinesweeperPoint(row: 0, col: 1)))
        #expect(f.model.hintPoint == MinesweeperPoint(row: 0, col: 1))
        #expect(!f.model.cells[0][1].isMine, "地雷を指している")
        #expect(f.model.revealedCount == revealedBefore, "示すだけで開けない")
        #expect(f.model.hints.used == 1)
    }

    @Test("旗の立っているマスは候補から外し、次の安全なマスを示す")
    func skipsFlaggedCells() throws {
        let f = Self.deducibleBoard(flagged: [(0, 1)])
        let outcome = try #require(f.model.useHint())
        #expect(outcome == .highlighted(MinesweeperPoint(row: 1, col: 0)))
    }

    @Test("開くと印は消える")
    func hintMarkClearsOnceOpened() throws {
        let f = Self.deducibleBoard()
        _ = f.model.useHint()
        let p = try #require(f.model.hintPoint)
        f.model.tap(row: p.row, col: p.col)
        #expect(f.model.hintPoint == nil)
    }

    @Test("運任せの局面では、開いているマスに接する安全なマスをその場で開ける")
    func revealsASafeCellWhenNothingIsDeducible() throws {
        let f = Self.guessBoard()
        let revealedBefore = f.model.revealedCount
        let outcome = try #require(f.model.useHint())

        guard case .revealed(let p) = outcome else {
            Issue.record("運任せの局面で示すだけになった: \(outcome)")
            return
        }
        #expect(!f.model.cells[p.row][p.col].isMine, "地雷を開けた")
        #expect(f.model.cells[p.row][p.col].isRevealed)
        #expect(f.model.revealedCount > revealedBefore)
        #expect(f.model.gameState == .playing)
        #expect(f.model.hintPoint == nil)
        #expect(f.model.hints.used == 1)
    }

    @Test("最初の 1 手の前は使えない")
    func unavailableBeforeFirstMove() {
        let model = MinesweeperModel()
        #expect(!model.canUseHint)
        #expect(model.useHint() == nil)
        #expect(model.hints.used == 0)
    }

    @Test("決着後は使えない")
    func unavailableAfterGameOver() {
        let f = Self.guessBoard()
        f.model.giveUp()
        #expect(!f.model.canUseHint)
        #expect(f.model.useHint() == nil)
    }

    @Test("無料 1 回 → 広告で +1 を最大 3 回 → 使い切り")
    func freeThenAdsThenExhausted() {
        let f = Self.guessBoard()
        let model = f.model
        let game = model.gameSerial
        #expect(model.hints.freeRemaining == 1)
        #expect(!model.needsAdForHint)
        #expect(!model.useAdHint(forGame: game), "無料が残っているうちは広告の経路で消費しない")

        #expect(model.useHint() != nil)
        #expect(model.needsAdForHint, "無料を使い切ったら次は広告")
        #expect(model.useHint() == nil, "広告無しでは出ない")
        #expect(model.hints.used == 1)

        for n in 1...3 {
            #expect(model.useAdHint(forGame: game), "広告 \(n) 本目")
        }
        #expect(model.hints.isExhausted)
        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)
        #expect(!model.needsAdForHint)
        #expect(!model.useAdHint(forGame: game), "4 本目は出ない")
        #expect(model.hints.used == 4)
    }

    @Test("広告を見ている間に局が替わっていたら適用しない")
    func staleGameSerialIsRejected() {
        let f = Self.guessBoard()
        _ = f.model.useHint()
        let used = f.model.hints.used
        #expect(!f.model.useAdHint(forGame: f.model.gameSerial - 1))
        #expect(f.model.hints.used == used)
    }

    @Test("使った回数は中断データに残り、再開で戻らない")
    func usedCountSurvivesRestart() {
        let f = Self.guessBoard()
        _ = f.model.useHint()
        f.model.pauseTimer()

        let restored = MinesweeperModel(services: f.services)
        #expect(restored.hints.used == 1)
        #expect(restored.needsAdForHint)
    }

    @Test("鍵の無い旧形式の中断データは 0 回として読む")
    func legacySnapshotReadsAsUnused() throws {
        let f = Self.guessBoard()
        let data = try #require(f.store.rawData(for: "minesweeper"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("hintsUsed"), "前提: 旧形式と同じく鍵が無い")
        #expect(f.model.hints.used == 0)
        #expect(f.model.hintsRemaining == 4)
    }

    @Test("範囲外の使用回数は丸める")
    func outOfRangeUsedCountIsClamped() {
        #expect(Self.guessBoard(hintsUsed: 99).model.hints.used == 4)
        #expect(Self.guessBoard(hintsUsed: -3).model.hints.used == 0)
    }

    @Test("新規ゲームで回数が戻る")
    func newGameResetsHints() {
        let f = Self.guessBoard()
        _ = f.model.useHint()
        f.model.newGame(rows: 9, cols: 9, mines: 10)
        #expect(f.model.hints.used == 0)
        #expect(f.model.hintPoint == nil)
    }

    @Test("ヒントを使った局のクリアは順位表に送らない（使わなければ送る）")
    func usedHintIsNotSubmittedToLeaderboard() {
        // 初級プリセット（9×9・地雷10）。地雷は行0 の9マスと (1,0)。(8,8) を開けば連鎖でクリアになる。
        let mines: [(row: Int, col: Int)] = (0..<9).map { (0, $0) } + [(1, 0)]
        let control = Self.makeFixture(rows: 9, cols: 9, mines: mines, elapsed: 30)
        control.model.tap(row: 8, col: 8)
        #expect(control.model.gameState == .won)
        #expect(control.center.scores.count == 1, "前提: 使わなければ送られる")

        let used = Self.makeFixture(rows: 9, cols: 9, mines: mines, elapsed: 30)
        #expect(used.model.useHint() != nil)
        used.model.tap(row: 8, col: 8)
        #expect(used.model.gameState == .won)
        #expect(used.center.scores.isEmpty, "ヒントを使った局のタイムを順位表に混ぜない")
        #expect(used.model.recordResult != nil, "リザルトの自己ベスト表示は従来どおり出る")
    }
}

/// ヒントの使用回数が `game_end` の `hints_used` に載る結線。
@Suite("マインスイーパー ヒントの解析（#2024）")
@MainActor
struct MinesweeperHintAnalyticsTests {

    @Test("ヒントを使った局の game_end に hints_used が載る")
    func finishCarriesHintsUsed() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["minesweeper"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 4, col: 4)
        #expect(model.gameState == .playing, "前提: 初手は安全で局は続いている")
        _ = model.useHint()

        model.giveUp()

        let ends = spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
        #expect(ends.count == 1)
        #expect(ends.first?["hints_used"] == .int(1))
    }
}
