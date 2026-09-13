import Core
import Foundation
import Testing
@testable import GameRunner

/// エンドレスモードのコース生成（#675）。
///
/// 生成器は置く前に成立条件を判定する（`RunnerEndlessCourse.canPlace`）が、ここでは
/// **生成したコースを独立に検め直す**。判定式はステージ制の `RunnerStageTests` と同じ物差し
/// （弾道は `RunnerRules`、踏み切りは `RunnerAutoPilot.lead`）で書き、生成器より厳しい速さの
/// 幅（区画 1 つ手前の遅い速さ／2 区画先の速い速さ）で見る。
@Suite("チャリンコおじさん: エンドレスのコース生成")
struct RunnerEndlessCourseTests {
    private static let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
    /// 受け入れ条件「1,000 種で生成した全コースが成立条件を満たす」の種の数。
    private static let seedCount: UInt64 = 1_000

    @Test("同じ種なら同じコース、違う種なら違うコース")
    func sameSeedSameCourse() {
        #expect(RunnerEndlessCourse.pattern(seed: 42) == RunnerEndlessCourse.pattern(seed: 42))
        #expect(RunnerEndlessCourse.makeStage(seed: 7) == RunnerEndlessCourse.makeStage(seed: 7))
        let patterns = Set((1...20).map { RunnerEndlessCourse.pattern(seed: UInt64($0)) })
        #expect(patterns.count == 20, "種が違えばコースも違う（冒頭だけ同じ）")
    }

    /// 「最初の数区画は毎回同じ」（会長決裁）。導入はステージ 1 と同じ並びで、
    /// 別の導入を書きたくなったらここを直す。
    @Test("冒頭はステージ 1 と同じ固定パターンで、以降がランダム")
    func introIsFixedAndMatchesStageOne() {
        #expect(RunnerEndlessCourse.intro == RunnerStage.all[0].pattern)
        for seed in 1...Self.seedCount {
            let pattern = RunnerEndlessCourse.pattern(seed: seed)
            #expect(pattern.hasPrefix(RunnerEndlessCourse.intro), "種 \(seed) の冒頭が固定パターンでない")
        }
    }

    @Test("固定長 400 区画で、先頭と末尾の 2 区画は平地")
    func hasFixedLengthAndClearance() {
        #expect(RunnerRules.endlessSegments == 400)
        for seed in 1...Self.seedCount {
            let stage = RunnerEndlessCourse.makeStage(seed: seed)
            #expect(stage.pattern.count == RunnerRules.endlessSegments, "種 \(seed) の区画数")
            #expect(stage.pattern.hasPrefix("--") && stage.pattern.hasSuffix("--"), "種 \(seed) の余白")
            #expect(stage.number == 0, "本番のステージ番号を名乗らない")
        }
    }

    /// 受け入れ条件「1,000 種で生成した全コースが成立条件を満たす」。
    @Test("1,000 種すべてのコースがステージ制と同じ成立条件を満たす")
    func everySeedSatisfiesLayoutRules() {
        for seed in 1...Self.seedCount {
            expectSatisfiesLayoutRules(RunnerEndlessCourse.makeStage(seed: seed), seed: seed)
        }
    }

    /// 部品は岩・穴・鳥・アイテム・台座・床のすべて（Issue #675「部品」）。解禁距離があるので
    /// 1 本の中に全部出るとは限らないが、100 種も回せば全種類が出る。
    @Test("岩・穴・鳥・アイテム・台座・床のすべてが生成に使われる")
    func allPartsAppear() {
        var seen: Set<Character> = []
        for seed in 1...100 as ClosedRange<UInt64> {
            seen.formUnion(RunnerEndlessCourse.pattern(seed: seed))
        }
        #expect(seen == ["-", "1", "2", "3", "n", "t", "b", "s", "P", "="], "出ていない記号がある: \(seen)")
    }

    // MARK: - 難易度カーブ

