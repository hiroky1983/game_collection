import Testing
import Foundation
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack
import GameDaifugo
import GameMahjongSolitaire
import GameMahjong
import GameSudoku
import GameGo

// MARK: - モック

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

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    private(set) var achievements: [GameCenterAchievement] = []
    /// `report` が呼ばれた回数（まとめて送っているかの検証に使う）。
    private(set) var reportCalls = 0
    /// 実績の送信が成功するか。false でオフライン（送信できなかった）を再現する。
    var reportSucceeds = true

    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        reportCalls += 1
        self.achievements.append(contentsOf: achievements)
        completion(reportSucceeds)
    }

    func percent(of achievementID: String) -> Double? {
        achievements.last { $0.achievementID == achievementID }?.percentComplete
    }
}

/// Model が実際に記録した区分キーを取り出し、対応表に通して得られるリーダーボード ID を返す。
///
/// タイム系の 3 ゲームは、テストが実時間を待たないため `elapsedSeconds` が 0 のまま終わる
/// （＝ 0 秒は捨てる仕様どおり送信されない）。それでも「Model が出す区分キーと対応表が
/// 噛み合っているか」は検証したいので、記録から区分キーを取り出して 60 秒のクリアとして通す。
@MainActor
private func leaderboardID(for gameID: String, in log: PlayLog) -> String? {
    let prefix = "\(gameID)#"
    let variant = log.records.keys
        .first { $0 == gameID || $0.hasPrefix(prefix) }
        .map { $0 == gameID ? nil : String($0.dropFirst(prefix.count)) } ?? nil
    return GameCenterLeaderboard.score(
        gameID: gameID, outcome: .win,
        score: GameScore(metric: .shortestTime, seconds: 60, variant: variant)
    )?.leaderboardID
}

/// 達成率は割り算の結果なので、丸め誤差を許して比べる（`1.0/12*100` と `100.0/12` は
/// 最下位ビットが一致しないことがある）。
private func isClose(_ actual: Double?, _ expected: Double) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) < 1e-9
}

/// ハブに登録済みのゲーム ID。ID の文字列は書かず各 `GameModule` の `id` から取る
/// （`AnalyticsTests` と同じやり方。どれかの `id` が変わったら実装と一緒にここも追従する）。
///
/// - Note: ハブへ**新しいゲームを追加**したときは、この配列にもモジュールを 1 行足す必要がある。
@MainActor
private func makeHubModules() -> [GameModule] {
    [
        Game2048Module(), ShogiModule(), GomokuModule(), MinesweeperModule(), OthelloModule(),
        PokerModule(), ConcentrationModule(), BlackjackModule(), DaifugoModule(),
        MahjongSolitaireModule(), MahjongModule(), SudokuModule(), GoModule(),
    ]
}

@MainActor
private func makeHubGameIDs() -> Set<String> {
    Set(GameRegistry(makeHubModules()).modules.map(\.id))
}

@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.gamecenter.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

/// **本番と同じ組み立て**の `GameServices` を作る。
///
/// 実績の進捗は `PlayLog` の通算値（`totalWins` / `playedGameIDs`）から作るが、それを増やすのは
/// `ReviewRequestService`（`recordWin`）と `RecommendationService`（`recordFinish`）である。
/// この 2 つを省いたテストでは進捗が常に 0 になり、順序の退行を検知できない。
@MainActor
private func makeServices(
    log: PlayLog,
    spy: SpyGameCenterService,
    isAvailable: @escaping @MainActor () -> Bool = { true }
) -> GameServices {
    GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        recommendations: RecommendationService(log: log, availableModules: { makeHubModules() }),
        review: ReviewRequestService(log: log, appVersion: "1.1.1"),
        playLog: log,
        gameCenter: GameCenterReporter(
            service: spy,
            allowedGameIDs: makeHubGameIDs(),
            isAvailable: isAvailable
        )
    )
}

// MARK: - 対応表（純粋関数）

@Suite("リーダーボードの対応表")
struct GameCenterLeaderboardTests {
    @Test("スコア系のゲームは勝敗を問わずスコアを送る")
    func pointsGames() {
        let g2048 = GameCenterLeaderboard.score(
            gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 12_340)
        )
        #expect(g2048 == GameCenterScore(leaderboardID: GameCenterLeaderboard.game2048Score, value: 12_340))

        let poker = GameCenterLeaderboard.score(
            gameID: "poker", outcome: .win, score: GameScore(metric: .points, points: 250)
        )
        #expect(poker?.leaderboardID == GameCenterLeaderboard.pokerChips)

