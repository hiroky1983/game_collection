import Core
import Foundation
import Testing
@testable import GameBlocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private(set) var saveCount = 0
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        saveCount += 1
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 既定オフ・使い捨ての設定。`UserDefaults.standard` を汚さない。
private func makePreference(_ suite: String) -> FeedbackPreference {
    let name = "asobiba.blocks.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
}

/// Game Center へ実際に送られたものを記録するスパイ。
private final class SpyGameCenterService: GameCenterService, @unchecked Sendable {
    var scores: [GameCenterScore] = []
    @MainActor func submit(_ score: GameCenterScore) { scores.append(score) }
    @MainActor func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
}

@MainActor
private func makeServices(
    store: SnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    gameCenter: GameCenterService? = nil
) -> GameServices {
    GameServices(
        snapshots: store,
        ads: NoopAdService(),
        playLog: log,
        gameCenter: gameCenter.map {
            GameCenterReporter(service: $0, allowedGameIDs: [BlocksModel.gameID])
        }
    )
}

/// 球を落として 1 機失わせる。実際のフレーム進行を通すので、落球の扱いをそのまま検証できる。
@MainActor
private func dropBall(_ model: BlocksModel) {
    model.movePaddle(to: 5)
    model.launch()
    // パドルから最も遠い側の、パドルより下の高さへ置いて落とす。
    model.placeBallForTesting(x: 95, y: 6, vx: 0, vy: -60)
    for _ in 0..<60 where model.phase == .playing {
        model.tick(dt: 1.0 / 60)
    }
}

/// いまのステージのブロックを全部消してクリアさせる。
@MainActor
private func clearStage(_ model: BlocksModel) {
    var guardCount = 0
    while !model.field.isCleared, guardCount < 4_000 {
        guardCount += 1
        if model.phase == .ready { model.launch() }
        guard model.phase == .playing else { break }
        guard let target = firstBreakable(model.field) else { break }
        let rect = BlocksField.blockRect(row: target.row, column: target.column)
        // **狙ったブロックの中心へ置く**。真下に置くと 1 つ下の段のブロックに深く重なり、
        // そちらが「いちばん近い」として先に解決される（下段が壊れないブロックだと
        // 永久に当たらない）。矩形は重ならないので、中心にいるあいだ候補は必ず 1 個。
        model.placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
        model.tick(dt: 1.0 / 60)
    }
}

private func firstBreakable(_ field: BlocksField) -> (row: Int, column: Int)? {
    for row in 0..<field.rowCount {
        for column in 0..<BlocksField.Metrics.columns
        where field.block(row: row, column: column)?.isBreakable == true {
            return (row, column)
        }
    }
    return nil
}

@Suite("ブロック崩しの進行")
@MainActor
struct ModelTests {

    // MARK: - 開始

