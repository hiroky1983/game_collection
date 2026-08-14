import Testing
import Foundation
import Core
import Game2048
import GameMinesweeper
import GameOthello
import GameBlackjack
import GameMahjongSolitaire

// MARK: - 共通のヘルパー

/// テスト専用の UserDefaults を作る。テストごとに違う suite 名を渡すこと（並列実行のため）。
@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.playrecord.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

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

@MainActor
private func makeServices(log: PlayLog) -> GameServices {
    GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
}

// MARK: - 自己ベストの判定（純粋関数）

@Suite("自己ベストの判定")
struct PlayRecordApplyTests {
    @Test("スコアは高いほうが自己ベスト。同点は更新扱いにしない")
    func pointsStrictlyGreater() {
        let first = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 1200), to: nil
        )
        #expect(first.record.bestPoints == 1200)
        #expect(first.update.points)

        // 同点 → 更新ではない（値もそのまま）
        let tie = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 1200), to: first.record
        )
        #expect(tie.record.bestPoints == 1200)
        #expect(!tie.update.points)
        #expect(!tie.update.isNewBest)

        // 下回った → 更新ではない
        let worse = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 900), to: tie.record
        )
        #expect(worse.record.bestPoints == 1200)
        #expect(!worse.update.points)

        // 上回った → 更新
        let better = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 1201), to: worse.record
        )
        #expect(better.record.bestPoints == 1201)
        #expect(better.update.points)
    }

    @Test("タイムは短いほうが自己ベスト。同タイムは更新扱いにしない")
    func secondsStrictlyLess() {
        let first = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .shortestTime, seconds: 90), to: nil
        )
        #expect(first.record.bestSeconds == 90)
        #expect(first.update.seconds)

        let tie = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .shortestTime, seconds: 90), to: first.record
        )
        #expect(tie.record.bestSeconds == 90)
        #expect(!tie.update.seconds)

        let better = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .shortestTime, seconds: 89), to: tie.record
        )
        #expect(better.record.bestSeconds == 89)
        #expect(better.update.seconds)
    }

    @Test("手数は少ないほうが自己ベスト。同手数は更新扱いにしない")
    func movesStrictlyLess() {
        let first = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .fewestMoves, moves: 30), to: nil
        )
        #expect(first.record.fewestMoves == 30)
        #expect(first.update.moves)

        let tie = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .fewestMoves, moves: 30), to: first.record
        )
        #expect(!tie.update.moves)
    }

    @Test("負けた局のタイム・手数は自己ベストに取り込まない")
    func lossDoesNotRecordTime() {
        // 投了した瞬間が常に「最短クリアタイム」になってしまうのを防ぐ。
        let result = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .shortestTime, seconds: 3, moves: 1), to: nil
        )
        #expect(result.record.bestSeconds == nil)
        #expect(result.record.fewestMoves == nil)
        #expect(!result.update.isNewBest)
        // 挑戦回数と敗北数は増える
        #expect(result.record.plays == 1)
        #expect(result.record.losses == 1)
    }

    @Test("負けても、スコアは自己ベストの対象になる（2048 のように勝ちが無いゲーム）")
    func lossStillRecordsPoints() {
        let result = PlayRecord.applying(
            outcome: .loss,
            score: GameScore(metric: .points, points: 5000, highestValue: 512),
            to: nil
        )
        #expect(result.record.bestPoints == 5000)
        #expect(result.record.highestValue == 512)
        #expect(result.update.isNewBest)
    }

    @Test("連勝は勝ちで伸び、負け・引き分けで途切れる")
    func streak() {
        var record: PlayRecord?
        for _ in 0..<3 {
            record = PlayRecord.applying(outcome: .win, score: GameScore(), to: record).record
        }
        #expect(record?.currentStreak == 3)
        #expect(record?.bestStreak == 3)
        #expect(record?.wins == 3)

        record = PlayRecord.applying(outcome: .draw, score: GameScore(), to: record).record
        #expect(record?.currentStreak == 0)
        #expect(record?.bestStreak == 3)   // 最高連勝は残る
        #expect(record?.draws == 1)

        record = PlayRecord.applying(outcome: .win, score: GameScore(), to: record).record
        record = PlayRecord.applying(outcome: .loss, score: GameScore(), to: record).record
        #expect(record?.currentStreak == 0)
        #expect(record?.bestStreak == 3)
        #expect(record?.losses == 1)
        #expect(record?.plays == 6)
    }

    @Test("連勝の更新演出は2連勝から（初勝利では出さない）")
    func streakBadgeStartsAtTwo() {
        let first = PlayRecord.applying(outcome: .win, score: GameScore(), to: nil)
        #expect(first.record.bestStreak == 1)
        #expect(!first.update.streak)

        let second = PlayRecord.applying(outcome: .win, score: GameScore(), to: first.record)
        #expect(second.record.bestStreak == 2)
        #expect(second.update.streak)
    }
}

