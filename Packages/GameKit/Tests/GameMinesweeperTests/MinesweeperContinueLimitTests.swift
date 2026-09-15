import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
        completion(true)
    }
}

/// 広告コンティニューの上限と順位表の扱い（#657）。
///
/// 地雷の配置は乱数なので、中断スナップショットを自作して盤面を決め打ちする（`MinesweeperChordTests` と同じ手口）。
/// 盤は**初級プリセット（9×9・地雷10）**にする。プリセット以外の盤は区分の時点で順位表の対象外になり、
/// 「コンティニューしたから送らない」のか「盤が対象外だから送らない」のかを区別できないため。
@Suite("マインスイーパーのコンティニュー上限（#657）")
@MainActor
struct MinesweeperContinueLimitTests {

    /// 地雷は行0 の9マスと (1,0)。(8,8) を1回開けば連鎖で安全マス71個がすべて開いてクリアになる。
    ///
    /// 経過秒を 0 より大きくしておくのは、0 秒のクリアを順位表が捨てる仕様（`GameCenterLeaderboard.score`）
    /// のせいで、対照側でも送信が起きなくなるのを避けるため。
    private static let mines: [(row: Int, col: Int)] = (0..<9).map { (0, $0) } + [(1, 0)]
    private static let elapsed = 30

    private struct Fixture {
        let model: MinesweeperModel
        let store: MemorySnapshotStore
        let spy: SpyGameCenterService
        let log: PlayLog
        let services: GameServices
    }