    @Test("最初はステージ1・残機3・発射前")
    func startsAtStageOne() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("start"))
        #expect(model.stageNumber == 1)
        #expect(model.lives == BlocksRules.initialLives)
        #expect(model.score == 0)
        #expect(model.phase == .ready)
        #expect(!model.continueUsed)
    }

    @Test("発射すると進行中になる")
    func launchStartsPlaying() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("launch"))
        model.launch()
        #expect(model.phase == .playing)
        #expect(model.field.ball.isMoving)
    }

    @Test("発射前は tick で何も進まない")
    func tickDoesNothingBeforeLaunch() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("idle"))
        let before = model.field
        model.tick(dt: 1)
        #expect(model.field == before)
    }

    // MARK: - 残機とゲームオーバー

    @Test("落球すると残機が1減り、発射前へ戻る")
    func losingBallCostsALife() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("life"))
        dropBall(model)
        #expect(model.lives == BlocksRules.initialLives - 1)
        #expect(model.phase == .ready)
        #expect(!model.field.ball.isMoving, "球はパドルの上へ戻る")
    }

    @Test("残機を使い切るとゲームオーバー")
    func runningOutOfLivesEndsTheGame() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("gameover")
        )
        dropBall(model)
        #expect(model.lives == 0)
        #expect(model.phase == .gameOver)
        #expect(model.phase.isFinished)
    }

    @Test("ゲームオーバー後は tick でも操作でも動かない")
    func frozenAfterGameOver() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("frozen")
        )
        dropBall(model)
        let before = model.field
        model.launch()
        model.tick(dt: 1)
        model.movePaddle(to: 80)
        #expect(model.phase == .gameOver)
        #expect(model.field == before)
    }

    // MARK: - ステージ進行

    @Test("全部消すとステージクリアになり、次のステージへ進める")
    func clearingAdvancesStage() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("stage"))
        clearStage(model)
        #expect(model.phase == .stageCleared)
        #expect(model.stageNumber == 1)

        model.advanceToNextStage()
        #expect(model.stageNumber == 2)
        #expect(model.phase == .ready)
        #expect(!model.field.isCleared, "次のステージの盤が組まれている")
        #expect(model.field.speed > BlocksStage.all[0].ballSpeed, "ステージが進むと速くなる")
    }

    @Test("クリアするとステージボーナスが入る")
    func stageClearGivesBonus() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("bonus"))
        clearStage(model)
        let blocks = BlocksStage.all[0].rows.joined().filter { $0 == "n" }.count
        let expected = blocks * BlocksScoring.normalDestroyedPoints
            + BlocksScoring.stageClearBonus(stage: 1, remainingLives: BlocksRules.initialLives)
        #expect(model.score == expected)
    }

    @Test("最終ステージをクリアすると全クリアで終わる")
    func clearingFinalStageWins() {
        let model = BlocksModel(
            services: makeServices(),
            startingAt: BlocksRules.stageCount,
            preference: makePreference("allclear")
        )
        clearStage(model)
        #expect(model.phase == .allCleared)
        #expect(model.phase.isFinished)
        // 最終ステージからは進めない。
        model.advanceToNextStage()
        #expect(model.stageNumber == BlocksRules.stageCount)
    }

    // MARK: - 一時停止

    @Test("いつでも一時停止でき、止めた状態へ戻る")
    func pauseAndResume() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("pause"))
        // 発射前に止めたら、再開しても発射前のまま。
        model.pause()
        #expect(model.phase == .paused)
        model.resume()
        #expect(model.phase == .ready)

        model.launch()
        model.pause()
        #expect(model.phase == .paused)
        let before = model.field
        model.tick(dt: 0.5)
        #expect(model.field == before, "止めているあいだ球は進まない")
        model.resume()
        #expect(model.phase == .playing)
    }

    @Test("描画ループが要るのは発射前と進行中だけ（#522）")
    func animationFramesOnlyWhileMoving() {
        // 発射前は球こそ止まっているが、パドルがドラッグに追従する。
        #expect(BlocksPhase.ready.needsAnimationFrames)
        #expect(BlocksPhase.playing.needsAnimationFrames)
        // ここから下は画面の中身が動かない。回し続けると電池を使うだけになる。
        #expect(!BlocksPhase.paused.needsAnimationFrames)
        #expect(!BlocksPhase.stageCleared.needsAnimationFrames)
        #expect(!BlocksPhase.gameOver.needsAnimationFrames)
        #expect(!BlocksPhase.allCleared.needsAnimationFrames)
    }

    @Test("一時停止で描画ループが止まり、再開すると戻る（#522）")
    func animationFramesStopWhilePaused() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("frames"))
        model.launch()
        #expect(model.phase.needsAnimationFrames)
        model.pause()
        #expect(!model.phase.needsAnimationFrames)
        model.resume()
        #expect(model.phase.needsAnimationFrames)
    }

    @Test("ゲームオーバーの表示中は描画ループが止まる（#522）")
    func animationFramesStopAfterGameOver() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("framesover")
        )
        dropBall(model)
        #expect(model.phase == .gameOver)
        #expect(!model.phase.needsAnimationFrames)
    }

    @Test("決着後は一時停止できない")
    func cannotPauseAfterFinish() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("pausefinished")
        )
        dropBall(model)
        model.pause()
        #expect(model.phase == .gameOver)
    }

    // MARK: - ゆっくりモード

    @Test("ゆっくりモードで球が遅くなり、戻すと元に戻る")
    func slowModeChangesSpeed() {
        let preference = makePreference("slow")
        let model = BlocksModel(services: makeServices(), preference: preference)
        let normal = model.field.speed
        model.launch()

        model.setSlowMode(true)
        #expect(model.isSlowMode)
        #expect(abs(model.field.speed - normal * BlocksRules.slowFactor) < 1e-9)
        #expect(abs(model.field.ball.speed - normal * BlocksRules.slowFactor) < 1e-9,
                "進行中の球にも即座に効く")
        #expect(preference.isEnabled, "設定に保存される")

        model.setSlowMode(false)
        #expect(abs(model.field.speed - normal) < 1e-9)
        #expect(!preference.isEnabled)
    }

    @Test("ゆっくりモードは既定オフで、保存されていれば次に開いたときも効く")
    func slowModePersists() {
        let preference = makePreference("slowpersist")
        #expect(!BlocksModel(services: makeServices(), preference: preference).isSlowMode)

        preference.isEnabled = true
        let restored = BlocksModel(services: makeServices(), preference: preference)
        #expect(restored.isSlowMode)
        #expect(abs(restored.field.speed - BlocksStage.all[0].ballSpeed * BlocksRules.slowFactor) < 1e-9)
    }

    @Test("設定画面での変更を取り込める")
    func syncsSlowModeFromPreference() {
        let preference = makePreference("slowsync")
        let model = BlocksModel(services: makeServices(), preference: preference)
        #expect(!model.isSlowMode)
        preference.isEnabled = true
        model.syncSlowModeFromPreference()
        #expect(model.isSlowMode)
    }

    // MARK: - 中断復元

    @Test("保存されるのは区切りだけ（フレームごとには保存しない）")
    func savesOnlyAtCheckpoints() {
        let store = MemorySnapshotStore()
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("snapshot")
        )
        let afterInit = store.saveCount
        #expect(afterInit == 1, "開始時に 1 回だけ保存する")

        model.launch()
        for _ in 0..<120 { model.tick(dt: 1.0 / 60) }
        #expect(store.saveCount == afterInit, "遊んでいるあいだは保存し直さない")

        clearStage(model)
        #expect(store.saveCount == afterInit + 1, "クリアの区切りで 1 回だけ保存する")
        model.advanceToNextStage()
        #expect(store.saveCount == afterInit + 2, "次のステージの頭で 1 回だけ保存する")
        #expect(store.load(BlocksSnapshot.self, for: BlocksModel.gameID)?.stage == 2)
    }

    /// 落球のたびに保存し直す（#508）。
    ///
    /// ステージ頭のまま放っておくと、落球するたび強制終了すれば残機がステージ頭へ戻り、
    /// 広告コンティニュー（残機 1・順位表の資格喪失）より条件の良い抜け道になる。
    @Test("残機を1つ失ったら中断データを更新する（#508）")
    func savesOnLosingALife() {
        let store = MemorySnapshotStore()
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("lifesave")
        )
        dropBall(model)
        #expect(model.lives == BlocksRules.initialLives - 1, "実際に 1 機失っている")
        let saved = store.load(BlocksSnapshot.self, for: BlocksModel.gameID)
        #expect(saved?.lives == BlocksRules.initialLives - 1,
                "落球後の残機が保存されていない（強制終了で復活できてしまう）")
        #expect(saved?.stage == model.stageNumber)
    }

    /// クリア表示中に中断しても、**次のステージ頭**として保存する（#508）。
    ///
    /// 表示中のステージ番号のまま保存すると、崩し終えたステージをボーナス込みの得点で
    /// もう一度遊べてしまう（強制終了で得点を伸ばせる抜け道になる）。
    @Test("クリア表示中の中断データは次のステージ頭として保存される（#508）")
    func stageClearedSavesNextStage() {
        let store = MemorySnapshotStore()
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("clearsave")
        )
        clearStage(model)
        #expect(model.phase == .stageCleared)
        let saved = store.load(BlocksSnapshot.self, for: BlocksModel.gameID)
        #expect(saved?.stage == 2, "進み先で保存されていない")
        #expect(saved?.score == model.score, "クリアボーナス込みの得点で保存する")
    }

    /// 同じ 1 フレームの中でステージクリアと落球が続けて起きても、残機を減らさない。
    ///
    /// `tick` のイベント処理は `guard phase == .playing else { break }` で打ち切っている。
    /// この打ち切りが無いと、最後のブロックを壊した球がそのまま落ちたときに
    /// **クリアしたのに 1 機失う**。現行のステージ配置ではこの並びに自然到達しないため、
    /// 球の状態を直接置いて再現する。
    @Test("同じフレームでクリアと落球が続いても残機は減らない")
    func stopsProcessingEventsAfterStageClear() {
        let store = MemorySnapshotStore()
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("clearthenlost")
        )
        model.launch()
        // 最後の 1 個を残して崩す。
        var guardCount = 0
        while model.field.remainingBreakableCount > 1, guardCount < 4_000 {
            guardCount += 1
            guard let target = firstBreakable(model.field) else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            model.placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.field.remainingBreakableCount == 1)

        // 最後の 1 個へ、1 フレームで床まで到達する速さの球を真上から撃ち込む。
        let last = firstBreakable(model.field)!
        let rect = BlocksField.blockRect(row: last.row, column: last.column)
        model.movePaddle(to: 5)   // パドルは反対側に置いて拾わせない
        model.placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: -6_000)
        model.tick(dt: BlocksRules.maxStep)

        #expect(model.phase == .stageCleared, "クリアで止まっていない（phase: \(model.phase)）")
        #expect(model.lives == BlocksRules.initialLives, "クリアしたのに残機が減っている")
    }

    @Test("続きからはステージの頭・そのステージ開始時点の残機とスコアで再開する")
    func restoresFromStageHead() {
        let store = MemorySnapshotStore()
        try? store.save(
            BlocksSnapshot(stage: 4, score: 1_234, lives: 2, continueUsed: true),
            for: BlocksModel.gameID
        )
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("restore")
        )
        #expect(model.stageNumber == 4)
        #expect(model.score == 1_234)
        #expect(model.lives == 2)
        #expect(model.continueUsed, "再起動でコンティニュー権は復活しない")
        #expect(model.phase == .ready)
        #expect(model.field.remainingBreakableCount > 0, "ステージ4の盤が頭から組まれている")
    }

    @Test("決着すると中断データを捨てる")
    func clearsSnapshotOnFinish() {
        let store = MemorySnapshotStore()
        let model = BlocksModel(
            services: makeServices(store: store), startingAt: 1, lives: 1, preference: makePreference("clear")
        )
        #expect(store.exists(for: BlocksModel.gameID))
        dropBall(model)
        #expect(!store.exists(for: BlocksModel.gameID))
    }

    @Test("壊れた中断データは無視して最初から始める")
    func ignoresBrokenSnapshot() {
        let store = MemorySnapshotStore()
        try? store.save(["nonsense": 1], for: BlocksModel.gameID)
        let model = BlocksModel(
            services: makeServices(store: store), preference: makePreference("broken")
        )
        #expect(model.stageNumber == 1)
        #expect(model.lives == BlocksRules.initialLives)
    }

    @Test("範囲外のステージ番号は丸めて復元する")
    func clampsStageNumber() {
        let store = MemorySnapshotStore()
        try? store.save(
            BlocksSnapshot(stage: 999, score: 0, lives: 3, continueUsed: false),
            for: BlocksModel.gameID
        )
        #expect(
            BlocksModel(services: makeServices(store: store), preference: makePreference("clamp"))
                .stageNumber == BlocksRules.stageCount
        )
    }

    // MARK: - コンティニュー

    @Test("コンティニューは残機1で、落ちたステージの頭から再開する")
    func continueRestartsCurrentStage() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 3, score: 500, lives: 1,
            preference: makePreference("continue")
        )
        dropBall(model)
        #expect(model.phase == .gameOver)

        #expect(model.continueAfterAd(forRun: model.fieldGeneration))
        #expect(model.phase == .ready)
        #expect(model.lives == BlocksRules.continueLives)
        #expect(model.stageNumber == 3, "落ちたステージのまま")
        #expect(model.score == 500, "スコアは引き継ぐ")
        #expect(model.continueUsed)
        #expect(!model.field.isCleared, "盤が頭から組み直されている")
    }

    @Test("コンティニューは1プレイにつき1回だけ")
    func continueOnlyOnce() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("continueonce")
        )
        dropBall(model)
        #expect(model.continueAfterAd(forRun: model.fieldGeneration))
        dropBall(model)
        #expect(model.phase == .gameOver)
        #expect(!model.continueAfterAd(forRun: model.fieldGeneration))
        #expect(model.phase == .gameOver, "2 回目は効かない")
    }

    @Test("ゲームオーバーでないときはコンティニューできない")
    func cannotContinueWhilePlaying() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("continuemid"))
        model.launch()
        #expect(!model.continueAfterAd(forRun: model.fieldGeneration))
        #expect(model.phase == .playing)
        #expect(!model.continueUsed)
    }

    /// 広告のロード〜視聴の間に「はじめから」で盤が作り直されたら、報酬は適用しない（#509）。
    ///
    /// 照合しないと、視聴完了の報酬が**別の局**に乗って `cancelLoss` まで走る
    /// （ソリティアの `grantUndos(forDeal:)` と同じ契約）。
    @Test("広告中に盤が作り直されたらコンティニューは適用されない（#509）")
    func continueIsRejectedAfterRunChanges() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, lives: 1, preference: makePreference("continuerun")
        )
        dropBall(model)
        #expect(model.phase == .gameOver)
        let run = model.fieldGeneration

        // 広告を見ている間に「はじめから」→ また残機を使い切ってゲームオーバー。
        model.newGame()
        dropBall(model)
        dropBall(model)
        dropBall(model)
        #expect(model.phase == .gameOver, "検証の前提: 2 局目もゲームオーバーになっている")

        #expect(!model.continueAfterAd(forRun: run), "別の局への報酬が適用されている")
        #expect(!model.continueUsed)
        #expect(model.phase == .gameOver)
        // いまの局の連番なら通る。
        #expect(model.continueAfterAd(forRun: model.fieldGeneration))
    }

    @Test("コンティニューを使うと、その回の記録は世界の順位表へ送らない（自己ベストには残る）")
    func continueMakesScoreIneligibleForLeaderboard() {
        let spy = SpyGameCenterService()
        let (log, _, _) = makeLog(suite: "leaderboard")
        let model = BlocksModel(
            services: makeServices(log: log, gameCenter: spy), startingAt: 1, score: 900, lives: 1,
            preference: makePreference("leaderboard")
        )
        dropBall(model)
        #expect(model.continueAfterAd(forRun: model.fieldGeneration))
        spy.scores.removeAll()   // コンティニュー**前**の送信は対象外
        // コンティニュー後に改めてゲームオーバーまで落とす。
        dropBall(model)
        #expect(model.phase == .gameOver)
        // 自己ベストは残る。
        #expect(log.record(gameID: BlocksModel.gameID)?.bestPoints == 900)
        // **実際に送られたもの**を見る。`GameScore` を自分で組み立てて
        // `GameCenterLeaderboard.score` に掛けても、Model が何を渡したかは分からず素通りする。
        #expect(spy.scores.isEmpty, "広告コンティニューを使った回が順位表へ送られている: \(spy.scores)")
    }

    @Test("コンティニューを使っていなければスコアを順位表へ送る")
    func submitsScoreToLeaderboard() {
        let spy = SpyGameCenterService()
        let model = BlocksModel(
            services: makeServices(gameCenter: spy), startingAt: 1, score: 900, lives: 1,
            preference: makePreference("leaderboardplain")
        )
        dropBall(model)
        #expect(model.phase == .gameOver)
        #expect(spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.blocksScore])
        #expect(spy.scores.first?.value == 900)
    }

    // MARK: - はじめから

    @Test("はじめからでステージ1・残機3・スコア0に戻る")
    func newGameResetsEverything() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 5, score: 4_000, lives: 1,
            continueUsed: true, preference: makePreference("newgame")
        )
        let generation = model.fieldGeneration
        model.newGame()
        #expect(model.stageNumber == 1)
        #expect(model.score == 0)
        #expect(model.lives == BlocksRules.initialLives)
        #expect(!model.continueUsed)
        #expect(model.phase == .ready)
        #expect(model.fieldGeneration > generation, "描画側が盤を作り直せるよう連番が進む")
    }

    @Test("開始直後は「はじめから」で失うものが無い")
    func noProgressToLoseAtStart() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("progress-start"))
        #expect(!model.hasProgressToLose)
    }

    @Test("発射したら「はじめから」に確認が要る")
    func playingHasProgressToLose() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("progress-play"))
        model.launch()
        #expect(model.hasProgressToLose)
    }

    @Test("得点が付いていれば一時停止中でも確認が要る")
    func scoreKeepsProgressWhilePaused() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, score: 120,
            preference: makePreference("progress-score")
        )
        model.launch()
        model.pause()
        #expect(model.phase == .paused)
        #expect(model.hasProgressToLose)
    }

    @Test("ステージ2以降は発射前でも確認が要る")
    func laterStageHasProgressToLose() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 3, preference: makePreference("progress-stage")
        )
        #expect(model.phase == .ready)
        #expect(model.hasProgressToLose)
    }

    @Test("決着後は得点が残っていても確認を挟まない")
    func finishedGameHasNothingToLose() {
        let model = BlocksModel(
            services: makeServices(), startingAt: 1, score: 900, lives: 1,
            preference: makePreference("progress-gameover")
        )
        dropBall(model)
        #expect(model.phase == .gameOver)
        #expect(!model.hasProgressToLose)
    }

    @Test("ステージ1で崩し終えてから「はじめから」を選んでも盤が組み直される")
    func newGameRebuildsEvenOnSameStage() {
        let model = BlocksModel(services: makeServices(), preference: makePreference("rebuild"))
        clearStage(model)
        #expect(model.field.isCleared)
        let generation = model.fieldGeneration
        model.newGame()
        #expect(!model.field.isCleared)
        #expect(model.fieldGeneration > generation)
    }
}

@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.blocks.playlog.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}