        let blackjack = GameCenterLeaderboard.score(
            gameID: "blackjack", outcome: .draw, score: GameScore(metric: .points, points: 900)
        )
        #expect(blackjack?.leaderboardID == GameCenterLeaderboard.blackjackChips)
    }

    @Test("チップが 0 でも送る（0 は正当な記録）。points が無いときだけ送らない")
    func pointsBoundary() {
        let zero = GameCenterLeaderboard.score(
            gameID: "blackjack", outcome: .loss, score: GameScore(metric: .points, points: 0)
        )
        #expect(zero?.value == 0)

        let missing = GameCenterLeaderboard.score(
            gameID: "2048", outcome: .loss, score: GameScore(metric: .points)
        )
        #expect(missing == nil)
    }

    @Test("タイム系は勝ち / クリアのときだけ送る")
    func timeOnlyOnWin() {
        let score = GameScore(metric: .shortestTime, seconds: 42, variant: "9x9-10")
        #expect(GameCenterLeaderboard.score(gameID: "minesweeper", outcome: .win, score: score)
            == GameCenterScore(leaderboardID: GameCenterLeaderboard.minesweeperBeginner, value: 42))
        #expect(GameCenterLeaderboard.score(gameID: "minesweeper", outcome: .loss, score: score) == nil)
        #expect(GameCenterLeaderboard.score(gameID: "minesweeper", outcome: .draw, score: score) == nil)
    }

    @Test("マインスイーパーはプリセット3種だけが対象。カスタム盤は送らない")
    func minesweeperPresetsOnly() {
        func id(_ variant: String) -> String? {
            GameCenterLeaderboard.score(
                gameID: "minesweeper", outcome: .win,
                score: GameScore(metric: .shortestTime, seconds: 30, variant: variant)
            )?.leaderboardID
        }
        #expect(id("9x9-10") == GameCenterLeaderboard.minesweeperBeginner)
        #expect(id("12x12-25") == GameCenterLeaderboard.minesweeperIntermediate)
        #expect(id("15x15-40") == GameCenterLeaderboard.minesweeperExpert)
        #expect(id("20x20-99") == nil, "カスタム盤は登録できないので送らない")
    }

    @Test("0 秒のクリアは送らない（抜けない 1 位を作らない）")
    func zeroSecondsIsDropped() {
        #expect(GameCenterLeaderboard.score(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 0, variant: "9x9-10")
        ) == nil)
        #expect(GameCenterLeaderboard.score(
            gameID: "mahjong", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 1)
        )?.value == 1, "1 秒からは送る")
    }

    @Test("数独は難易度ごとに別のリーダーボード")
    func sudokuPerDifficulty() {
        func id(_ variant: String) -> String? {
            GameCenterLeaderboard.score(
                gameID: "sudoku", outcome: .win,
                score: GameScore(metric: .shortestTime, seconds: 300, variant: variant)
            )?.leaderboardID
        }
        #expect(id("easy") == GameCenterLeaderboard.sudokuEasy)
        #expect(id("normal") == GameCenterLeaderboard.sudokuNormal)
        #expect(id("hard") == GameCenterLeaderboard.sudokuHard)
        #expect(Set([id("easy"), id("normal"), id("hard")]).count == 3, "難易度が同じ表に混ざらない")
    }

    @Test("勝敗しか残らないゲームは対象外")
    func winLossGamesAreExcluded() {
        for gameID in ["shogi", "gomoku", "othello", "daifugo", "mahjong4", "concentration"] {
            #expect(
                GameCenterLeaderboard.score(
                    gameID: gameID, outcome: .win, score: GameScore(metric: .winLoss)
                ) == nil,
                "\(gameID) は勝敗だけなので順位表にしない"
            )
        }
    }

    @Test("麻雀ソリティア（mahjong）と四人打ち麻雀（mahjong4）を取り違えない")
    func mahjongIDsAreNotConfused() {
        let solitaire = GameCenterLeaderboard.score(
            gameID: "mahjong", outcome: .win, score: GameScore(metric: .shortestTime, seconds: 120)
        )
        #expect(solitaire?.leaderboardID == GameCenterLeaderboard.mahjongSolitaireTime)
        #expect(GameCenterLeaderboard.score(
            gameID: "mahjong4", outcome: .win, score: GameScore(metric: .shortestTime, seconds: 120)
        ) == nil)
    }

    @Test("麻雀ソリティアは標準の亀甲だけを順位表に載せる（#239）")
    func mahjongSolitaireOnlyPostsTheStandardLayout() {
        func id(_ variant: String?) -> String? {
            GameCenterLeaderboard.score(
                gameID: "mahjong", outcome: .win,
                score: GameScore(metric: .shortestTime, seconds: 300, variant: variant)
            )?.leaderboardID
        }
        // 区分なし（v1.1.1 までの記録）と亀甲は同じ表。
        #expect(id(nil) == GameCenterLeaderboard.mahjongSolitaireTime)
        #expect(id("turtle") == GameCenterLeaderboard.mahjongSolitaireTime)
        // かたちが違えば難度も違うので、同じ表には混ぜない（かたちごとの表は未登録）。
        #expect(id("pyramid") == nil)
        #expect(id("cross") == nil)
    }

    @Test("対応表が返す ID は必ず登録一覧（allIDs）に含まれる")
    func everyMappedIDIsRegistered() {
        let cases: [(String, GameScore)] = [
            ("2048", GameScore(metric: .points, points: 1)),
            ("poker", GameScore(metric: .points, points: 1)),
            ("blackjack", GameScore(metric: .points, points: 1)),
            ("minesweeper", GameScore(metric: .shortestTime, seconds: 1, variant: "9x9-10")),
            ("minesweeper", GameScore(metric: .shortestTime, seconds: 1, variant: "12x12-25")),
            ("minesweeper", GameScore(metric: .shortestTime, seconds: 1, variant: "15x15-40")),
            ("sudoku", GameScore(metric: .shortestTime, seconds: 1, variant: "easy")),
            ("sudoku", GameScore(metric: .shortestTime, seconds: 1, variant: "normal")),
            ("sudoku", GameScore(metric: .shortestTime, seconds: 1, variant: "hard")),
            ("mahjong", GameScore(metric: .shortestTime, seconds: 1)),
        ]
        let mapped = cases.compactMap {
            GameCenterLeaderboard.score(gameID: $0.0, outcome: .win, score: $0.1)?.leaderboardID
        }
        #expect(mapped.count == cases.count, "対応表から漏れている組み合わせがある")
        #expect(Set(mapped) == Set(GameCenterLeaderboard.allIDs), "登録一覧と対応表が食い違っている")
    }

    @Test("登録が必要な ID に重複が無い")
    func idsAreUnique() {
        #expect(Set(GameCenterLeaderboard.allIDs).count == GameCenterLeaderboard.allIDs.count)
        #expect(Set(GameCenterAchievements.allIDs).count == GameCenterAchievements.allIDs.count)
    }
}

