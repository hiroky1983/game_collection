import CoreEngine
import Foundation
import Testing
@testable import GameRunner

/// 跳び続けないと沈む床（#1089・里山＝田んぼ・港町＝干潟）の検証。
///
/// 床は `RunnerHazard` ではないので、既存の成立条件（`RunnerStageTests.everyHazardIsClearable` /
/// `hazardsAreFarEnoughApart`）は一切掛からない。**「どう操作しても抜けられない区間」が
/// 生まれないことは、ここで長さと連打の速さから機械的に確かめる**。
@Suite("チャリンコおじさん: 沈む床")
struct RunnerSinkFloorTests {
    private static let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
    private static let bank = Double(RunnerRules.sinkFloorBankTiles) * RunnerRules.tileWidth
    /// 本編で沈む床が置かれる面のうち、いちばん遅い面と速い面の基準速。
    /// 遅いほど床の上に居る時間が長い（＝連打が要る）ので、公平さの検証は遅い側で行う。
    private static var sinkStageSpeeds: [Double] {
        RunnerStage.all.filter { !$0.sinkFloors.isEmpty }.map(\.speed)
    }

    // MARK: - 区画記号の展開

    /// 加速床（`=`）と同じく連続ぶんは 1 本にまとまる。違うのは**両端に岸を残す**こと。
    @Test("区画記号 → 沈む床: 連続する ~ は 1 本にまとまり、両端に岸のぶんだけ短くなる")
    func sinkFloorSymbolExpandsToMergedRunsWithBanks() {
        let stage = RunnerStage(number: 1, pattern: "-~~--~-", speed: 40)
        #expect(stage.sinkFloors.count == 2, "連続ぶんは 1 本にまとまる")
        let long = stage.sinkFloors[0]
        #expect(long.segments == 2)
        #expect(long.start == Self.segment + Self.bank)
        #expect(long.length == Self.segment * 2 - Self.bank * 2)
        let short = stage.sinkFloors[1]
        #expect(short.segments == 1)
        #expect(short.start == Self.segment * 5 + Self.bank)
        #expect(short.length == Self.segment - Self.bank * 2)
        #expect(short.end == short.start + short.length)
        // 床は障害でもアイテムでも台座でもない（地形としては平地そのもの）。
        #expect(stage.hazards.isEmpty)
        #expect(stage.platforms.isEmpty)
        #expect(stage.boostFloors.isEmpty)
    }

    // MARK: - 長さの設計（決裁「短い床は二段で跳び越せる・長い床は跳び越せない」）