    /// 受け入れ条件「距離に応じて速くなり障害が増える」。距離 0 と 5,000 で単調増加。
    @Test("距離 0 と 5,000 で速さと密度が単調増加し、どちらも上限で頭打ちになる")
    func difficultyRampsWithDistance() {
        #expect(RunnerEndlessCourse.speed(atDistance: 0) == RunnerRules.baseSpeed)
        #expect(RunnerEndlessCourse.speed(atDistance: 5_000) > RunnerEndlessCourse.speed(atDistance: 0))
        #expect(RunnerEndlessCourse.hazardDensity(atDistance: 5_000) > RunnerEndlessCourse.hazardDensity(atDistance: 0))
        var previousSpeed = 0.0
        var previousDensity = 0.0
        for distance in stride(from: 0.0, through: 30_000, by: 500) {
            let speed = RunnerEndlessCourse.speed(atDistance: distance)
            let density = RunnerEndlessCourse.hazardDensity(atDistance: distance)
            #expect(speed >= previousSpeed && density >= previousDensity, "距離 \(distance) で下がっている")
            #expect(speed <= RunnerRules.endlessMaxSpeed && density <= 1, "距離 \(distance) で上限を超えている")
            previousSpeed = speed
            previousDensity = density
        }
        #expect(previousSpeed == RunnerRules.endlessMaxSpeed, "終盤は上限に達する")
        // `makeStage` が作るステージの `speed(at:)` も同じ式。
        let stage = RunnerEndlessCourse.makeStage(seed: 1)
        for distance in [0.0, 1_000, 5_000, 20_000, 30_000] {
            #expect(abs(stage.speed(at: distance) - RunnerEndlessCourse.speed(atDistance: distance)) < 1e-9)
        }
    }

    /// 密度の上がり方が生成結果にも出ていること（確率の式だけでなく、実際に後半のほうが密）。
    @Test("生成したコースは冒頭より終盤のほうが障害が多い")
    func generatedCoursesGetDenser() {
        var early = 0
        var late = 0
        for seed in 1...100 as ClosedRange<UInt64> {
            let symbols = Array(RunnerEndlessCourse.pattern(seed: seed))
            early += symbols[12..<112].filter { RunnerStage.segmentSpec($0) != nil }.count
            late += symbols[298..<398].filter { RunnerStage.segmentSpec($0) != nil }.count
        }
        #expect(Double(late) > Double(early) * 1.5, "冒頭 \(early) 個 / 終盤 \(late) 個")
    }