// MARK: - 表示の整形

@Suite("記録の1行表示")
struct RecordFormatTests {
    @Test("秒数の整形")
    func time() {
        #expect(RecordFormat.time(0) == "0:00")
        #expect(RecordFormat.time(9) == "0:09")
        #expect(RecordFormat.time(83) == "1:23")
        #expect(RecordFormat.time(3661) == "1:01:01")
    }

    @Test("3桁区切り")
    func number() {
        #expect(RecordFormat.number(0) == "0")
        #expect(RecordFormat.number(999) == "999")
        #expect(RecordFormat.number(1000) == "1,000")
        #expect(RecordFormat.number(12340) == "12,340")
        #expect(RecordFormat.number(1234567) == "1,234,567")
    }

    @Test("記録が無いゲームはハブに1行も出さない")
    func hubLineEmpty() {
        #expect(RecordFormat.hubLine([]) == nil)
        #expect(RecordFormat.hubLine([PlayRecord()]) == nil)
    }

    @Test("ハブの1行: スコア・タイム・手数・勝敗")
    func hubLines() {
        let points = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 12340), to: nil
        ).record
        #expect(RecordFormat.hubLine([points]) == "ベスト 12,340")

        let moves = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .fewestMoves, moves: 24), to: nil
        ).record
        #expect(RecordFormat.hubLine([moves]) == "最少 24手")

        var winLoss: PlayRecord?
        for _ in 0..<3 { winLoss = PlayRecord.applying(outcome: .win, score: GameScore(), to: winLoss).record }
        winLoss = PlayRecord.applying(outcome: .loss, score: GameScore(), to: winLoss).record
        #expect(RecordFormat.hubLine([winLoss!]) == "3勝1敗")   // 連勝中でなければ連勝は出さない

        winLoss = PlayRecord.applying(outcome: .win, score: GameScore(), to: winLoss).record
        winLoss = PlayRecord.applying(outcome: .win, score: GameScore(), to: winLoss).record
        #expect(RecordFormat.hubLine([winLoss!]) == "5勝1敗・2連勝中")
    }

    @Test("難易度が複数あるゲームは、一番速い記録を難易度名つきで代表にする")
    func hubLinePicksFastestVariant() {
        let easy = PlayRecord.applying(
            outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 45, variant: "9x9-10", variantLabel: "初級"),
            to: nil
        ).record
        let hard = PlayRecord.applying(
            outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 480, variant: "15x15-40", variantLabel: "上級"),
            to: nil
        ).record
        #expect(RecordFormat.hubLine([easy, hard]) == "最短 0:45（初級）")
        // 並び順が変わっても同じ結果になる
        #expect(RecordFormat.hubLine([hard, easy]) == "最短 0:45（初級）")
    }

    @Test("リザルトの1行")
    func resultLines() {
        let points = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, points: 12340, highestValue: 1024), to: nil
        ).record
        #expect(RecordFormat.resultLine(points) == "自己ベスト 12,340（最大 1,024）")

        let cleared = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .shortestTime, seconds: 83), to: nil
        ).record
        #expect(RecordFormat.resultLine(cleared) == "最短タイム 1:23・1回クリア")

        // まだクリアしていないときは挑戦回数を出す
        let notCleared = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .shortestTime, seconds: 10), to: nil
        ).record
        #expect(RecordFormat.resultLine(notCleared) == "クリア記録なし（1回挑戦）")
    }
}

// MARK: - 永続化