    /// 長さで 2 種を区別できること。**1 区画ぶん = 短い床（二段で跳び越せる）／
    /// 2 区画ぶん以上 = 長い床（跳び越せない）**が、どの面の速さでも成り立つ。
    @Test("1 区画ぶんの床は二段ジャンプで跳び越せ、2 区画ぶんの床は跳び越せない")
    func shortFloorsClearableLongFloorsNot() {
        for stage in RunnerStage.all where !stage.sinkFloors.isEmpty {
            for floor in stage.sinkFloors {
                let clearable = floor.isClearableByDoubleJump(at: stage.speed)
                #expect(
                    clearable == (floor.segments == 1),
                    """
                    ステージ \(stage.number) の床（\(floor.segments) 区画・長さ \(floor.length)）が
                    二段の飛距離 \(RunnerRules.doubleJumpRange(at: stage.speed)) と噛み合っていない
                    """
                )
            }
        }
        // 3 区画ぶん以上も跳び越せない（長さの上限を増やす方向の変更で効く）。
        let wide = RunnerStage(number: 1, pattern: "--~~~--", speed: 57.2).sinkFloors[0]
        #expect(!wide.isClearableByDoubleJump(at: 57.2))
    }

    /// **本当に二段で跳び越せる**ことを軌道で確かめる（長さの比較だけでは、岸で踏み切れるか・
    /// 着地が岸に乗るかまでは分からない）。いちばん遅い面の速さ（飛距離がいちばん短い）で見る。
    @Test("短い床は、岸で踏み切って頂点で二段目を踏めば水に触れずに越えられる")
    func shortFloorIsActuallyClearedByADoubleJump() {
        let speed = Self.sinkStageSpeeds.min() ?? RunnerRules.baseSpeed
        let stage = RunnerStage(number: 1, pattern: "--~----", speed: speed)
        let floor = stage.sinkFloors[0]
        var field = RunnerField(stage: stage)
        var touchedWater = false
        var usedSecondJump = false
        for _ in 0..<(60 * 10) {
            // 岸のぎりぎりで踏み切り、頂点（上昇が止まったところ）で二段目を踏む。
            if field.isGrounded, field.distance >= floor.start - RunnerRules.tileWidth / 2,
               field.distance < floor.start {
                field.jump()
            } else if !field.isGrounded, !usedSecondJump, field.vy <= 0 {
                usedSecondJump = field.jump()
            }
            _ = field.step(dt: 1.0 / 60)
            if field.isOnSinkFloor { touchedWater = true }
            if field.distance > floor.end { break }
        }
        #expect(usedSecondJump, "二段目を踏めていない（この検証が成り立っていない）")
        #expect(field.distance > floor.end, "床を越えられていない")
        #expect(!touchedWater, "水に足が着いた（跳び越せていない）")
        #expect(field.sinkProgress == 0)
    }

    // MARK: - 公平さ（決裁「1 秒に 3 回の連打で、置いた一番長い床を必ず抜けられる」）

    /// 人が無理なく出せる 1 秒 3 回の連打（周期 20 フレーム）で、**本編に置いたいちばん長い床**を
    /// 抜けられること。連打は「押して同じフレームで離す」——いちばん低いホップで、
    /// 滞空がいちばん短い＝いちばん沈む側の操作。
    ///
    /// 速さは本編で床がある面の**いちばん遅い側といちばん速い側の両方**で見る（遅い面ほど
    /// 床の上に長く居る＝不利、速い面ほど着地までの距離が伸びる＝踏み切り直しの回数が減る）。
    @Test("1 秒 3 回の連打で、いちばん長い床を溺れずに抜けられる")
    func longestFloorSurvivesThreeTapsPerSecond() {
        let longest = RunnerStage.all.flatMap(\.sinkFloors).map(\.segments).max() ?? 1
        #expect(longest >= 2, "長い床が本編に無い（この検証が空振りしている）")
        for speed in [Self.sinkStageSpeeds.min() ?? 34, Self.sinkStageSpeeds.max() ?? 34] {
            let stage = RunnerStage(
                number: 1,
                pattern: "--" + String(repeating: "~", count: longest) + "----",
                speed: speed
            )
            let floor = stage.sinkFloors[0]
            var field = RunnerField(stage: stage)
            var drowned = false
            var frames = 0
            while frames < 60 * 20, field.distance <= floor.end {
                // 1 秒 3 回 = 20 フレームごとに 1 回、押して即離す。
                if frames % 20 == 0 {
                    field.jump()
                    field.endHold()
                }
                frames += 1
                if field.step(dt: 1.0 / 60).contains(.fell) { drowned = true; break }
            }
            #expect(!drowned, "速さ \(speed) で、1 秒 3 回の連打では抜けられなかった")
            #expect(field.distance > floor.end, "速さ \(speed) で床を渡り切れていない")
        }
    }

    /// 逆に、**跳ばずに乗り続ければ必ず溺れる**（仕組みが効いている）。死因は `sink`。
    @Test("長い床を跳ばずに走ると、必ず沈んで溺れる（死因は sink）")
    func standingStillOnALongFloorDrowns() {
        let stage = RunnerStage(number: 1, pattern: "--~~----", speed: Self.sinkStageSpeeds.max() ?? 57.2)
        var field = RunnerField(stage: stage)
        var drowned = false
        for _ in 0..<(60 * 20) where !drowned {
            drowned = field.step(dt: 1.0 / 60).contains(.fell)
        }
        #expect(drowned, "跳ばなくても渡り切れてしまう")
        #expect(field.lastMissCause == .sink)
        #expect(field.sinkProgress >= 1)
    }

    // MARK: - 沈みの増減

    @Test("沈みは接地しているあいだだけ増え、跳ぶと 0 に戻る")
    func jumpingResetsTheSink() {
        let stage = RunnerStage(number: 1, pattern: "--~~----", speed: 50)
        var field = RunnerField(stage: stage)
        let floor = stage.sinkFloors[0]
        while field.distance < floor.start + 4 { _ = field.step(dt: 1.0 / 60) }
        for _ in 0..<12 { _ = field.step(dt: 1.0 / 60) }
        let sunk = field.sinkProgress
        #expect(sunk > 0, "床の上で沈みが溜まらない")
        field.jump()
        _ = field.step(dt: 1.0 / 60)
        #expect(field.sinkProgress == 0, "跳んでも沈みが戻らない")
        #expect(field.sinkDepth == 0)
    }

    @Test("床を出ると沈みは 0 に戻る")
    func leavingTheFloorResetsTheSink() {
        let stage = RunnerStage(number: 1, pattern: "--~-----", speed: 50)
        var field = RunnerField(stage: stage)
        let floor = stage.sinkFloors[0]
        var peak = 0.0
        while field.distance < floor.end + 8 {
            _ = field.step(dt: 1.0 / 60)
            peak = max(peak, field.sinkProgress)
        }
        #expect(peak > 0, "床の上で沈みが溜まらない")
        #expect(field.sinkProgress == 0, "床を出ても沈みが残っている")
    }

    /// 沈みは**見た目だけ**（決裁「当たり判定の地面の高さは変えない」）。
    /// 沈んだ状態で踏み切ったジャンプは、乾いた地面での踏み切りと 1 単位も変わらない。
    @Test("沈んでいても足元の高さは動かず、踏み切ったジャンプは普通のジャンプと同じ")
    func sinkOnlyMovesThePicture() {
        let stage = RunnerStage(number: 1, pattern: "--~~----", speed: 50)
        var sinking = RunnerField(stage: stage)
        let floor = stage.sinkFloors[0]
        while sinking.distance < floor.start + 4 { _ = sinking.step(dt: 1.0 / 60) }
        for _ in 0..<18 { _ = sinking.step(dt: 1.0 / 60) }
        #expect(sinking.sinkProgress > 0.3, "沈みが溜まっていない（この検証が成り立っていない）")
        #expect(sinking.footY == RunnerField.Metrics.groundY, "当たり判定の足元が動いている")
        #expect(sinking.altitude == 0)
        #expect(sinking.sinkDepth > 0, "絵が沈んでいない")
        #expect(sinking.sinkDepth <= RunnerRules.sinkVisualDepth)

        // 沈んだ状態と乾いた地面からの踏み切りで、頂点の高さが一致する。
        var dry = RunnerField(stage: RunnerStage(number: 1, pattern: "--------", speed: 50))
        for _ in 0..<60 { _ = dry.step(dt: 1.0 / 60) }
        func apex(_ field: inout RunnerField) -> Double {
            field.jump()
            var top = 0.0
            for _ in 0..<60 {
                _ = field.step(dt: 1.0 / 60)
                top = max(top, field.altitude)
            }
            return top
        }
        #expect(abs(apex(&sinking) - apex(&dry)) < 1e-9, "沈みでジャンプの頂点が変わっている")
    }

    @Test("沈む床の上では接地中だけ遅くなり、空中の横速度は基準速のまま")
    func sinkFloorSlowsTheGroundOnly() {
        let stage = RunnerStage(number: 1, pattern: "--~~----", speed: 50)
        var field = RunnerField(stage: stage)
        let floor = stage.sinkFloors[0]
        while field.distance < floor.start + 4 { _ = field.step(dt: 1.0 / 60) }
        let onFloor = field.currentSpeed
        #expect(field.isOnSinkFloor)
        #expect(onFloor < stage.speed, "乗っても素の基準速より遅くならない")
        #expect(
            abs(onFloor - stage.speed * field.pedalBoost * RunnerRules.sinkFloorMultiplier) < 1e-9,
            "倍率が接地中の速さに掛かっていない"
        )
        field.jump()
        _ = field.step(dt: 1.0 / 60)
        #expect(!field.isOnSinkFloor, "跳んでも床の上と見なされている")
        #expect(abs(field.currentSpeed - stage.speed) < 1e-9, "空中の横速度が基準速でない")
    }

    /// ゆっくりモード（アクセシビリティ）。`RunnerModel` が `dt` そのものを縮めるので、
    /// **沈む速さも同じ割合で遅くなる**——同じ実時間で沈む量が `slowFactor` 倍になる。
    @Test("ゆっくりモードでは沈む速さも同じ割合で遅くなる")
    func slowModeSlowsTheSink() {
        func sink(slow: Bool) -> Double {
            let stage = RunnerStage(number: 1, pattern: "--~~----", speed: 50)
            var field = RunnerField(stage: stage)
            // 走り出しの位置ではなく、**水の上の同じ地点・沈み 0** から数える
            // （助走の長さがモードで変わると、測っているものが「同じ実時間の沈み」でなくなる）。
            field.placeForTesting(distance: stage.sinkFloors[0].start + 4, altitude: 0, vy: 0)
            #expect(field.isOnSinkFloor)
            for _ in 0..<20 { _ = field.step(dt: 1.0 / 60 * (slow ? RunnerRules.slowFactor : 1)) }
            return field.sinkProgress
        }
        let normal = sink(slow: false), slow = sink(slow: true)
        #expect(slow > 0)
        #expect(
            abs(slow - normal * RunnerRules.slowFactor) < 1e-9,
            "ゆっくりモードの沈み \(slow) が通常 \(normal) の \(RunnerRules.slowFactor) 倍になっていない"
        )
    }

    /// 一時停止・バックグラウンドへの移動と復帰で、沈みがずれない・二重に進まない。
    ///
    /// 止まっているあいだは `RunnerModel.tick` が `field` を進めないので沈みも止まり、
    /// 復帰した最初のフレームに溜まった巨大な `dt` は `RunnerRules.maxStep` で頭打ちになる
    /// ——「戻った瞬間に溺れていた」が起きないこと。
    @Test("一時停止とバックグラウンド復帰で沈みが二重に進まない")
    @MainActor
    func pauseAndBackgroundDoNotAdvanceTheSink() {
        let model = RunnerModel(startingAt: 21, preference: makePreference("sink-pause"))
        let floor = model.field.stage.sinkFloors[0]
        model.press()
        model.release()
        // 床の上まで走り、そこで止める（自動操縦は床で跳ぶので、床に入ったら操作をやめる）。
        var frames = 0
        while frames < 60 * 60, !model.field.isOnSinkFloor {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.field.isOnSinkFloor, "床の上まで来られなかった（床は \(floor.start)）")
        for _ in 0..<6 { model.tick(dt: 1.0 / 60) }
        let beforePause = model.field.sinkProgress
        #expect(beforePause > 0)

        model.pause()
        for _ in 0..<120 { model.tick(dt: 1.0 / 60) }
        #expect(model.field.sinkProgress == beforePause, "一時停止中に沈みが進んだ")

        // 復帰直後に 30 秒ぶんの `dt` が来ても、1 フレームで進むのは `maxStep` ぶんだけ。
        model.resume()
        model.tick(dt: 30)
        #expect(
            model.field.sinkProgress <= beforePause + RunnerRules.maxStep / RunnerRules.sinkDuration + 1e-9,
            "復帰の 1 フレームで沈みが一気に進んだ（\(beforePause) → \(model.field.sinkProgress)）"
        )
    }

    // MARK: - 置き方（#1009 の「入れない組み合わせ」）

    @Test("沈む床は 19 面以降にだけ置かれていて、里山・港町の両方にある")
    func sinkFloorsOnlyAppearInTheNewWorlds() {
        for stage in RunnerStage.all.prefix(18) {
            #expect(!stage.pattern.contains("~"), "ステージ \(stage.number) に沈む床がある: \(stage.pattern)")
        }
        for (world, range) in [(RunnerWorld.satoyama, 19...24), (.harbor, 25...30)] {
            let count = RunnerStage.all
                .filter { range.contains($0.number) }
                .reduce(0) { $0 + $1.sinkFloors.count }
            #expect(count >= 2, "\(world) に沈む床が \(count) 本しかない")
        }
    }

    /// **新しい仕組みは初めて出す面で前後を平地にして単独で見せる**（#1009 C2）。
    /// 田んぼは 21 面、干潟は 29 面が初出。
    @Test("沈む床の初出（21 面・29 面）の 1 本目は前後が素の平地")
    func firstSinkFloorOfEachWorldStandsAlone() {
        for number in [21, 29] {
            let pattern = Array(RunnerStage.all[number - 1].pattern)
            guard let index = pattern.firstIndex(of: "~") else {
                Issue.record("ステージ \(number) に沈む床が無い")
                continue
            }
            #expect(index > 0 && pattern[index - 1] == "-", "ステージ \(number): 1 本目の手前が平地でない")
            #expect(
                index + 1 < pattern.count && pattern[index + 1] == "-",
                "ステージ \(number): 1 本目の直後が平地でない"
            )
        }
    }

    /// **#1089 の「入れない組み合わせ」**。
    ///
    /// - 床の中・床の直後の区画に鳥を置かない（跳び続けないと沈むが、跳ぶと鳥に当たる）
    /// - 床の中に台座・突き上げを置かない
    ///
    /// 区画記号は 1 区画に 1 文字なので「床の中」は字面で自明だが、**区画の外側の当たり判定まで
    /// 見て**確かめる: 鳥のくぐる区間（`encounter`）が床の水面と重ならず、走者が水を抜けてから
    /// 着地して走る余地（1 タイル以上）が残っていること。
    @Test("沈む床の中と直後に鳥を置かず、床の中に台座・突き上げも置かない")
    func sinkFloorsAvoidBirdsPlatformsAndShoots() {
        for stage in RunnerStage.all where !stage.sinkFloors.isEmpty {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "~" {
                #expect(symbol != "P" && symbol != "^", "ステージ \(stage.number): 床の区画に台座・突き上げ")
                if index + 1 < pattern.count {
                    #expect(
                        pattern[index + 1] != "b",
                        "ステージ \(stage.number): 区画 \(index) の床の直後に鳥がいる"
                    )
                }
            }
            for floor in stage.sinkFloors {
                for bird in stage.hazards where bird.kind == .bird {
                    let mustRun = bird.encounter.start...bird.encounter.end
                    #expect(
                        !(mustRun.lowerBound < floor.end && floor.start < mustRun.upperBound),
                        "ステージ \(stage.number): 鳥のくぐる区間が床と重なっている"
                    )
                    guard mustRun.lowerBound > floor.end else { continue }
                    #expect(
                        mustRun.lowerBound - floor.end > RunnerRules.tileWidth,
                        "ステージ \(stage.number): 床を出てから鳥まで \(mustRun.lowerBound - floor.end) しかない"
                    )
                }
                for platform in stage.platforms {
                    #expect(
                        !(platform.start < floor.end && floor.start < platform.end),
                        "ステージ \(stage.number): 台座が床と重なっている"
                    )
                }
            }
        }
    }

    /// エンドレス（#1086）には置かない（決裁「生成器に教えるのは別の版」）。
    /// 生成器が `~` を出さないので、枠で走っているあいだ沈みは起きない。
    @Test("エンドレスのコースには沈む床が出ない")
    func endlessCourseHasNoSinkFloors() {
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                #expect(!field.isOnSinkFloor, "種 \(seed) のエンドレスに沈む床が出た")
                if field.sinkProgress > 0 { Issue.record("種 \(seed) で沈みが進んだ"); break }
            }
        }
    }

    /// QA 用ショーケース（`-simulateRunner` の撮影）で、沈む床を単体で見られること。
    /// 2 区画ぶん（長い床）にしてあるのは、跳ばずに走らせて沈みかけ・溺れの画を撮るため。
    @Test("QA用ショーケースに 2 区画ぶんの沈む床がある")
    func showcaseHasALongSinkFloor() {
        let floors = RunnerStage.debugShowcase.sinkFloors
        #expect(floors.count == 1)
        #expect(floors.first?.segments == 2)
        #expect(floors.first?.isClearableByDoubleJump(at: RunnerStage.debugShowcase.speed) == false)
    }
}