    /// 速さの上限そのものが成立条件の内側にあること（`RunnerRules.endlessMaxSpeed` のドキュメント）。
    /// 隣り合う区画に**どの組み合わせで**障害が並んでも、着地して踏み切り直せる。
    @Test("速さの上限でも、隣り合う区画に並んだ障害の間に着地の余白がある")
    func maxSpeedKeepsAdjacentHazardsPassable() {
        let speed = RunnerRules.endlessMaxSpeed
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        for previous in ["1", "2", "3", "n", "t", "b"] {
            for next in ["1", "2", "3", "n", "t", "b"] {
                guard let a = RunnerStage.segmentSpec(Character(previous)),
                      let b = RunnerStage.segmentSpec(Character(next)) else { continue }
                let first = RunnerHazard(kind: a.kind, start: offset, length: Double(a.tiles) * RunnerRules.tileWidth)
                let second = RunnerHazard(
                    kind: b.kind, start: Self.segmentWidth + offset, length: Double(b.tiles) * RunnerRules.tileWidth
                )
                #expect(
                    RunnerEndlessCourse.canPlace(second, after: first, speedBefore: speed, speedAfter: speed),
                    "\(previous) の隣に \(next) を置けない"
                )
            }
        }
    }

    // MARK: - 成立条件（`RunnerStageTests` と同じ物差し）

    /// タップ（踏み切って即離す）の弾道の標本。`RunnerPlaythroughTests.tapFlight` と同じ測り方。
    private static let tapFlight: [Double] = {
        var field = RunnerField(stage: RunnerStage(number: 1, pattern: "----", speed: 40))
        field.jump()
        field.endHold()
        var samples: [Double] = []
        while !field.isGrounded, samples.count < 6000 {
            _ = field.step(dt: tapSampleDT)
            samples.append(field.altitude)
        }
        return samples
    }()
    private static let tapSampleDT = 1.0 / 600
    private static var tapAirTime: Double { Double(tapFlight.count) * tapSampleDT }
    private static func tapTime(above height: Double) -> Double {
        Double(tapFlight.filter { $0 >= height }.count) * tapSampleDT
    }

    /// 1 本のコースを、ステージ制の成立条件で検める。
    ///
    /// 速さは距離で上がるので、越えられるかは**手前の遅い**速さ（`low`）で、間隔・鳥の前後は
    /// **先の速い**速さ（`high`）で判定する。どちらも生成器が使う幅より外側を取る。
    private func expectSatisfiesLayoutRules(_ stage: RunnerStage, seed: UInt64) {
        let halfWidth = RunnerField.Metrics.playerHalfWidth
        func low(_ hazard: RunnerHazard) -> Double { stage.speed(at: hazard.start - Self.segmentWidth) }
        func high(_ hazard: RunnerHazard) -> Double { stage.speed(at: hazard.end + Self.segmentWidth * 2) }

        // 記号。
        let symbols = Array(stage.pattern)
        for symbol in symbols where symbol != "-" {
            let isKnown = RunnerStage.segmentSpec(symbol) != nil
                || symbol == RunnerStage.pickupSymbol
                || symbol == RunnerStage.platformSymbol
                || symbol == RunnerStage.boostFloorSymbol
            #expect(isKnown, "種 \(seed): 未知の記号 '\(symbol)'")
        }

        // 障害 1 つずつ: 押さないジャンプで越えられる（鳥は接地でくぐれる）。穴は最大 3 タイル表記（4 タイル幅）。
        for hazard in stage.hazards {
            let speed = low(hazard)
            switch hazard.kind {
            case .pit:
                #expect(hazard.length <= 4 * RunnerRules.tileWidth, "種 \(seed): 穴が広すぎる（\(hazard.length)）")
                let needed = RunnerAutoPilot.lead(for: hazard, speed: speed) + hazard.length
                #expect(
                    speed * RunnerRules.jumpAirTime > needed + RunnerRules.tileWidth,
                    "種 \(seed): \(hazard.start) の穴（\(hazard.length)）が跳び越せない"
                )
                // 瞬間タップでも渡れる（`RunnerPlaythroughTests.instantTapClearsPitsAndLowBlocks` と同じ境目）。
                #expect(
                    speed * Self.tapAirTime > hazard.length + halfWidth + RunnerRules.tileWidth,
                    "種 \(seed): \(hazard.start) の穴（\(hazard.length)）を瞬間タップで渡れない（速さ \(speed)）"
                )
            case .lowBlock, .tallBlock:
                let overlap = (hazard.length + halfWidth * 2) / speed
                #expect(
                    RunnerRules.airTime(above: hazard.height + RunnerAutoPilot.clearance) > overlap,
                    "種 \(seed): \(hazard.start) の障害物（高さ \(hazard.height)）を越えきれない"
                )
                #expect(hazard.height < RunnerRules.jumpApex)
                if hazard.kind == .lowBlock {
                    #expect(
                        Self.tapTime(above: hazard.height + RunnerAutoPilot.clearance) > overlap,
                        "種 \(seed): \(hazard.start) の低い障害物を瞬間タップで越えられない"
                    )
                }
            case .bird:
                #expect(hazard.bottom > RunnerField.Metrics.playerHeight)
                #expect(hazard.bottom - RunnerField.Metrics.playerHeight < RunnerRules.jumpApex)
            }
        }

        // 隣り合う障害の間隔と、鳥の前後。
        for (previous, next) in zip(stage.hazards, stage.hazards.dropFirst()) {
            let speed = high(next)
            let needed = speed * RunnerRules.jumpAirTime + RunnerAutoPilot.lead(for: next, speed: speed)
            #expect(next.start - previous.start > needed, "種 \(seed): \(previous.start) と \(next.start) が近すぎる")
            if next.kind == .bird {
                let landing = previous.start - RunnerAutoPilot.lead(for: previous, speed: speed)
                    + speed * RunnerRules.jumpAirTime
                #expect(landing < next.start - halfWidth, "種 \(seed): \(previous.start) の着地が鳥 \(next.start) に食い込む")
            }
            if previous.kind == .bird {
                let takeOff = next.start - RunnerAutoPilot.lead(for: next, speed: speed)
                #expect(takeOff > previous.end + halfWidth, "種 \(seed): \(next.start) の踏み切りが鳥 \(previous.start) に食い込む")
            }
        }
        // 鳥のあとの台座への踏み切りも帯の外（`RunnerStageTests.birdsNeverForceAJump` と同じ）。
        for bird in stage.hazards where bird.kind == .bird {
            for platform in stage.platforms where platform.start >= bird.end {
                let speed = stage.speed(at: platform.start + Self.segmentWidth)
                let rise = RunnerRules.riseTime(to: platform.top + RunnerAutoPilot.clearance)
                let takeOff = platform.start - RunnerAutoPilot.baseLead - speed * rise
                #expect(takeOff > bird.end + halfWidth, "種 \(seed): 台座 \(platform.start) の踏み切りが鳥 \(bird.start) に食い込む")
            }
        }

        // 台座の前後は素の平地、床の直後は素の平地で台座の隣ではない（`RunnerStage.patterns` の配置規則）。
        for (index, symbol) in symbols.enumerated() {
            if symbol == RunnerStage.platformSymbol {
                if index > 0, symbols[index - 1] != RunnerStage.platformSymbol {
                    #expect(symbols[index - 1] == "-", "種 \(seed): 台座の手前（区画 \(index - 1)）が平地でない")
                }
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.platformSymbol {
                    #expect(symbols[index + 1] == "-", "種 \(seed): 台座の直後（区画 \(index + 1)）が平地でない")
                }
            }
            if symbol == RunnerStage.boostFloorSymbol {
                if index < symbols.count - 1, symbols[index + 1] != RunnerStage.boostFloorSymbol {
                    #expect(symbols[index + 1] == "-", "種 \(seed): 床の直後（区画 \(index + 1)）が平地でない")
                }
                if index > 0 {
                    #expect(symbols[index - 1] != RunnerStage.platformSymbol, "種 \(seed): 床が台座の直後（区画 \(index)）")
                }
            }
        }
        for platform in stage.platforms {
            #expect(platform.top + RunnerAutoPilot.clearance < RunnerRules.jumpApex)
            for hazard in stage.hazards {
                #expect(!(hazard.start < platform.end && platform.start < hazard.end), "種 \(seed): 台座の上に障害")
            }
            for pickup in stage.pickups {
                #expect(!(platform.start <= pickup.start && pickup.start < platform.end), "種 \(seed): 台座の上にアイテム")
            }
            for floor in stage.boostFloors {
                #expect(!(floor.start < platform.end && platform.start < floor.end), "種 \(seed): 床が台座と重なる")
            }
        }
    }
}