// MARK: - 実績の進捗（純粋関数）

@Suite("実績の進捗")
struct GameCenterAchievementTests {
    @Test("まだ何も進んでいない実績は送らない")
    func nothingBeforeAnyProgress() {
        #expect(GameCenterAchievements.progress(
            totalWins: 0, playedGameCount: 0, registeredGameCount: 12
        ).isEmpty)
    }

    @Test("初勝利で firstWin が 100%、通算系は途中経過になる")
    func firstWin() {
        let progress = GameCenterAchievements.progress(
            totalWins: 1, playedGameCount: 1, registeredGameCount: 12
        )
        let byID = Dictionary(uniqueKeysWithValues: progress.map { ($0.achievementID, $0.percentComplete) })
        #expect(isClose(byID[GameCenterAchievements.firstWin], 100))
        #expect(isClose(byID[GameCenterAchievements.wins10], 10))
        #expect(isClose(byID[GameCenterAchievements.wins50], 2))
        #expect(isClose(byID[GameCenterAchievements.playAll], 100.0 / 12))
    }

    @Test("達成率は 100 を超えない")
    func percentIsCapped() {
        let progress = GameCenterAchievements.progress(
            totalWins: 999, playedGameCount: 99, registeredGameCount: 12
        )
        #expect(progress.allSatisfy { $0.percentComplete <= 100 })
        #expect(progress.count == GameCenterAchievements.allIDs.count)
    }

    @Test("登録ゲーム数が 0 なら playAll を出さない（ゼロ除算を作らない）")
    func noDivisionByZero() {
        let ids = GameCenterAchievements.progress(
            totalWins: 3, playedGameCount: 3, registeredGameCount: 0
        ).map(\.achievementID)
        #expect(!ids.contains(GameCenterAchievements.playAll))
    }
}

// MARK: - 送信係（オフライン・重複）

