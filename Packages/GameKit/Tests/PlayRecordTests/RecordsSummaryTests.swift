import Testing
import Foundation
import Core

/// アプリ内「きろく」画面（#669）の中身。画面は App ターゲットにあるため、並び・文言・読み上げを
/// 決める `RecordsSummary` をここで固定する。
@MainActor
@Suite("きろく画面の集計（#669）")
struct RecordsSummaryTests {
    private static let games = [
        RecordsSummary.Game(id: "shogi", title: "将棋"),
        RecordsSummary.Game(id: "minesweeper", title: "マインスイーパー"),
        RecordsSummary.Game(id: "2048", title: "2048"),
    ]

    /// テスト専用の UserDefaults。テストごとに違う suite 名を渡すこと（並列実行のため）。
    private func makeLog(suite: String) -> PlayLog {
        let name = "asobiba.recordssummary.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// `GameServices.gameDidFinish` と同じ順で PlayLog に決着を積む。
    private func finish(_ log: PlayLog, _ gameID: String, _ outcome: GameOutcome, _ score: GameScore) {
        log.recordFinish(gameID: gameID)
        if outcome == .win { log.recordWin() }
        log.recordResult(gameID: gameID, outcome: outcome, score: score)
    }

    @Test("記録ゼロなら全ゲームが「まだ遊んでいない」で、並びは渡した順のまま")
    func emptyLogShowsEveryGameAsUnplayed() {
        let summary = makeLog(suite: "empty").recordsSummary(games: Self.games)
        #expect(summary.rows.map(\.gameID) == ["shogi", "minesweeper", "2048"])
        #expect(summary.rows.allSatisfy { !$0.isPlayed && $0.detailText == "まだ遊んでいない" })
        #expect(summary.rows.allSatisfy { $0.playsText == nil && $0.milestones.isEmpty })
        #expect(summary.progressText == "全部あそぶ 0/3")
        #expect(summary.totalWins == 0)
        #expect(summary.bestStreak == 0)
        #expect(summary.milestones.allSatisfy { !$0.isAchieved })
    }

    @Test("削除したゲーム（ルーレット #2545）の記録が残っていても、きろく画面は登録済みのゲームだけを数える")
    func removedRouletteRecordIsSkipped() {
        let log = makeLog(suite: "removedRoulette")
        finish(log, "roulette", .win, GameScore(metric: .points, points: 1200))
        finish(log, "shogi", .win, GameScore(metric: .winLoss))
        let summary = log.recordsSummary(games: Self.games)
        #expect(summary.rows.map(\.gameID) == ["shogi", "minesweeper", "2048"])
        #expect(summary.progressText == "全部あそぶ 1/3")
    }

    @Test("遊んだゲームは記録の1行・回数・節目が出て、進捗が数えられる")
    func playedGamesShowRecordsAndProgress() {
        let log = makeLog(suite: "played")
        for _ in 0..<3 { finish(log, "shogi", .win, GameScore(metric: .winLoss)) }
        finish(log, "shogi", .loss, GameScore(metric: .winLoss))
        for _ in 0..<6 { finish(log, "shogi", .win, GameScore(metric: .winLoss)) }
        finish(log, "minesweeper", .win,
               GameScore(metric: .shortestTime, seconds: 83, variant: "9x9-10", variantLabel: "初級"))

        let summary = log.recordsSummary(games: Self.games)
        let shogi = summary.rows[0]
        #expect(shogi.isPlayed)
        #expect(shogi.detailText == "9勝1敗・6連勝中")
        #expect(shogi.playsText == "10回")
        #expect(shogi.milestones == [.firstWin, .plays10])
        #expect(shogi.milestoneTitle(.firstWin) == "初勝利")

        let mines = summary.rows[1]
        #expect(mines.detailText == "最短 1:23（初級）")
        #expect(mines.milestones == [.firstWin])
        // タイムのゲームは「勝利」ではなく「クリア」と呼ぶ。
        #expect(mines.milestoneTitle(.firstWin) == "初クリア")

        #expect(!summary.rows[2].isPlayed)
        #expect(summary.playedCount == 2)
        #expect(summary.progressText == "全部あそぶ 2/3")
        #expect(summary.totalWins == 10)
        // 最高連勝は勝敗のゲームだけで数える（マインスイーパーの連続クリアは混ぜない）。
        #expect(summary.bestStreak == 6)
    }

    @Test("VoiceOver はゲーム名から1行ずつ読む")
    func accessibilityLabelsReadOneRowAtATime() {
        let log = makeLog(suite: "a11y")
        finish(log, "shogi", .win, GameScore(metric: .winLoss))
        finish(log, "shogi", .loss, GameScore(metric: .winLoss))
        let summary = log.recordsSummary(games: Self.games)
        #expect(summary.rows[0].accessibilityLabel == "将棋、1勝1敗、2回あそんだ、初勝利")
        #expect(summary.rows[2].accessibilityLabel == "2048、まだ遊んでいない")
        #expect(summary.milestones[0].accessibilityLabel == "はじめての勝利、達成")
        #expect(summary.milestones[1].accessibilityLabel == "通算10勝、1/10")
    }

    @Test("勝敗以外のゲームは「初クリア」と読み、数字の無い記録は「記録なし」と出す")
    func nonWinLossAndRecordWithoutNumbers() {
        let log = makeLog(suite: "nonwinloss")
        finish(log, "minesweeper", .win,
               GameScore(metric: .shortestTime, seconds: 83, variant: "9x9-10", variantLabel: "初級"))
        // スコアを申告しない終わり方だけ（見出しの数字が作れない）。
        finish(log, "2048", .loss, GameScore(metric: .points))
        let summary = log.recordsSummary(games: Self.games)
        #expect(summary.rows[1].accessibilityLabel == "マインスイーパー、最短 1:23（初級）、1回あそんだ、初クリア")
        #expect(summary.rows[2].isPlayed)
        #expect(summary.rows[2].detailText == "記録なし")
        #expect(summary.rows[2].accessibilityLabel == "2048、記録なし、1回あそんだ")
    }

    @Test("プレイ記録を消去すると、次に開いたときは全部が未プレイに戻る")
    func clearingThePlayLogResetsTheSummary() {
        let log = makeLog(suite: "clear")
        finish(log, "shogi", .win, GameScore(metric: .winLoss))
        finish(log, "2048", .loss, GameScore(metric: .points, points: 1200))
        #expect(log.recordsSummary(games: Self.games).playedCount == 2)

        log.clear()
        let summary = log.recordsSummary(games: Self.games)
        #expect(summary == RecordsSummary.make(games: Self.games, playedGameIDs: [], records: [:], totalWins: 0))
        #expect(summary.rows.allSatisfy { !$0.isPlayed })
    }

    @Test("集計しても PlayLog のキーは増えない（保存項目を足さない）")
    func summaryDoesNotPersistAnything() {
        let name = "asobiba.recordssummary.tests.nopersist"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        finish(log, "shogi", .win, GameScore(metric: .winLoss))
        let before = defaults.persistentDomain(forName: name) as NSDictionary?
        _ = log.recordsSummary(games: Self.games)
        let after = defaults.persistentDomain(forName: name) as NSDictionary?
        #expect(before == after)
        #expect(Set((after as? [String: Any] ?? [:]).keys).isSubset(of: Set(PlayLog.allKeys)))
    }

    @Test("節目の達成率は Game Center の実績と同じ式")
    func milestonesMatchGameCenterAchievements() {
        for (wins, played) in [(0, 0), (1, 1), (7, 2), (10, 3), (57, 3)] {
            let records = Dictionary(uniqueKeysWithValues: Self.games.prefix(played).map {
                ($0.id, [PlayRecord(plays: 1)])
            })
            let summary = RecordsSummary.make(
                games: Self.games, playedGameIDs: [], records: records, totalWins: wins
            )
            let reported = Dictionary(uniqueKeysWithValues: GameCenterAchievements.progress(
                totalWins: wins, playedGameCount: played, registeredGameCount: Self.games.count
            ).map { ($0.achievementID, $0.percentComplete) })

            #expect(summary.milestones.map(\.achievementID) == GameCenterAchievements.allIDs)
            for milestone in summary.milestones {
                let percent = min(100, Double(milestone.value) / Double(milestone.target) * 100)
                // Game Center は 0% を送らないので、送られていないものは 0 として比べる。
                #expect(percent == (reported[milestone.achievementID] ?? 0),
                        "\(milestone.title): wins=\(wins) played=\(played)")
                #expect(milestone.isAchieved == (percent >= 100))
            }
        }
    }