/// エンドレスのコースを実際に走り切れることの実証（`RunnerPlaythroughTests` と同じ自動操縦）。
@Suite("チャリンコおじさん: エンドレスのクリア可能性")
struct RunnerEndlessPlaythroughTests {
    private static let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth

    /// 自動操縦で `until` の距離まで走る。戻り値は決着のできごと（無ければ nil）と到達距離。
    private func run(seed: UInt64, until goal: Double) -> (terminal: RunnerEvent?, distance: Double) {
        var field = RunnerField(stage: RunnerEndlessCourse.makeStage(seed: seed))
        var frames = 0
        while frames < 60 * 1_200, field.distance < goal {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            let events = field.step(dt: 1.0 / 60)
            if let terminal = events.first(where: { $0.isTerminal }) {
                return (terminal, field.distance)
            }
        }
        return (nil, field.distance)
    }

    /// 受け入れ条件「`RunnerAutoPilot` が任意の種で最低 100 区画走れる」。
    @Test("自動操縦が 20 種すべてで 100 区画以上走れる")
    func autoPilotRunsAtLeast100Segments() {
        let goal = Self.segmentWidth * 100
        // 種の数は実行時間との釣り合い（デバッグビルドで 1 種 ≒ 0.9 秒）。生成の成立条件そのものは
        // 1,000 種で検めている（`RunnerEndlessCourseTests`）ので、ここは物理とつないだ実証に絞る。
        for seed in 1...20 {
            let result = run(seed: UInt64(seed), until: goal)
            #expect(result.terminal == nil, "種 \(seed): \(result.distance) で \(String(describing: result.terminal))")
            #expect(result.distance >= goal, "種 \(seed): \(result.distance) までしか走れていない")
        }
    }

    /// 400 区画の終わりまで通しで走れる（成立条件が終盤の速さ・密度でも保たれている）。
    @Test("自動操縦が 400 区画を最後まで走り切れる")
    func autoPilotFinishesTheWholeCourse() {
        for seed in [1, 2, 3] as [UInt64] {
            let result = run(seed: seed, until: .infinity)
            #expect(result.terminal == .reachedGoal, "種 \(seed): \(result.distance) で \(String(describing: result.terminal))")
        }
    }