@Suite("Game Center 送信係")
@MainActor
struct GameCenterReporterTests {
    @Test("Game Center が使えないときは一度も送らない（オフライン・未サインイン）")
    func offlineSendsNothing() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(
            service: spy, allowedGameIDs: makeHubGameIDs(), isAvailable: { false }
        )
        reporter.gameDidFinish(
            gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 5_000),
            totalWins: 3, playedGameCount: 5
        )
        #expect(spy.scores.isEmpty)
        #expect(spy.achievements.isEmpty)
        #expect(spy.reportCalls == 0)
    }

    @Test("ハブに登録されていないゲーム ID は送らない")
    func unknownGameIDIsDropped() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: makeHubGameIDs())
        reporter.gameDidFinish(
            gameID: "not-a-game", outcome: .loss, score: GameScore(metric: .points, points: 1),
            totalWins: 1, playedGameCount: 1
        )
        #expect(spy.scores.isEmpty)
        #expect(spy.achievements.isEmpty)
    }

    @Test("達成率が変わらない実績は送り直さない")
    func achievementsAreNotResent() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: makeHubGameIDs())
        let score = GameScore(metric: .points, points: 100)

        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)
        #expect(spy.reportCalls == 1)
        let firstBatch = spy.achievements.count

        // 同じ進捗のまま決着（負けたので勝利数も遊んだ本数も増えない）
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)
        #expect(spy.reportCalls == 1, "同じ達成率を送り返さない")
        #expect(spy.achievements.count == firstBatch)

        // 進んだぶんだけ送る
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 2, playedGameCount: 1)
        #expect(spy.reportCalls == 2)
        #expect(isClose(spy.percent(of: GameCenterAchievements.wins10), 20))
        #expect(
            spy.achievements.filter { $0.achievementID == GameCenterAchievements.firstWin }.count == 1,
            "100% に達した実績は以後送らない"
        )
    }

    @Test("送信に失敗した実績の進捗は、次の決着で送り直される")
    func failedAchievementIsRetried() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: makeHubGameIDs())
        let score = GameScore(metric: .points, points: 100)

        // 1回目: オフラインで送信できなかった
        spy.reportSucceeds = false
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)
        #expect(spy.reportCalls == 1)

        // 2回目: 進捗は変わっていないが、前回届いていないので送り直す
        spy.reportSucceeds = true
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)
        #expect(spy.reportCalls == 2, "失敗したぶんは送信済みにしない")
        #expect(isClose(spy.percent(of: GameCenterAchievements.firstWin), 100))

        // 3回目: 今度は届いているので送り直さない
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)
        #expect(spy.reportCalls == 2)
    }

    @Test("失敗の通知が来ても、その間に進んだ進捗は巻き戻さない")
    func rollbackKeepsNewerProgress() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: makeHubGameIDs())
        let score = GameScore(metric: .points, points: 100)

        spy.reportSucceeds = true
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 1, playedGameCount: 1)   // wins10 = 10%
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 3, playedGameCount: 1)   // wins10 = 30%
        #expect(spy.reportCalls == 2)

        // 30% まで届いている状態で、同じ 30% を送り直させない
        reporter.gameDidFinish(gameID: "2048", outcome: .loss, score: score,
                               totalWins: 3, playedGameCount: 1)
        #expect(spy.reportCalls == 2)
    }

    @Test("リーダーボードは決着のたびに送る（Game Center 側が自己ベストを保つ）")
    func scoresAreSentEveryTime() {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: makeHubGameIDs())
        for points in [100, 50, 300] {
            reporter.gameDidFinish(
                gameID: "2048", outcome: .loss,
                score: GameScore(metric: .points, points: points),
                totalWins: 0, playedGameCount: 0
            )
        }
        #expect(spy.scores.map(\.value) == [100, 50, 300])
    }
}

// MARK: - 各ゲームからの送信（本番と同じ組み立てで駆動する）

