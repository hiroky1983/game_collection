import Testing
import Foundation
import Core
@testable import Game2048

/// 再起動をまたぐ挙動を、ファイルを触らずに再現するための中断データ置き場。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 送信されたイベントをそのまま溜めるスパイ。Firebase もネットワークも使わない。
@MainActor
private final class SpyAnalyticsService: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []
    func log(_ event: AnalyticsEvent) { events.append(event) }

    var starts: Int {
        events.filter { if case .gameStart = $0 { return true } else { return false } }.count
    }
    var outcomes: [GameOutcome] {
        events.compactMap { if case let .gameEnd(_, outcome, _) = $0 { return outcome } else { return nil } }
    }
}

/// #438: 2048 到達時の勝利演出と、それに伴う `outcome: .win` の通知。
@Suite("2048 勝利演出（#438）")
@MainActor
struct Game2048WinTests {
    /// 左へ寄せると 1024 どうしが合体して 2048 になり、盤はまだ埋まらない。
    static let oneMoveFromWin = [
        [1024, 1024, 4, 8],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]

    /// 1 手で 2048 を 2 枚作れる盤。続行後にもう一度合体しても再発火しないことの検証に使う。
    static let twoWinningTilesInOneMove = [
        [1024, 1024, 1024, 1024],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
    ]

    /// 左へ寄せると 2048 ができ、**同時に**盤が埋まり切って終局する盤。
    /// 空くのは (0,3) だけで、そこに沸く 2 / 4 はどちらの隣（16 と 8）とも合体しない。
    static let winningMoveEndsTheGame = [
        [1024, 1024, 8, 16],
        [4, 16, 4, 8],
        [8, 4, 8, 4],
        [4, 8, 4, 8],
    ]

    private struct Harness {
        let services: GameServices
        let log: PlayLog
        let analytics: SpyAnalyticsService
    }