    /// 跳ばなければ必ずミスになる（自動操縦が「何もしなくても勝てる」証明にならないための対照）。
    @Test("一度も跳ばなければ最初の穴でミスになる")
    func doingNothingFails() {
        var field = RunnerField(stage: RunnerEndlessCourse.makeStage(seed: 1))
        var events: [RunnerEvent] = []
        var frames = 0
        while frames < 60 * 60, !events.contains(where: { $0.isTerminal }) {
            frames += 1
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.fell))
    }
}

/// エンドレスの進行・記録・解析（#675）。
@Suite("チャリンコおじさん: エンドレスの進行と記録")
@MainActor
struct RunnerEndlessModelTests {

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// 送信されたイベントをそのまま溜めるスパイ（`MahjongNewGameTests` と同じ形）。
    @MainActor
    private final class SpyAnalyticsService: AnalyticsService {
        private(set) var events: [AnalyticsEvent] = []
        func log(_ event: AnalyticsEvent) { events.append(event) }
    }

    @Test("モードは開始時に焼き込まれ、ステージ制の続き（ステージ番号）はそのまま残る")
    func modeIsBakedAtStart() {
        let model = RunnerModel(startingAt: 5, preference: makePreference("endless-mode"))
        #expect(model.mode == .stages)
        #expect(model.endlessSeed == nil)
        model.newEndlessGame(seed: 42)
        #expect(model.mode == .endless)
        #expect(model.endlessSeed == 42)
        #expect(model.phase == .ready)
        #expect(model.distance == 0)
        #expect(model.stage.pattern == RunnerEndlessCourse.pattern(seed: 42), "コースは種から決まる")
        #expect(model.stageNumber == 5, "エンドレス中もステージ制の続きを失わない")
        #expect(!model.canResumeFromCheckpoint)
        // 「はじめから」でステージ制へ戻るとステージ 1 から。
        model.newGame(mode: .stages)
        #expect(model.mode == .stages)
        #expect(model.stageNumber == 1)
        #expect(model.stage.number == 1)
    }