@Suite("各ゲームが送るリーダーボード")
@MainActor
struct GameCenterPerGameTests {
    @Test("2048: ゲームオーバーでスコアが送られる")
    func game2048() {
        let (log, defaults, name) = makeLog(suite: "2048")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        // 左へ寄せると先頭行の 2+2 だけが合体し、必ず終局する盤面（`PlayRecordTests` と同じ）。
        let model = Game2048Model(
            services: makeServices(log: log, spy: spy),
            board: [
                [2, 2, 16, 32],
                [8, 4, 64, 8],
                [16, 8, 4, 64],
                [4, 16, 8, 32],
            ]
        )
        model.move(.left)

        #expect(model.gameOver)
        #expect(spy.scores == [
            GameCenterScore(leaderboardID: GameCenterLeaderboard.game2048Score, value: model.score),
        ])
    }

    @Test("マインスイーパー: 初級クリアで初級のタイムが送られ、実績も同じ決着で進む")
    func minesweeperWin() {
        let (log, defaults, name) = makeLog(suite: "minesweeper")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = MinesweeperModel(services: makeServices(log: log, spy: spy))
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        for r in 0..<9 {
            for c in 0..<9 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }

        #expect(model.gameState == .won)
        // テストは実時間を待たないので `elapsedSeconds` は 0 のまま = 送信は起きない
        // （0 秒は捨てる仕様）。ここで検証したいのは「Model が実際に出す区分キーが、
        // 登録済みのリーダーボードへ正しく対応しているか」なので、区分キーを記録から取り出して
        // 対応表に通す。区分キーの作り方（`recordVariant`）が変わればこのテストが落ちる。
        #expect(
            leaderboardID(for: "minesweeper", in: log) == GameCenterLeaderboard.minesweeperBeginner
        )
        // 実績の進捗は PlayLog の更新後の値から作る。ここが 100 でなければ、
        // `GameServices.gameDidFinish` の中で Game Center を review より先に呼んでいる（退行）。
        #expect(isClose(spy.percent(of: GameCenterAchievements.firstWin), 100))
        #expect(isClose(spy.percent(of: GameCenterAchievements.playAll), 100.0 / Double(makeHubModules().count)))
    }

    @Test("マインスイーパー: 地雷を踏んだ局は送らない")
    func minesweeperLoss() {
        let (log, defaults, name) = makeLog(suite: "minesweeper-loss")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = MinesweeperModel(services: makeServices(log: log, spy: spy))
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        let mine = model.cells.indices.flatMap { r in
            model.cells[r].indices.map { (r, $0) }
        }.first { model.cells[$0.0][$0.1].isMine }
        if let mine { model.tap(row: mine.0, col: mine.1) }

        #expect(model.gameState == .lost)
        #expect(spy.scores.isEmpty, "クリアしていない局のタイムは順位表に混ぜない")
        // 負けでも「遊んだ本数」は進むので playAll だけは動く。
        #expect(spy.percent(of: GameCenterAchievements.firstWin) == nil)
        #expect(isClose(spy.percent(of: GameCenterAchievements.playAll), 100.0 / Double(makeHubModules().count)))
    }

    @Test("数独: むずかしいをクリアすると hard のタイムが送られる")
    func sudokuWin() async {
        let (log, defaults, name) = makeLog(suite: "sudoku")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = SudokuModel(services: makeServices(log: log, spy: spy), seed: 555)
        await model.newGame(difficulty: .hard)
        for index in 0..<81 where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }

        #expect(model.state == .cleared)
        #expect(leaderboardID(for: "sudoku", in: log) == GameCenterLeaderboard.sudokuHard)
    }

    @Test("麻雀ソリティア: クリアでタイムが送られる")
    func mahjongSolitaireWin() {
        let (log, defaults, name) = makeLog(suite: "mahjong-solitaire")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = MahjongSolitaireModel(services: makeServices(log: log, spy: spy))
        for pair in model.solution {
            guard model.phase == .playing else { break }
            for index in pair { model.tap(index) }
        }

        #expect(model.phase == .won)
        #expect(leaderboardID(for: "mahjong", in: log) == GameCenterLeaderboard.mahjongSolitaireTime)
    }

    @Test("ブラックジャック: 精算後のチップが送られる")
    func blackjack() {
        let (log, defaults, name) = makeLog(suite: "blackjack")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = BlackjackModel(services: makeServices(log: log, spy: spy))
        model.placeBet(100)
        while model.phase == .playerTurn { model.hit() }   // バーストするまで引く

        #expect(spy.scores.count == 1)
        #expect(spy.scores.first?.leaderboardID == GameCenterLeaderboard.blackjackChips)
        #expect(spy.scores.first?.value == model.chips)
    }

    @Test("オセロ: 投了しても順位表には何も送らない")
    func othelloResign() {
        let (log, defaults, name) = makeLog(suite: "othello")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = OthelloModel(services: makeServices(log: log, spy: spy))
        model.resign()

        #expect(spy.scores.isEmpty)
    }

    @Test("Game Center が使えなくても、記録とリザルトは従来どおり返る（オフラインの担保）")
    func offlineKeepsGamePlayIntact() {
        let (log, defaults, name) = makeLog(suite: "offline")
        defer { defaults.removePersistentDomain(forName: name) }
        let spy = SpyGameCenterService()

        let model = Game2048Model(
            services: makeServices(log: log, spy: spy, isAvailable: { false }),
            board: [
                [2, 2, 16, 32],
                [8, 4, 64, 8],
                [16, 8, 4, 64],
                [4, 16, 8, 32],
            ]
        )
        model.move(.left)

        #expect(model.gameOver)
        #expect(spy.scores.isEmpty)
        #expect(spy.achievements.isEmpty)
        // 自己ベスト（#115）もリザルトの表示も Game Center の可否に依存しない。
        #expect(log.record(gameID: "2048")?.bestPoints == model.score)
        #expect(model.recordResult?.update.points == true)
    }
}

