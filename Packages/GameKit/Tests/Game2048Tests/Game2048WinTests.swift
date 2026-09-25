import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

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
        #expect(harness.analytics.starts.count == 1, "前提: 1 プレイ数えている")

        model.move(.left)
        #expect(harness.analytics.outcomes == [.win])

        model.continueAfterWin()
        #expect(harness.analytics.starts.count == 2, "続きは次の 1 プレイとして数える")
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

    @Test("勝利直後に kill されても演出は残り、続行は 1 プレイとして対応が取れる")
    func suspendingRightAfterTheWinKeepsThePromptAndThePairing() {
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
        #expect(restored.showWinPrompt, "選ばないうちに演出が消えない（#516）")
        #expect(spy.starts.count == 0, "復元だけでは `game_start` を数えない")

        // 「続ける」を選んでから終局まで遊ぶ。
        restored.continueAfterWin()
        #expect(spy.starts.count == 1, "続行がこのプロセスの 1 プレイ目になる")
        while !restored.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(restored.board, $0).moved
            }) else { break }
            restored.move(direction)
        }
        #expect(restored.gameOver)

        // 数え直した 1 プレイに対して `game_end` はちょうど 1 回。到達時の `.win` は
        // 前のプロセスで送信済みなので、ここで二重には出ない。
        #expect(spy.outcomes.count == 1, "`game_start` 1 回に `game_end` 1 回で対応する")
    }

    @Test("演出が出ていないときの `continueAfterWin()` は何もしない")
    func continueAfterWinIsNoOpWithoutPrompt() {
        let harness = makeHarness(suite: "noop")
        let model = makeModel(harness, board: Self.oneMoveFromWin)
        let startsBefore = harness.analytics.starts.count

        model.continueAfterWin()

        #expect(!model.showWinPrompt)
        #expect(harness.analytics.starts.count == startsBefore, "プレイを数え増やさない")
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

    @Test("演出を出したまま画面を離れて入り直しても、演出は残る（#516）")
    func reenteringWhileThePromptIsUpKeepsIt() {
        let harness = makeHarness(suite: "reentry-with-prompt")
        let before = makeModel(harness, board: Self.oneMoveFromWin)
        before.move(.left)
        #expect(before.showWinPrompt, "前提: 演出が出ている")
        #expect(harness.analytics.outcomes == [.win], "前提: 到達で 1 回送っている")

        // 「続ける」を押さずにハブへ戻り、同じプロセスのまま入り直す。
        harness.services.gameDidLeave(gameID: "2048")
        let restored = Game2048Model(services: harness.services)

        #expect(restored.showWinPrompt, "演出は復元される（選ばないうちに消えない）")

        // 続きは従来どおり次の 1 プレイとして数え直せる。
        restored.continueAfterWin()
        #expect(harness.analytics.starts.count == 2, "続行が 1 プレイとして数えられる")
        while !restored.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(restored.board, $0).moved
            }) else { break }
            restored.move(direction)
        }
        #expect(harness.analytics.outcomes.count == 2, "数え直したプレイの終局も送られる")
    }

    // MARK: - スナップショットの後方互換

    @Test("`hasWon` を持たない旧バージョンの中断データも読める")
    func decodesLegacySnapshotWithoutHasWon() throws {
        let legacy = Data(#"{"board":[[2,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],"score":8}"#.utf8)
        let snapshot = try JSONDecoder().decode(Game2048Snapshot.self, from: legacy)
        #expect(snapshot.score == 8, "キーが増えても既存の中断データを失わせない")
        #expect(snapshot.hasWon == false)
    }

    @Test("`showWinPrompt` を持たない旧バージョンの中断データは演出なしとして読む（#516）")
    func decodesLegacySnapshotWithoutShowWinPrompt() throws {
        let legacy = Data(#"{"board":[[2048,4,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],"score":30000,"hasWon":true}"#.utf8)
        let snapshot = try JSONDecoder().decode(Game2048Snapshot.self, from: legacy)
        #expect(snapshot.hasWon, "前提: 到達済みの中断データ")
        #expect(!snapshot.showWinPrompt, "キーが増えても既存の中断データの挙動を変えない")
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

    // MARK: - 勝ちで終局した局のコンティニュー（#764）

    @Test("2048 を作った手で詰んだ局をコンティニューしても、過去の負けは消えない（#764）")
    func continuingAWinningGameOverKeepsPastLosses() {
        let harness = makeHarness(suite: "continue-after-winning-game-over")
        // この局と無関係な過去の負けを 1 件置く。
        harness.log.recordResult(gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 100))
        let model = makeModel(harness, board: Self.winningMoveEndsTheGame)

        model.move(.left)
        #expect(model.gameOver, "前提: この手で終局する")
        let recordAtGameOver = harness.log.record(gameID: "2048")
        #expect(recordAtGameOver?.plays == 2, "前提: 過去の負け 1 + この局の勝ち 1")
        #expect(recordAtGameOver?.wins == 1)
        #expect(recordAtGameOver?.losses == 1)

        #expect(model.continueAfterAd())

        let recordAfterContinue = harness.log.record(gameID: "2048")
        #expect(recordAfterContinue?.plays == 2, "過去の負けを巻き戻してプレイ数が減っている")
        #expect(recordAfterContinue?.wins == 1, "この局の勝ちはそのまま残る")
        #expect(recordAfterContinue?.losses == 1, "この局と無関係な過去の負けが消えている")
    }

    @Test("2048 到達 →「続ける」→ 詰んだ局は負けとして記録し、コンティニューで巻き戻す（#764）")
    func continuingAfterWinThenLosingCancelsTheLoss() {
        let harness = makeHarness(suite: "continue-after-win-then-lose")
        let model = makeModel(harness, board: Self.oneMoveFromWin)
        model.move(.left)
        #expect(model.hasWon, "前提: 到達済み")
        model.continueAfterWin()

        while !model.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(model.board, $0).moved
            }) else { break }
            model.move(direction)
        }
        #expect(model.gameOver, "前提: 続行ぶんを詰むまで遊んだ")
        #expect(harness.log.record(gameID: "2048")?.losses == 1, "前提: 到達済みでも、続行後の終局は負け")

        #expect(model.continueAfterAd())

        let record = harness.log.record(gameID: "2048")
        #expect(record?.losses == 0, "直前の負けが巻き戻っていない（`hasWon` で分岐すると壊れる）")
        #expect(record?.plays == 1, "到達時の勝ち 1 件だけが残る")
        #expect(record?.wins == 1)
    }

    @Test("勝ちで終局した局のコンティニュー後、次の局の負けは従来どおり巻き戻る（#764）")
    func lossFlagDoesNotLeakIntoTheNextGame() {
        let harness = makeHarness(suite: "continue-flag-reset")
        let model = makeModel(harness, board: Self.winningMoveEndsTheGame)
        model.move(.left)
        #expect(model.continueAfterAd(), "前提: 勝ちで終局した局をコンティニューする")

        // 「もう一度」で次の局を始め、負けで終局させる。
        model.newGame()
        while !model.gameOver {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(model.board, $0).moved
            }) else { break }
            model.move(direction)
        }
        #expect(model.gameOver)
        let lossesAtGameOver = harness.log.record(gameID: "2048")?.losses ?? 0
        #expect(lossesAtGameOver >= 1, "前提: 次の局は負けで記録されている")

        #expect(model.continueAfterAd())
        #expect(harness.log.record(gameID: "2048")?.losses == lossesAtGameOver - 1, "次の局の負けが巻き戻っていない")
    }
}
