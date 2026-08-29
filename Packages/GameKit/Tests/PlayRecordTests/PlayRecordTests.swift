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
import MahjongTiles

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

    @Test("引き分けだけの記録でもハブに1行出る（大富豪の中位フィニッシュ）")
    func hubLineShowsDrawOnlyRecord() {
        // 大富豪は4人中1位が勝ち・最下位が負け・中位は引き分け。中位が続くと勝敗が両方0になる。
        var record: PlayRecord?
        for _ in 0..<3 {
            record = PlayRecord.applying(outcome: .draw, score: GameScore(), to: record).record
        }
        #expect(RecordFormat.hubLine([record!]) == "0勝0敗3分")
        #expect(RecordFormat.resultLine(record!) == "通算 0勝0敗3分")

        // 勝ち負けが混ざれば引き分けも添える
        record = PlayRecord.applying(outcome: .win, score: GameScore(), to: record).record
        record = PlayRecord.applying(outcome: .loss, score: GameScore(), to: record).record
        #expect(RecordFormat.hubLine([record!]) == "1勝1敗3分")
    }

    @Test("到達した最大値も同点は更新扱いにしない")
    func highestValueStrictlyGreater() {
        let first = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, highestValue: 512), to: nil
        )
        #expect(first.record.highestValue == 512)
        #expect(first.update.highestValue)

        let tie = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, highestValue: 512), to: first.record
        )
        #expect(tie.record.highestValue == 512)
        #expect(!tie.update.highestValue)
        #expect(!tie.update.isNewBest)

        let better = PlayRecord.applying(
            outcome: .loss, score: GameScore(metric: .points, highestValue: 1024), to: tie.record
        )
        #expect(better.record.highestValue == 1024)
        #expect(better.update.highestValue)
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

    /// #335 で `lastPlayedAt` を足したときの旧データ互換。**Optional で足す**という前提が崩れると
    /// `[String: PlayRecord]` のデコードが丸ごと失敗し、`PlayLog.init` のフォールバックで
    /// 全ゲームの自己ベストが消える。
    @Test("lastPlayedAt を持たない旧データを読んでも記録が消えない")
    func decodesRecordsWithoutLastPlayedAt() {
        let (_, defaults, name) = makeLog(suite: "legacy-records")
        defer { defaults.removePersistentDomain(forName: name) }

        // #335 より前のバージョンが書いた JSON（lastPlayedAt の鍵が無い）。
        let legacy = """
        {"2048":{"metric":"points","plays":7,"wins":0,"losses":7,"draws":0,\
        "currentStreak":0,"bestStreak":0,"bestPoints":8888,"highestValue":1024}}
        """
        defaults.set(Data(legacy.utf8), forKey: PlayLog.recordsKey)

        let log = PlayLog(defaults: defaults)
        #expect(log.record(gameID: "2048")?.bestPoints == 8888, "旧データの自己ベストが読める")
        #expect(log.record(gameID: "2048")?.plays == 7)
        #expect(log.record(gameID: "2048")?.lastPlayedAt == nil, "日付は不明のまま")
        #expect(log.lastPlayedAtByGame.isEmpty, "日付が無い記録は最終プレイ日時に載せない")

        // 次に1回遊べば日付が入り、旧データの自己ベストも残っている。
        let playedAt = Date(timeIntervalSince1970: 1_800_000_000)
        log.recordResult(gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 1), at: playedAt)
        #expect(log.record(gameID: "2048")?.bestPoints == 8888)
        #expect(log.lastPlayedAtByGame["2048"] == playedAt)
    }

    @Test("最終プレイ日時は難易度をまたいで最も新しいものを代表にする")
    func lastPlayedAtAcrossVariants() {
        let (log, defaults, name) = makeLog(suite: "last-played")
        defer { defaults.removePersistentDomain(forName: name) }

        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(86_400)
        log.recordResult(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 40, variant: "15x15-40", variantLabel: "上級"),
            at: newer
        )
        log.recordResult(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 40, variant: "9x9-10", variantLabel: "初級"),
            at: older
        )

        #expect(log.lastPlayedAtByGame["minesweeper"] == newer, "区分をまたいで最新")
        // 同じ区分に古い日時で書き込んでも巻き戻らない（CodeRabbit 指摘）。
        log.recordResult(
            gameID: "minesweeper", outcome: .win,
            score: GameScore(metric: .shortestTime, seconds: 40, variant: "15x15-40", variantLabel: "上級"),
            at: older
        )
        #expect(log.record(gameID: "minesweeper", variant: "15x15-40")?.lastPlayedAt == newer,
                "古い日時で上書きされない")
        #expect(log.lastPlayedAtByGame["minesweeper"] == newer)
        // 再起動しても保持される（records と同じ1キーに入っているだけで、キーは増えない）。
        #expect(PlayLog(defaults: defaults).lastPlayedAtByGame["minesweeper"] == newer)
        #expect(Set((defaults.persistentDomain(forName: name) ?? [:]).keys) == Set(PlayLog.playRecordKeys),
                "日付を足してもキーは増えない")
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

    @Test("麻雀ソリティア: クリアでタイムとクリア回数が盤面のかたちごとに記録される")
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
        // 記録の区分キーはレイアウトの id（#239）。既定は亀甲。
        let record = log.record(gameID: "mahjong", variant: "turtle")
        #expect(record?.metric == .shortestTime)
        #expect(record?.wins == 1)
        #expect(record?.bestSeconds != nil)
        #expect(record?.variantLabel == "亀甲")
        #expect(model.recordResult?.update.seconds == true)
        // 区分なしのキーには入らない（マインスイーパー・数独と同じ扱い）。
        #expect(log.record(gameID: "mahjong") == nil)
        #expect(log.summaryLine(gameID: "mahjong")?.contains("（亀甲）") == true)
    }

    @Test("麻雀ソリティア: 別のかたちのクリアは別の記録になる")
    func mahjongSolitaireKeepsRecordsPerLayout() {
        let (log, defaults, name) = makeLog(suite: "mahjong-layout")
        defer { defaults.removePersistentDomain(forName: name) }

        let services = makeServices(log: log)
        for layout in [MahjongSolitaireLayout.turtle, .pyramid, .cross] {
            let model = MahjongSolitaireModel(services: services, layout: layout)
            for pair in model.solution {
                guard model.phase == .playing else { break }
                for index in pair { model.tap(index) }
            }
            #expect(model.phase == .won, "\(layout.displayName) を取り切れない")
            #expect(log.record(gameID: "mahjong", variant: layout.id)?.wins == 1,
                    "\(layout.displayName) の記録が別枠になっていない")
        }
        // 3 つのかたちが混ざらず 3 件として残る。
        #expect(log.records(gameID: "mahjong").count == 3)
    }

    @Test("麻雀ソリティア: 捨てた盤面は「＋の配り直し」も「手詰まりで最初から」も記録しない（#240）")
    func mahjongSolitaireDiscardedBoardsAreNotRecorded() {
        let (log, defaults, name) = makeLog(suite: "mahjong-discard")
        defer { defaults.removePersistentDomain(forName: name) }

        let services = makeServices(log: log)

        // ＋から配り直す経路。取りかけの盤面を捨てても通算成績には乗らない。
        let restarted = MahjongSolitaireModel(services: services, seed: 4001)
        for pair in restarted.solution.prefix(5) { for index in pair { restarted.tap(index) } }
        #expect(restarted.remainingCount == 134, "前提: 取りかけの盤面になっている")
        restarted.newGame()
        #expect(log.records(gameID: "mahjong").isEmpty, "配り直しは記録しない")

        // 手詰まりで「最初から」を選ぶ経路。#240 でこちらも記録しない側に揃えた。
        let gaveUp = MahjongSolitaireModel(services: services, seed: 4002)
        for pair in gaveUp.solution.prefix(5) { for index in pair { gaveUp.tap(index) } }
        gaveUp.giveUpAndRestart()
        #expect(
            log.records(gameID: "mahjong").isEmpty,
            "手詰まりでの配り直しも記録しない（＋からの配り直しと扱いを揃える）"
        )
    }

    @Test("数独: クリアで難易度別のタイムが記録される")
    func sudokuRecordsTimePerDifficulty() async {
        let (log, defaults, name) = makeLog(suite: "sudoku")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = SudokuModel(services: makeServices(log: log), seed: 555)
        await model.newGame(difficulty: .hard)
        for index in 0..<81 where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }

        #expect(model.state == .cleared)
        // 記録は難易度ごとに分かれる（マインスイーパーの難易度別と同じ扱い）。
        let record = log.record(gameID: "sudoku", variant: "hard")
        #expect(record?.metric == .shortestTime)
        #expect(record?.variantLabel == "むずかしい")
        #expect(record?.wins == 1)
        #expect(record?.bestSeconds != nil)
        #expect(log.record(gameID: "sudoku", variant: "easy") == nil, "別の難易度には混ざらない")
    }

    @Test("数独: 諦めた局のタイムは記録されない")
    func sudokuGiveUpDoesNotRecordTime() async {
        let (log, defaults, name) = makeLog(suite: "sudoku-giveup")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = SudokuModel(services: makeServices(log: log), seed: 556)
        await model.newGame(difficulty: .easy)
        model.giveUp()

        let record = log.record(gameID: "sudoku", variant: "easy")
        #expect(record?.losses == 1)
        #expect(record?.bestSeconds == nil, "クリアしていない局のタイムは自己ベストにしない")
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

    @Test("将棋: 投了で敗北が記録され、新規対局で前局の表示が消える")
    func shogiRecordsWinLoss() {
        let (log, defaults, name) = makeLog(suite: "shogi")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = ShogiGameModel(services: makeServices(log: log))
        model.resign()
        #expect(model.recordResult != nil)
        #expect(log.record(gameID: "shogi")?.losses == 1)
        #expect(log.record(gameID: "shogi")?.metric == .winLoss)
        #expect(log.summaryLine(gameID: "shogi") == "0勝1敗")

        // 新規対局に入ったら前局のリザルト表示は残さない
        model.newGame()
        #expect(model.recordResult == nil)
    }

    @Test("五目並べ: 投了で敗北が記録され、新規対局で前局の表示が消える")
    func gomokuRecordsWinLoss() {
        let (log, defaults, name) = makeLog(suite: "gomoku")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = GomokuModel(services: makeServices(log: log))
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(model.recordResult != nil)
        #expect(log.record(gameID: "gomoku")?.losses == 1)
        #expect(log.summaryLine(gameID: "gomoku") == "0勝1敗")

        model.newGame(humanSide: .black, aiLevel: 1)
        #expect(model.recordResult == nil)
    }

    @Test("神経衰弱: 対戦ものなので手数ではなく勝敗を記録する")
    func concentrationRecordsWinLoss() {
        let (log, defaults, name) = makeLog(suite: "concentration")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = ConcentrationModel(services: makeServices(log: log))
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        // 人が全ペアを取り切る（既存の ReviewRequestTests と同じ手順）
        for _ in 0..<model.cards.count where !model.isGameOver {
            let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
            guard let first = unmatched.first,
                  let second = unmatched.first(where: {
                      $0 != first && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            if model.firstFlippedIndex == nil { model.tap(index: first) }
            model.tap(index: second)
        }

        #expect(model.isGameOver)
        let record = log.record(gameID: "concentration")
        #expect(record?.metric == .winLoss)
        #expect(record?.wins == 1)
        // 対戦もののため手数は記録しない（受け入れ条件からの意図的な逸脱・PR の社長判断に記載）
        #expect(record?.fewestMoves == nil)
        #expect(log.summaryLine(gameID: "concentration") == "1勝0敗")
    }

    @Test("ポーカー: ラウンド終了時のチップが記録される")
    func pokerRecordsChips() {
        let (log, defaults, name) = makeLog(suite: "poker")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = PokerModel(services: makeServices(log: log))
        model.restartSession()
        model.startGame()
        model.bet1Action(.check)
        if model.phase == .exchange { model.confirmExchange() }
        if model.phase == .betting2 { model.bet2Action(.check) }
        if model.phase == .betting2, model.currentBet > 0 { model.callCPUBet() }

        #expect(model.phase == .result)
        let record = log.record(gameID: "poker")
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == model.playerChips)
        #expect(model.recordResult != nil)
    }

    @Test("大富豪: 中位フィニッシュ（引き分け扱い）でもハブに1行出る")
    func daifugoRecordsEvenWhenAllDraws() async {
        let (log, defaults, name) = makeLog(suite: "daifugo")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = DaifugoModel(services: makeServices(log: log), cpuDelay: .zero, seed: 2026)
        model.startGame()
        for _ in 0..<500 where model.phase == .playing {
            await model.runCPUTurnsIfNeeded()
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if let play = DaifugoRules.greedyPlay(
                hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
            ) {
                for card in play { model.toggleSelection(card) }
                model.playSelected()
            } else {
                model.pass()
            }
        }

        #expect(model.phase == .result)
        #expect(model.recordResult != nil)
        #expect(log.record(gameID: "daifugo")?.plays == 1)
        // 大富豪は「1位=勝ち / 最下位=負け / 中位=引き分け」。中位で終わっても記録は出す
        #expect(log.summaryLine(gameID: "daifugo") != nil)
    }

    @Test("四人打ち麻雀: 東風戦を終えると1プレイとして記録し、ハブに1行出る")
    func mahjongFourPlayerRecordsOncePerEastRound() async {
        let (log, defaults, name) = makeLog(suite: "mahjong4")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = MahjongModel(services: makeServices(log: log), cpuDelay: .zero, seed: 4649)
        model.startGame()
        await playMahjongFourPlayer(model)

        #expect(model.phase == .gameResult)
        #expect(model.recordResult != nil)
        // 東 1 局〜東 4 局まで打っても、記録は東風戦ごとに 1 プレイ。
        #expect(log.record(gameID: "mahjong4")?.plays == 1)
        #expect(log.summaryLine(gameID: "mahjong4") != nil)
    }

    @Test("2048: 広告コンティニューした回は1プレイとして数える（負けを二重に数えない）")
    func game2048ContinueDoesNotDoubleCount() {
        let (log, defaults, name) = makeLog(suite: "game2048Continue")
        defer { defaults.removePersistentDomain(forName: name) }

        let deadBoard = [
            [2, 2, 16, 32],
            [8, 4, 64, 8],
            [16, 8, 4, 64],
            [4, 16, 8, 32],
        ]
        let model = Game2048Model(services: makeServices(log: log), board: deadBoard)
        model.move(.left)
        #expect(model.gameOver)
        let scoreBeforeContinue = model.score
        #expect(log.record(gameID: "2048")?.plays == 1)

        // 広告を見て再開 → さっきの負けは無かったことになる。到達済みスコアは残る。
        model.continueAfterAd()
        #expect(!model.gameOver)
        #expect(model.recordResult == nil, "続きを遊ぶ間は前の終局の記録行を出さない")
        let afterContinue = log.record(gameID: "2048")
        #expect(afterContinue?.plays == 0)
        #expect(afterContinue?.losses == 0)
        #expect(afterContinue?.bestPoints == scoreBeforeContinue, "到達済みのスコアは取り消さない")

        // #122 の修正で、コンティニュー後は空きマス4が確保され続きを遊べるようになった。
        // 終局まで遊びきって、1プレイ分としてだけ記録されることを確認する。
        var moves = 0
        while !model.gameOver, moves < 10_000 {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(model.board, $0).moved
            }) else {
                Issue.record("終局していないのに動かせる方向が無い: \(model.board)")
                break
            }
            model.move(direction)
            moves += 1
        }
        #expect(model.gameOver)
        #expect(moves >= 4, "コンティニュー後は最低4手が保証される（実際は \(moves) 手）")

        let final = log.record(gameID: "2048")
        #expect(final?.plays == 1, "コンティニューを挟んでも1プレイとしてだけ数える")
        #expect(final?.losses == 1)
        #expect((final?.bestPoints ?? 0) >= scoreBeforeContinue, "続きで伸びたスコアが反映される")
    }

    @Test("マインスイーパー: コンティニューして勝った回は敗北として残らない")
    func minesweeperContinueDoesNotDoubleCount() {
        let (log, defaults, name) = makeLog(suite: "minesweeperContinue")
        defer { defaults.removePersistentDomain(forName: name) }

        let model = MinesweeperModel(services: makeServices(log: log))
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        guard let mine = model.cells.indices.flatMap({ r in
            model.cells[r].indices.map { (r, $0) }
        }).first(where: { model.cells[$0.0][$0.1].isMine }) else {
            Issue.record("地雷が見つからない")
            return
        }
        model.tap(row: mine.0, col: mine.1)
        #expect(model.gameState == .lost)
        #expect(log.record(gameID: "minesweeper", variant: "9x9-10")?.losses == 1)

        model.continueAfterAd()
        #expect(model.gameState == .playing)
        let afterContinue = log.record(gameID: "minesweeper", variant: "9x9-10")
        #expect(afterContinue?.losses == 0)
        #expect(afterContinue?.plays == 0)

        // 続きを開けきってクリア
        for r in 0..<9 {
            for c in 0..<9 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }
        #expect(model.gameState == .won)
        let final = log.record(gameID: "minesweeper", variant: "9x9-10")
        #expect(final?.plays == 1)
        #expect(final?.losses == 0, "コンティニューして勝った回は敗北として残らない")
        #expect(final?.wins == 1)
    }

    @Test("将棋: 終局の検討画面を再起動でも開き直すと、記録行は出るが二重に数えない")
    func shogiRestoredReviewShowsRecordWithoutRecounting() {
        let (log, defaults, name) = makeLog(suite: "shogiRestore")
        defer { defaults.removePersistentDomain(forName: name) }

        let snapshots = MemorySnapshotStore()
        let services = GameServices(snapshots: snapshots, ads: NoopAdService(), playLog: log)

        let model = ShogiGameModel(services: services)
        model.resign()
        #expect(log.record(gameID: "shogi")?.losses == 1)

        // 「再起動」— 同じスナップショットから作り直す
        let reopened = ShogiGameModel(services: services)
        #expect(reopened.gameOver)
        #expect(reopened.recordResult != nil, "検討画面に戻っても記録行は出す")
        #expect(reopened.recordResult?.update.isNewBest == false, "更新の瞬間は過ぎているのでバッジは出さない")
        #expect(log.record(gameID: "shogi")?.losses == 1, "復元では記録し直さない")
        #expect(log.record(gameID: "shogi")?.plays == 1)
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

/// 四人打ち麻雀: 常に自摸切り・和了できるときは必ず和了する方針で東風戦を最後まで進める。
/// CPU の間合いは 0 なので実時間は待たない。
@MainActor
private func playMahjongFourPlayer(_ model: MahjongModel, rejectOnce: Bool = false) async {
    var didReject = !rejectOnce
    var guardCount = 0
    while model.phase != .gameResult, guardCount < 800 {
        guardCount += 1
        switch model.phase {
        case .playing:
            if model.currentPlayer == MahjongModel.humanIndex, let drawn = model.drawnTile {
                if !didReject {
                    didReject = true
                    // 手牌にもツモ牌にも無い牌を指定すると拒否される（警告の発火を確かめる）。
                    let absent = MahjongTileOrder.all.first {
                        model.playerHand.count(of: $0) == 0 && $0 != drawn
                    }
                    if let absent { model.discard(absent) }
                }
                if model.canDeclareTsumo {
                    model.declareTsumo()
                } else {
                    model.discard(drawn)
                }
            } else {
                await model.runCPUTurnsIfNeeded()
            }
        case .ronOffer:
            model.declareRon()
        case .callOffer:
            // この通しテストは「常に自摸切り」の方針なので鳴かない。
            model.declineCall()
        case .handResult:
            model.advanceToNextHand()
        case .idle, .gameResult:
            return
        }
    }
}