    /// - Parameter continuedMineAt: 指定すると、そのマスを「コンティニューで確定した爆弾」（旗 + `isContinuedMine`）
    ///   にした盤を作る。`continueUsed` の鍵は書かないので、v1.1.4 で使った局の旧形式の中断データになる（#816）。
    private static func makeFixture(suite: String, continuedMineAt continued: (row: Int, col: Int)? = nil) -> Fixture {
        let rows = 9, cols = 9
        let mineSet = Set(mines.map { $0.row * cols + $0.col })
        let isContinued = { (r: Int, c: Int) in continued.map { $0.row == r && $0.col == c } ?? false }
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
                    isRevealed: false,
                    isFlagged: isContinued(r, c),
                    isMine: mineSet.contains(r * cols + c),
                    adjacentMines: adjacent,
                    isContinuedMine: isContinued(r, c)
                )
            }
        }
        let snapshot = MinesweeperSnapshot(
            rows: rows, cols: cols, totalMines: mines.count, cells: cells,
            flagCount: continued == nil ? 0 : 1, revealedCount: 0, elapsedSeconds: elapsed
        )
        let store = MemorySnapshotStore()
        try? store.save(snapshot, for: "minesweeper")

        let name = "asobiba.minesweeper.continue.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let spy = SpyGameCenterService()
        let services = GameServices(
            snapshots: store,
            ads: NoopAdService(),
            playLog: log,
            gameCenter: GameCenterReporter(service: spy, allowedGameIDs: ["minesweeper"], isAvailable: { true })
        )
        return Fixture(model: MinesweeperModel(services: services), store: store, spy: spy, log: log, services: services)
    }

    // MARK: - 受け入れ条件1: 局内の回数に上限がある

    @Test("コンティニューは1局1回。2回目の地雷では提案できず、呼んでも盤面は変わらない")
    func continueOnlyOncePerGame() {
        let f = Self.makeFixture(suite: "once")
        #expect(!f.model.continueUsed, "前提: 未使用で始まる")

        f.model.tap(row: 0, col: 0)
        #expect(f.model.canContinue, "1回目の地雷ではコンティニューを提案できる")
        f.model.continueAfterAd()
        #expect(f.model.gameState == .playing)
        #expect(f.model.continueUsed)

        f.model.tap(row: 0, col: 1)
        #expect(f.model.gameState == .lost, "前提: 2つ目の地雷を踏んでいる")
        #expect(!f.model.canContinue, "使用済みの局では提案しない")

        let flagsBefore = f.model.flagCount
        f.model.continueAfterAd()
        #expect(f.model.gameState == .lost, "2回目のコンティニューで続きに戻ってはいけない")
        #expect(f.model.hitMine?.row == 0 && f.model.hitMine?.col == 1)
        #expect(!f.model.cells[0][1].isContinuedMine)
        #expect(f.model.flagCount == flagsBefore)
    }

    @Test("諦めた局ではコンティニューを提案しない")
    func noContinueAfterGiveUp() {
        let f = Self.makeFixture(suite: "giveup")
        f.model.giveUp()
        #expect(f.model.gameState == .lost)
        #expect(!f.model.canContinue)
    }

    @Test("新規ゲームで使用済みがリセットされる")
    func newGameResetsContinue() {
        let f = Self.makeFixture(suite: "reset")
        f.model.tap(row: 0, col: 0)
        f.model.continueAfterAd()
        f.model.pauseTimer()
        #expect(f.model.continueUsed)

        f.model.newGame(rows: 9, cols: 9, mines: 10)
        #expect(!f.model.continueUsed)
    }

    // MARK: - 受け入れ条件2: 中断データに保存され、再起動で復活しない

    @Test("再起動してもコンティニュー権は復活しない（中断データに使用済みを持つ）")
    func continueUsedSurvivesRestart() {
        let f = Self.makeFixture(suite: "restart")
        f.model.tap(row: 0, col: 0)
        f.model.continueAfterAd()
        f.model.pauseTimer()

        let restored = MinesweeperModel(services: f.services)
        #expect(restored.continueUsed, "使用済みフラグが復元される")

        restored.tap(row: 0, col: 1)
        #expect(restored.gameState == .lost)
        #expect(!restored.canContinue, "再起動をはさんでも2回目は提案しない")
    }

    @Test("使用済みの鍵を持たない旧形式の中断データも読め、未使用として扱う")
    func legacySnapshotReadsAsUnused() throws {
        let f = Self.makeFixture(suite: "legacy")
        let data = try #require(f.store.rawData(for: "minesweeper"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("continueUsed"), "前提: 旧形式と同じく鍵が無い中断データ")

        #expect(f.model.gameState == .playing, "キーが増えても既存の中断データを失わせない")
        #expect(!f.model.continueUsed, "欠けていたら『まだ使っていない』として読む")
    }

    @Test("鍵の無い旧形式でも、確定爆弾のマスが残っていれば使用済みとして読み、2回目を提案しない（#816）")
    func legacySnapshotWithContinuedMineReadsAsUsed() throws {
        let f = Self.makeFixture(suite: "legacy-continued", continuedMineAt: (0, 0))
        let data = try #require(f.store.rawData(for: "minesweeper"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("continueUsed"), "前提: v1.1.4 と同じく鍵が無い中断データ")
        #expect(f.model.cells[0][0].isContinuedMine, "前提: 確定爆弾のマスが復元されている")

        #expect(f.model.continueUsed, "盤に残った確定爆弾はコンティニューを使った証拠")
        f.model.tap(row: 0, col: 1)
        #expect(f.model.gameState == .lost, "前提: 2つ目の地雷を踏んでいる")
        #expect(!f.model.canContinue, "旧形式の中断データをはさんでも2回目は提案しない")
    }

    @Test("鍵の無い旧形式で確定爆弾のマスが残っている局のクリアは順位表に送らない（#816）")
    func legacySnapshotWithContinuedMineIsNotSubmitted() {
        let f = Self.makeFixture(suite: "legacy-continued-clear", continuedMineAt: (0, 0))
        f.model.tap(row: 8, col: 8)

        #expect(f.model.gameState == .won, "前提: 復元した局をクリアしている")
        #expect(f.spy.scores.isEmpty, "v1.1.4 でコンティニューした局のタイムを順位表に混ぜない")
        #expect(f.log.record(gameID: "minesweeper", variant: "9x9-10")?.bestSeconds == Self.elapsed,
                "自己ベストは使用有無を問わず残す")
    }

    // MARK: - 受け入れ条件3: コンティニューした局は順位表に送らない（自己ベストは残す）

    @Test("コンティニューせずにクリアした局のタイムは順位表へ送られる（対照）")
    func clearWithoutContinueIsSubmitted() {
        let f = Self.makeFixture(suite: "control")
        f.model.tap(row: 8, col: 8)

        #expect(f.model.gameState == .won)
        #expect(f.spy.scores == [
            GameCenterScore(leaderboardID: GameCenterLeaderboard.minesweeperBeginner, value: Self.elapsed),
        ])
    }

    @Test("コンティニューを使ってクリアした局は順位表に送らず、自己ベストには記録する")
    func clearAfterContinueIsNotSubmitted() {
        let f = Self.makeFixture(suite: "continued")
        f.model.tap(row: 0, col: 0)
        f.model.continueAfterAd()
        f.model.tap(row: 8, col: 8)

        #expect(f.model.gameState == .won, "前提: コンティニュー後にクリアしている")
        #expect(f.spy.scores.isEmpty, "広告コンティニューを使った局のタイムを順位表に混ぜない")
        #expect(f.log.record(gameID: "minesweeper", variant: "9x9-10")?.bestSeconds == Self.elapsed,
                "自己ベストは使用有無を問わず残す")
        #expect(f.model.recordResult != nil, "リザルトの自己ベスト表示も従来どおり出る")
    }
}