    @Test("達成後の進捗表記は目標で頭打ちにする")
    func progressTextCapsAtTarget() {
        let summary = RecordsSummary.make(games: Self.games, playedGameIDs: [], records: [:], totalWins: 57)
        #expect(summary.milestones.map(\.progressText) == ["1/1", "10/10", "50/50", "0/3"])
    }

    @Test("最後に遊んだ日は暦日で数え、今日・昨日・N 日前になる（#2871）")
    func lastPlayedTextCountsCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30))!
        func row(_ last: Date?, played: Bool = true) -> RecordsSummary.Row {
            RecordsSummary.make(
                games: [RecordsSummary.Game(id: "shogi", title: "将棋")],
                playedGameIDs: played ? ["shogi"] : [],
                records: [:],
                totalWins: 0,
                lastPlayedAt: last.map { ["shogi": $0] } ?? [:]
            ).rows[0]
        }
        // 23 時間前でも暦日が違えば「昨日」。
        let yesterdayLate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23, minute: 50))!
        let threeDays = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let future = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        #expect(row(now).lastPlayedText(now: now, calendar: calendar) == "最後に遊んだのは今日")
        #expect(row(yesterdayLate).lastPlayedText(now: now, calendar: calendar) == "最後に遊んだのは昨日")
        #expect(row(threeDays).lastPlayedText(now: now, calendar: calendar) == "最後に遊んだのは3日前")
        #expect(row(future).lastPlayedText(now: now, calendar: calendar) == "最後に遊んだのは今日")
        #expect(row(nil).lastPlayedText(now: now, calendar: calendar) == nil)
        #expect(row(now, played: false).lastPlayedText(now: now, calendar: calendar) == nil)
        #expect(row(now).accessibilityLabel(lastPlayedText: "最後に遊んだのは今日").contains("最後に遊んだのは今日"))
    }

    @Test("PlayLog に積んだ最終プレイ日時が行に載る（#2871）")
    func lastPlayedAtComesFromPlayLog() {
        let log = makeLog(suite: "lastPlayed")
        finish(log, "shogi", .win, GameScore(metric: .winLoss))
        let rows = log.recordsSummary(games: Self.games).rows
        #expect(rows[0].lastPlayedAt != nil)
        #expect(rows[1].lastPlayedAt == nil)
        #expect(rows[0].lastPlayedText(now: Date()) == "最後に遊んだのは今日")
    }
}