    @Test("ミスで 1 回が終わり、走行距離が残る。もう一度は新しい種で始まる")
    func missEndsTheRunAndRetryRollsANewCourse() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-miss"))
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(model.distance > 0)
        #expect(model.endlessBestDistance == Int(model.distance))
        #expect(model.didSetBestDistance, "初回は必ず更新")
        #expect(!model.canResumeFromCheckpoint, "エンドレスに広告での再開は無い")
        let generation = model.runGeneration
        model.retryStage()
        #expect(model.phase == .ready)
        #expect(model.mode == .endless)
        #expect(model.endlessSeed != 1, "同じコースを走り直す導線は無い")
        #expect(model.runGeneration == generation + 1)
        #expect(model.distance == 0)
    }

    /// 受け入れ条件「ステージ制の記録・順位表に影響しない」。
    @Test("エンドレスの記録はステージ制の自己ベストを汚さず、別の順位表へ送られる")
    func endlessRecordIsSeparateFromStages() {
        let log = makePlayLog("separate")
        let gameCenter = SpyGameCenterService()
        let store = MemorySnapshotStore()
        let model = RunnerModel(
            services: makeServices(store: store, log: log, gameCenter: gameCenter),
            startingAt: 1, preference: makePreference("endless-record")
        )
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        let stageRecord = log.record(gameID: RunnerModel.gameID)
        #expect(stageRecord?.bestPoints == 1, "ステージ制は到達ステージ数")
        let saveCount = store.saveCount

        model.newEndlessGame(seed: 3)
        failCurrentStage(model)
        let meters = Int(model.distance)
        #expect(meters > 0)

        #expect(log.record(gameID: RunnerModel.gameID) == stageRecord, "ステージ制の記録が動いていない")
        let endless = log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant)
        #expect(endless?.bestPoints == meters)
        #expect(endless?.variantLabel == "エンドレス")
        #expect(endless?.losses == 1 && endless?.wins == 0, "ミスで終わった回は負けとして数える")
        #expect(gameCenter.scores == [
            GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerStage, value: 1),
            GameCenterScore(leaderboardID: GameCenterLeaderboard.runnerDistance, value: meters),
        ])
        #expect(store.saveCount == saveCount, "エンドレスは中断データに書かない")
        #expect(store.load(RunnerSnapshot.self, for: RunnerModel.gameID)?.stage == 2, "ステージ制の続きはそのまま")

        // 開き直すと自己ベストを `PlayLog` から読む。
        let reopened = RunnerModel(
            services: makeServices(store: store, log: log), preference: makePreference("endless-reopen")
        )
        #expect(reopened.mode == .stages, "起動時は必ずステージ制（エンドレスは復元しない）")
        #expect(reopened.endlessBestDistance == meters)
    }

    @Test("自己ベストは伸びたときだけ更新され、同じ距離では更新しない")
    func bestDistanceUpdatesOnlyWhenLonger() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-best"))
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        let first = model.endlessBestDistance
        #expect(first != nil)
        // 同じ種・同じ操作（跳ばない）なら同じ距離でミスする。同点は更新扱いにしない。
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.endlessBestDistance == first)
        #expect(!model.didSetBestDistance)
    }

    /// 固定長のコースを走り切った場合も 1 回の決着（第 1 弾は 400 区画で打ち切り）。
    @Test("コースを走り切ると勝ちとして距離が記録される")
    func finishingTheCourseCountsAsAWin() {
        let log = makePlayLog("finish")
        let model = RunnerModel(
            services: makeServices(log: log), startingAt: 1, preference: makePreference("endless-finish")
        )
        model.newEndlessGame(seed: 2)
        #expect(autoPlayCurrentStage(model, maxFrames: 60 * 1_200), "走り切る前に打ち切りに達した")
        #expect(model.phase == .allCleared)
        #expect(model.isRunOver)
        #expect(model.distance == model.stage.length)
        let record = log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant)
        #expect(record?.wins == 1)
        #expect(record?.bestPoints == Int(model.stage.length))
        // その先は無い。「もう一度」で新しいコース。
        model.advanceToNextStage()
        #expect(model.phase == .allCleared, "エンドレスに次のステージは無い")
        model.retryStage()
        #expect(model.phase == .ready && model.mode == .endless)
    }

    /// 撮影用シナリオ（`-simulateRunner endless-*`）が狙った画で止まること。種は固定なので決定論的。
    @Test("撮影用シナリオ endless-running / endless-failed は狙った状態で止まる")
    func captureScenariosLandWhereIntended() {
        let ready = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-ready"))
        ready.applyDebugScenario("endless")
        #expect(ready.mode == .endless && ready.phase == .ready)

        let running = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-running"))
        running.applyDebugScenario("endless-running")
        #expect(running.mode == .endless && running.phase == .running)
        #expect(!running.field.isGrounded, "跳んでいる最中で止める")

        let failed = RunnerModel(startingAt: 1, preference: makePreference("endless-capture-failed"))
        failed.applyDebugScenario("endless-failed")
        #expect(failed.mode == .endless && failed.phase == .failed)
        #expect(failed.distance > 700, "冒頭の固定区画を抜けてからミスする")
    }

    @Test("一時停止はエンドレスでも効く")
    func pauseWorksInEndless() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("endless-pause"))
        model.newEndlessGame(seed: 1)
        model.press()
        model.release()
        model.tick(dt: 0.5)
        let distance = model.distance
        model.pause()
        #expect(model.phase == .paused)
        for _ in 0..<60 { model.tick(dt: 1.0 / 60) }
        #expect(model.distance == distance)
        model.resume()
        #expect(model.phase == .running)
    }

    /// `game_start` の `mode` でステージ制（`stage`・`level` はそのまま）とエンドレス（`endless`）を分ける。
    @Test("解析の game_start にモードが付き、エンドレスには level が付かない")
    func analyticsCarriesMode() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = RunnerModel(services: services, startingAt: 3, preference: makePreference("endless-analytics"))
        model.newEndlessGame(seed: 1)
        model.newGame(mode: .stages)
        let starts = spy.events.compactMap { event -> (level: String?, mode: String?)? in
            if case let .gameStart(_, level, mode) = event { return (level?.parameterValue, mode) } else { return nil }
        }
        #expect(starts.map(\.mode) == ["stage", "endless", "stage"])
        #expect(starts.map(\.level) == ["stage-3", nil, "stage-1"])
    }
}