@Suite("プレイ記録の永続化")
@MainActor
struct PlayRecordStorageTests {
    @Test("記録はアプリ再起動をまたいで保持される")
    func survivesRelaunch() {
        let (log, defaults, name) = makeLog(suite: "relaunch")
        defer { defaults.removePersistentDomain(forName: name) }

        log.recordResult(gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 8888))
        log.recordResult(
            gameID: "minesweeper",
            outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 42, variant: "9x9-10", variantLabel: "初級")
        )

        // 「再起動」— 同じ UserDefaults から作り直す
        let reopened = PlayLog(defaults: defaults)
        #expect(reopened.record(gameID: "2048")?.bestPoints == 8888)
        #expect(reopened.record(gameID: "minesweeper", variant: "9x9-10")?.bestSeconds == 42)
        #expect(reopened.summaryLine(gameID: "2048") == "ベスト 8,888")
        #expect(reopened.summaryLine(gameID: "minesweeper") == "最短 0:42（初級）")
    }

    @Test("難易度ごとに別々の記録として保存される")
    func variantsAreSeparate() {
        let (log, defaults, name) = makeLog(suite: "variants")
        defer { defaults.removePersistentDomain(forName: name) }

        log.recordResult(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 40, variant: "9x9-10", variantLabel: "初級")
        )
        log.recordResult(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 400, variant: "15x15-40", variantLabel: "上級")
        )

        #expect(log.record(gameID: "minesweeper", variant: "9x9-10")?.bestSeconds == 40)
        #expect(log.record(gameID: "minesweeper", variant: "15x15-40")?.bestSeconds == 400)
        #expect(log.records(gameID: "minesweeper").count == 2)
        // 区分の無いキー（gameID 単体）は作られない
        #expect(log.record(gameID: "minesweeper") == nil)
    }

    @Test("消去するとゲーム別の記録も残らない")
    func clearRemovesRecords() {
        let (log, defaults, name) = makeLog(suite: "clear")
        defer { defaults.removePersistentDomain(forName: name) }

        log.recordResult(gameID: "othello", outcome: .win, score: GameScore(metric: .winLoss))
        log.recordFinish(gameID: "othello")
        #expect(defaults.data(forKey: PlayLog.recordsKey) != nil)

        log.clear()
        #expect(log.records.isEmpty)
        #expect(log.summaryLine(gameID: "othello") == nil)
        #expect(defaults.data(forKey: PlayLog.recordsKey) == nil)
        // 消去後に作り直しても復活しない
        #expect(PlayLog(defaults: defaults).records.isEmpty)
    }

    @Test("書き込むキーは規定の10キーだけで、遊ぶほど増えたりしない")
    func keysDoNotGrow() {
        let (log, defaults, name) = makeLog(suite: "keys")
        defer { defaults.removePersistentDomain(forName: name) }

        for i in 0..<200 {
            log.recordResult(
                gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: i)
            )
        }
        let keys = Set((defaults.persistentDomain(forName: name) ?? [:]).keys)
        #expect(keys == Set(PlayLog.playRecordKeys))
        #expect(log.records.count == 1)
    }

    @Test("壊れた保存データがあっても空として起動する")
    func brokenDataFallsBackToEmpty() {
        let (_, defaults, name) = makeLog(suite: "broken")
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(Data([0x00, 0x01, 0x02]), forKey: PlayLog.recordsKey)
        #expect(PlayLog(defaults: defaults).records.isEmpty)
    }
}

// MARK: - 各ゲームからの記録