// MARK: - アプリ内から見る導線（#334）

/// v1.1.1 までは実績・リーダーボードの**送信**しか無く、アプリ内から**見る手段がゼロ**だった。
/// 導線は App ターゲット（`HubView` / `GameCenterEntry`）にあり GameKit のテストから import
/// できないため、`AppEnvironment.registry` の突き合わせ（RecommendationTests）と同じく
/// ソースを走査して固定する。
@Suite("実績・ランキングの導線")
struct GameCenterEntryPointTests {
    private func appSource(_ fileName: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameCenterTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
        return try String(
            contentsOf: repoRoot.appendingPathComponent("App/\(fileName)"), encoding: .utf8
        )
    }

    @Test("ハブのツールバーから実績・ランキングを開ける")
    func hubHasGameCenterEntryPoint() throws {
        let source = try appSource("HubView.swift")
        // 「トロフィーのボタンを押すと `openGameCenter()` が走る」という**結線**まで見る。
        // 部品の有無を個別に contains で確かめるだけだと、ボタンの中身を空にしても
        // `openGameCenter()` の定義側が文字列として残るため緑のまま素通りする（QA 指摘）。
        #expect(
            source.range(
                of: #"Button \{ openGameCenter\(\) \} label: \{\s*Image\(systemName: "trophy\.fill"\)"#,
                options: .regularExpression
            ) != nil,
            "トロフィーのボタンと openGameCenter() の結線が切れている"
        )
        #expect(source.contains("GameCenterEntry.open()"),
                "ハブから GameCenterEntry を呼ぶ導線が消えている")
        // アイコンだけのボタンは VoiceOver がシンボル名を読むため、明示のラベルが要る。
        #expect(source.contains(#"accessibilityLabel("実績・ランキング")"#),
                "アイコンボタンの読み上げラベルが消えている")
    }

    @Test("未サインインのときは Game Center を開かず、案内に落ちる")
    func entryChecksSignInBeforeOpening() throws {
        let source = try appSource("GameCenterEntry.swift")
        guard let signInGuard = source.range(of: "guard GameCenterAuth.isSignedIn"),
              let trigger = source.range(of: "GKAccessPoint.shared.trigger")
        else {
            Issue.record("サインイン判定またはダッシュボード起動が見つからない（走査のパターンが壊れている可能性）")
            return
        }
        // 判定が起動より**前**にあること。順序が入れ替わると、未サインインでも trigger を
        // 呼んで無反応になる（GameKit は認証済みを前提にするため何も起きない）。
        #expect(signInGuard.lowerBound < trigger.lowerBound,
                "サインイン判定より先に Game Center を開こうとしている")
        #expect(source.contains("case needsSignInGuidance"),
                "案内へ落とす経路が消えている")
    }

    @Test("iOS 26 で deprecated の GKGameCenterViewController に戻っていない")
    func doesNotUseDeprecatedGameCenterViewController() throws {
        // 置き換え先は GKAccessPoint（SDK ヘッダの API_DEPRECATED_WITH_REPLACEMENT が明示）。
        // 導線を触るときに「昔の作法」へ戻してしまわないよう、App/ 全体で禁止する。
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDir = repoRoot.appendingPathComponent("App")
        let swiftFiles = try FileManager.default
            .contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!swiftFiles.isEmpty, "App/ の走査に失敗している")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            // コメントでの言及（deprecated である理由の説明）は許す。コードとしての使用だけを禁じる。
            let usages = source.split(separator: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
                    && trimmed.contains("GKGameCenterViewController")
            }
            #expect(usages.isEmpty,
                    "\(file.lastPathComponent) が deprecated な GKGameCenterViewController を使っている: \(usages)")
        }
    }
}