    private func makeHarness(suite: String) -> Harness {
        let name = "asobiba.2048win.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(),
            ads: NoopAdService(),
            review: ReviewRequestService(
                log: log,
                appVersion: "1.1.3",
                now: { Date(timeIntervalSince1970: 1_800_000_000) },
                delay: .zero
            ),
            playLog: log,
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["2048"])
        )
        return Harness(services: services, log: log, analytics: spy)
    }

    /// 盤を直接与える `init` は「新しいプレイ」を数えない経路なので、解析の対応を取るために
    /// ここで 1 プレイぶん数えておく（そうしないと `game_end` が送られず、通知を観測できない）。
    private func makeModel(_ harness: Harness, board: [[Int]], score: Int = 0) -> Game2048Model {
        let model = Game2048Model(services: harness.services, board: board, score: score)
        harness.services.gameDidStart(gameID: "2048")
        return model
    }

    // MARK: - 発火

    @Test("2048 初到達で勝利演出が出て、ゲームは終わらない")
    func reachingWinningTileShowsPrompt() {
        let model = Game2048Model(board: Self.oneMoveFromWin)
        #expect(!model.hasWon, "前提: まだ到達していない")

        model.move(.left)

        #expect(model.hasWon)
        #expect(model.showWinPrompt, "勝利演出が出る")
        #expect(!model.gameOver, "原典と同じく、勝っても盤は続く")
        #expect(model.board[0][0] == 2048)
    }

    @Test("2048 初到達で `outcome: .win` が通知される")
    func reachingWinningTileReportsWin() {
        let harness = makeHarness(suite: "reports-win")
        let model = makeModel(harness, board: Self.oneMoveFromWin)

        model.move(.left)

        #expect(harness.analytics.outcomes == [.win], "解析へ送る決着は勝ち 1 件だけ")
        #expect(harness.log.record(gameID: "2048")?.wins == 1)
    }

    @Test("2048 に届かない手では発火しない")
    func doesNotFireBeforeReachingWinningTile() {
        let harness = makeHarness(suite: "not-yet")
        let model = makeModel(harness, board: [
            [512, 512, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])

        model.move(.left)

        #expect(model.board[0][0] == 1024, "前提: 合体はしている")
        #expect(!model.hasWon)
        #expect(!model.showWinPrompt)
        #expect(harness.analytics.outcomes.isEmpty)
        #expect(harness.log.totalWins == 0)
    }

    // MARK: - 続行

    @Test("「続ける」で同じ盤面のままプレイを継続できる")
    func continueKeepsBoardAndScore() {
        let model = Game2048Model(board: Self.oneMoveFromWin, score: 100)
        model.move(.left)
        let boardAtWin = model.board
        let scoreAtWin = model.score

        model.continueAfterWin()

        #expect(!model.showWinPrompt, "演出は下りる")
        #expect(!model.gameOver)
        #expect(model.board == boardAtWin, "盤面はそのまま")
        #expect(model.score == scoreAtWin, "スコアもそのまま")
        #expect(Direction.allCases.contains { Game2048Logic.slide(model.board, $0).moved })
    }

    @Test("続行後、同じ局では二度と発火しない")
    func doesNotFireTwiceInTheSameGame() {
        let harness = makeHarness(suite: "no-refire")
        let model = makeModel(harness, board: Self.twoWinningTilesInOneMove)

        model.move(.left)
        #expect(model.showWinPrompt, "前提: 1 回目は発火する")
        model.continueAfterWin()

        // 2048 が 2 枚あるので、もう一度寄せれば 4096 ができる = 再び「勝利条件」を満たす盤になる。
        model.move(.left)

        #expect(model.board[0][0] == 4096, "前提: さらに合体している")
        #expect(!model.showWinPrompt, "同じ局では二度と出さない")
        #expect(harness.analytics.outcomes == [.win], "決着の通知も 1 回だけ")
        #expect(harness.log.record(gameID: "2048")?.wins == 1)
    }

    @Test("続行ぶんは次の 1 プレイとして数え直す（`game_start` と `game_end` が対応する）")
    func continuingCountsAsANewPlay() {
        let harness = makeHarness(suite: "restart-count")
        let model = makeModel(harness, board: Self.oneMoveFromWin)
        #expect(harness.analytics.starts == 1, "前提: 1 プレイ数えている")

        model.move(.left)
        #expect(harness.analytics.outcomes == [.win])

        model.continueAfterWin()
        #expect(harness.analytics.starts == 2, "続きは次の 1 プレイとして数える")
    }

    @Test("勝利演出を出している間はスワイプを受け付けない")
    func movesAreRejectedWhileThePromptIsUp() {
        let harness = makeHarness(suite: "reject-move")
        let model = makeModel(harness, board: Self.twoWinningTilesInOneMove)
        model.move(.left)
        #expect(model.showWinPrompt, "前提: 演出が出ている")
        let boardAtWin = model.board
        let scoreAtWin = model.score

        // 演出はスワイプ領域に重なるだけなので、Model 側で止まっていないと盤面が進む。
        for direction in Direction.allCases { model.move(direction) }

        #expect(model.board == boardAtWin, "盤面も新タイルも動かない")
        #expect(model.score == scoreAtWin, "スコアも動かない")
        #expect(model.showWinPrompt, "演出は出たまま")

        // 中断データも到達時点のまま（裏で進んだ盤が保存されていない）。
        let saved = harness.services.snapshots.load(Game2048Snapshot.self, for: "2048")
        #expect(saved?.board == boardAtWin)
        #expect(saved?.score == scoreAtWin)

        // 「続ける」を押せば従来どおり動かせる（拒否が恒久化していないことの確認）。
        model.continueAfterWin()
        model.move(.left)
        #expect(model.board != boardAtWin)
    }

    @Test("勝利直後に中断・復元して終局しても、`game_end` は 1 回のまま")
    func suspendingRightAfterTheWinDoesNotDoubleCountTheEnd() {
        let harness = makeHarness(suite: "suspend-after-win")
        let before = makeModel(harness, board: Self.oneMoveFromWin)
        before.move(.left)
        #expect(harness.analytics.outcomes == [.win], "前提: 到達で 1 回送っている")

        // 「続ける」を押さずにアプリが落ちた状態を、解析の数え方ごと作り直して再現する。
        let spy = SpyAnalyticsService()
        let restarted = GameServices(
            snapshots: harness.services.snapshots,
            ads: NoopAdService(),
            playLog: harness.log,
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["2048"])
        )
        let restored = Game2048Model(services: restarted)
        #expect(restored.hasWon)
        #expect(!restored.showWinPrompt)

        // 復元した続きを終局まで遊ぶ。
        while !restored.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(restored.board, $0).moved
            }) else { break }
            restored.move(direction)
        }
        #expect(restored.gameOver)

        // 中断からの再開は「新しいプレイ」として数えない（#158）ので、対応の取れない
        // `game_end` は作られない。到達時の 1 回に対して 2 回目は送られない。
        #expect(spy.starts == 0, "復元だけでは `game_start` を数えない")
        #expect(spy.outcomes.isEmpty, "開始を数えていないプレイの終局は送らない")
    }

    @Test("演出が出ていないときの `continueAfterWin()` は何もしない")
    func continueAfterWinIsNoOpWithoutPrompt() {
        let harness = makeHarness(suite: "noop")
        let model = makeModel(harness, board: Self.oneMoveFromWin)
        let startsBefore = harness.analytics.starts

        model.continueAfterWin()

        #expect(!model.showWinPrompt)
        #expect(harness.analytics.starts == startsBefore, "プレイを数え増やさない")
    }

    // MARK: - 中断・復元

    @Test("中断・復元をまたいでも再発火しない")
    func doesNotFireAgainAfterRestore() {
        let harness = makeHarness(suite: "restore")
        let before = makeModel(harness, board: Self.twoWinningTilesInOneMove)
        before.move(.left)
        #expect(before.hasWon)
        before.continueAfterWin()

        // アプリを起動し直した状態を、同じスナップショット置き場から作り直して再現する。
        let restored = Game2048Model(services: harness.services)
        #expect(restored.hasWon, "到達済みフラグが復元される")
        #expect(!restored.showWinPrompt, "復元しただけで演出は出ない")

        restored.move(.left)
        #expect(restored.board[0][0] == 4096, "前提: 復元後も合体できている")
        #expect(!restored.showWinPrompt)
        #expect(harness.analytics.outcomes == [.win], "勝ちの通知は通算 1 回のまま")
    }

    @Test("「もう一度」で到達済みフラグが戻り、次の局では改めて発火する")
    func newGameResetsTheFlag() {
        let model = Game2048Model(board: Self.oneMoveFromWin)
        model.move(.left)
        #expect(model.hasWon)

        model.newGame()

        #expect(!model.hasWon)
        #expect(!model.showWinPrompt)
    }

    // MARK: - スナップショットの後方互換

    @Test("`hasWon` を持たない旧バージョンの中断データも読める")
    func decodesLegacySnapshotWithoutHasWon() throws {
        let legacy = Data(#"{"board":[[2,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],"score":8}"#.utf8)
        let snapshot = try JSONDecoder().decode(Game2048Snapshot.self, from: legacy)
        #expect(snapshot.score == 8, "キーが増えても既存の中断データを失わせない")
        #expect(snapshot.hasWon == false)
    }

    @Test("既に 2048 が乗っている旧バージョンの中断データは到達済みとして読む")
    func legacySnapshotWithWinningTileIsTreatedAsWon() throws {
        let legacy = Data(#"{"board":[[2048,4,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],"score":30000}"#.utf8)
        let snapshot = try JSONDecoder().decode(Game2048Snapshot.self, from: legacy)
        #expect(snapshot.hasWon, "クリア済みの局を再開しただけで演出が出るのを防ぐ")
    }

    @Test("既に 2048 が乗った盤から始めても発火しない")
    func startingFromAWonBoardDoesNotFire() {
        let model = Game2048Model(board: [
            [2048, 4, 4, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])
        #expect(model.hasWon, "前提: 到達済みとして読む")

        model.move(.left)

        #expect(!model.showWinPrompt)
    }

    // MARK: - 到達と終局が同時のとき

    @Test("2048 を作った手で盤が埋まり切ったら、終局でも勝ちとして記録する")
    func winningMoveThatAlsoEndsTheGameIsRecordedAsWin() {
        let harness = makeHarness(suite: "win-and-over")
        let model = makeModel(harness, board: Self.winningMoveEndsTheGame)

        model.move(.left)

        #expect(model.gameOver, "前提: この手で終局する")
        #expect(model.hasWon)
        #expect(!model.showWinPrompt, "終局しているので続行の演出は出さない")
        #expect(harness.analytics.outcomes == [.win], "決着の通知は 1 回で、内容は勝ち")
        #expect(harness.log.record(gameID: "2048")?.wins == 1)
    }
}