@Suite("各ゲームが記録する指標")
@MainActor
struct GameRecordingTests {
    @Test("2048: ゲームオーバーでスコアと最大タイルが記録される")
    func game2048RecordsScore() {
        let (log, defaults, name) = makeLog(suite: "game2048")
        defer { defaults.removePersistentDomain(forName: name) }

        // 左へ寄せると先頭行の 2+2 だけが合体し、空いた1マスに 2/4 のどちらが湧いても
        // 隣接する同じ数が生まれない = 必ず終局する盤面。
        let model = Game2048Model(
            services: makeServices(log: log),
            board: [
                [2, 2, 16, 32],
                [8, 4, 64, 8],
                [16, 8, 4, 64],
                [4, 16, 8, 32],
            ]
        )
        model.move(.left)

        #expect(model.gameOver)
        let record = log.record(gameID: "2048")
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == model.score)
        #expect(record?.highestValue == 64)
        #expect(model.recordResult?.update.points == true)
        #expect(log.summaryLine(gameID: "2048") == "ベスト \(RecordFormat.number(model.score))")
    }

    @Test("マインスイーパー: クリアで難易度別のタイムが記録される")
    func minesweeperRecordsTime() {
        let (log, defaults, name) = makeLog(suite: "minesweeper")
        defer { defaults.removePersistentDomain(forName: name) }

        // 初級（9×9・地雷10）。1手目で地雷が配置されるので、そのあと安全マスだけを開けば必ずクリアできる。
        let model = MinesweeperModel(services: makeServices(log: log))
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        for r in 0..<9 {
            for c in 0..<9 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }

        #expect(model.gameState == .won)
        let record = log.record(gameID: "minesweeper", variant: "9x9-10")
        #expect(record?.metric == .shortestTime)
        #expect(record?.wins == 1)
        #expect(record?.bestSeconds == model.elapsedSeconds)
        #expect(record?.variantLabel == "初級")
    }

    @Test("マインスイーパー: 地雷を踏んだ局のタイムは記録されない")
    func minesweeperLossKeepsNoTime() {
        let (log, defaults, name) = makeLog(suite: "minesweeperLoss")
        defer { defaults.removePersistentDomain(forName: name) }

        // 1手目で地雷を配置させてから、その地雷を踏む。
        let model = MinesweeperModel(services: makeServices(log: log))
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        let mine = model.cells.indices.flatMap { r in
            model.cells[r].indices.map { (r, $0) }
        }.first { model.cells[$0.0][$0.1].isMine }
        #expect(mine != nil)
        if let mine { model.tap(row: mine.0, col: mine.1) }

        #expect(model.gameState == .lost)
        let record = log.record(gameID: "minesweeper", variant: "9x9-10")
        #expect(record?.losses == 1)
        #expect(record?.bestSeconds == nil)
        #expect(log.summaryLine(gameID: "minesweeper") == nil)   // クリア記録が無ければハブには出さない
    }

    @Test("麻雀ソリティア: クリアでタイムとクリア回数が記録される")
    func mahjongSolitaireRecordsTime() {
        let (log, defaults, name) = makeLog(suite: "mahjong")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = MahjongSolitaireModel(services: makeServices(log: log))
        // 生成時に用意されている取り切り手順どおりにタップして完走させる。
        for pair in model.solution {
            guard model.phase == .playing else { break }
            for index in pair { model.tap(index) }
        }

        #expect(model.phase == .won)
        let record = log.record(gameID: "mahjong")
        #expect(record?.metric == .shortestTime)
        #expect(record?.wins == 1)
        #expect(record?.bestSeconds != nil)
        #expect(model.recordResult?.update.seconds == true)
    }

    @Test("ブラックジャック: 精算後のチップが最高記録になる")
    func blackjackRecordsChips() {
        let (log, defaults, name) = makeLog(suite: "blackjack")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = BlackjackModel(services: makeServices(log: log))
        model.placeBet(100)
        while model.phase == .playerTurn { model.hit() }   // バーストするまで引く

        let record = log.record(gameID: "blackjack")
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == model.chips)
        #expect(record?.plays == 1)
    }

    @Test("オセロ: 投了で敗北が記録され、連勝は0に戻る")
    func othelloRecordsWinLoss() {
        let (log, defaults, name) = makeLog(suite: "othello")
        defer { defaults.removePersistentDomain(forName: name) }

        // 先に2連勝したことにしておく
        log.recordResult(gameID: "othello", outcome: .win, score: GameScore(metric: .winLoss))
        log.recordResult(gameID: "othello", outcome: .win, score: GameScore(metric: .winLoss))
        #expect(log.summaryLine(gameID: "othello") == "2勝0敗・2連勝中")

        let model = OthelloModel(services: makeServices(log: log))
        model.resign()

        let record = log.record(gameID: "othello")
        #expect(record?.losses == 1)
        #expect(record?.currentStreak == 0)
        #expect(record?.bestStreak == 2)
        #expect(log.summaryLine(gameID: "othello") == "2勝1敗")
    }

    @Test("記録サービスを注入しない構成（プレビュー・テスト）では何も記録されない")
    func withoutPlayLogNothingIsRecorded() {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let result = services.gameDidFinish(
            gameID: "othello", outcome: .win, score: GameScore(metric: .winLoss)
        )
        #expect(result == nil)
    }
}
