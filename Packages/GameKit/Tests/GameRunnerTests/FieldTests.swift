import Foundation
import Testing
@testable import GameRunner

/// コース（当たり判定・ジャンプの軌道）の検証（#494）。
///
/// `SKScene` はここで一度も生成しない。ルール層が SpriteKit から独立しているおかげで、
/// 1 ステージ丸ごとをシミュレータ抜きで再生できる（アクション枠の基盤規約 §6）。
@Suite("チャリンコおじさん: コースの進行")
struct RunnerFieldTests {

    /// 障害の無い一本道。狙った局面だけを取り出して確かめるために使う。
    private func flatStage(segments: Int = 6, speed: Double = 40) -> RunnerStage {
        RunnerStage(number: 1, pattern: String(repeating: "-", count: segments), speed: speed)
    }

    @Test("走ると距離が速さ×時間だけ進む（ペダルの乗りのぶんだけ上振れる）")
    func runsForward() {
        var field = RunnerField(stage: flatStage())
        for _ in 0..<60 { _ = field.step(dt: 1.0 / 60) }
        #expect(field.distance > 40, "接地して漕ぎ続けると基準より速くなる（#569）")
        #expect(field.distance < 40 * RunnerRules.maxPedalBoost + 0.5, "上限を超えない")
        #expect(field.isGrounded, "平地では接地したまま")
    }

    // MARK: - ペダル（#569）

    @Test("接地して漕ぎ続けると上限まで乗る")
    func pedalBuildsUpOnGround() {
        var field = RunnerField(stage: flatStage(segments: 40))
        #expect(field.pedalBoost == 1, "走り出しは乗っていない")
        // 上限までの半分だけ漕ぐ時間。
        _ = field.step(dt: (RunnerRules.maxPedalBoost - 1) / RunnerRules.pedalGain / 2)
        let midway = field.pedalBoost
        #expect(midway > 1, "接地しているあいだは上がる")
        #expect(midway < RunnerRules.maxPedalBoost, "上限までは時間がかかる")
        for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
        #expect(abs(field.pedalBoost - RunnerRules.maxPedalBoost) < 1e-9, "上限で頭打ち")
    }

    @Test("跳んでいるあいだは漕げないので乗りが落ちる（下限は 1.0）")
    func jumpingCostsPedal() {
        var field = RunnerField(stage: flatStage(segments: 40))
        // まず上限まで乗せてから踏み切る。
        for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
        let before = field.pedalBoost
        field.jump()
        field.endHold()
        while !field.isGrounded { _ = field.step(dt: 1.0 / 240) }
        #expect(field.pedalBoost < before, "跳ぶと乗りが落ちる")
        #expect(field.pedalBoost >= 1, "落ちきっても基準の速さが下限")
    }

    /// 乗りの下限は 1.0（= 基準の速さ）。
    ///
    /// **乗っていない状態から踏み切る**のがこの下限に当たる唯一の入口で、上の
    /// 「上限まで乗せてから跳ぶ」形では滞空 1 回ぶんでは 1.0 まで落ちきらず素通りする。
    /// 下限が外れると走る速さが基準を下回り、ステージの成立条件（`RunnerStageTests`）の
    /// 前提そのものが崩れる。
    @Test("乗っていない状態から跳んでも 1.0 を割らない")
    func pedalNeverDropsBelowBase() {
        var field = RunnerField(stage: flatStage(segments: 40))
        #expect(field.pedalBoost == 1)
        field.jump()   // 押しっぱなし = 滞空が最も長くなる跳び方
        while !field.isGrounded { _ = field.step(dt: 1.0 / 240) }
        #expect(field.pedalBoost == 1, "下限を割ると基準より遅くなる")
    }

    /// **タイムが操作を反映する**ことの実証（#569 の A 案そのもの）。
    /// 同じ地点で踏み切っても、高く跳ぶほど空中が長くなり、着地後の速さも落ちる。
    @Test("同じ地点で踏み切っても、高く跳ぶほど到達が遅れる")
    func lowJumpsAreFaster() {
        func distance(afterHolding holding: Bool) -> Double {
            var field = RunnerField(stage: flatStage(segments: 40))
            for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
            field.jump()
            if !holding { field.endHold() }
            for _ in 0..<180 { _ = field.step(dt: 1.0 / 60) }
            return field.distance
        }
        #expect(
            distance(afterHolding: false) > distance(afterHolding: true),
            "低い弾道のほうが同じ時間で先へ進む"
        )
    }

    /// 空中の横速度は乗りに左右されない（`RunnerStageTests` の成立条件の前提・#569）。
    @Test("空中では乗りに関わらず基準の速さで進む")
    func airborneSpeedIsAlwaysBase() {
        var field = RunnerField(stage: flatStage(segments: 40))
        for _ in 0..<600 { _ = field.step(dt: 1.0 / 60) }
        #expect(field.currentSpeed > field.stage.speed, "接地中は乗りが効く")
        field.jump()
        field.endHold()
        _ = field.step(dt: 1.0 / 240)
        #expect(field.currentSpeed == field.stage.speed, "空中は基準の速さ")
    }

    @Test("同じ入力からは常に同じ軌道になる（乱数を使わない）")
    func isDeterministic() {
        func trace(jumpAt frame: Int) -> [Double] {
            var field = RunnerField(stage: flatStage())
            var result: [Double] = []
            for i in 0..<120 {
                if i == frame { field.jump() }
                _ = field.step(dt: 1.0 / 60)
                result.append(field.altitude)
            }
            return result
        }
        #expect(trace(jumpAt: 10) == trace(jumpAt: 10))
        #expect(trace(jumpAt: 10) != trace(jumpAt: 20), "踏み切りの位置が違えば軌道も違う")
    }

    /// 着地するまで離さなければ（＝十分長く押し続ければ）、切り詰め無しの全弾道になり、
    /// 頂点と滞空時間が `RunnerRules.jumpApex`/`jumpAirTime` どおりになる。
    /// `RunnerAutoPilot` が地形のクリア可能性を保証するのもこの軌道（`shouldRelease` 参照）。
    @Test("十分長く押し続けたジャンプの頂点と滞空時間が定数どおり")
    func jumpArcMatchesRulesWhenHeldToLanding() {
        var field = RunnerField(stage: flatStage())
        field.jump()
        var apex: Double = 0
        var frames = 0
        while !field.isGrounded, frames < 300 {
            frames += 1
            _ = field.step(dt: 1.0 / 240)
            apex = max(apex, field.altitude)
        }
        #expect(abs(apex - RunnerRules.jumpApex) < 0.3, "頂点 \(apex)")
        let airTime = Double(frames) / 240
        #expect(abs(airTime - RunnerRules.jumpAirTime) < 0.02, "滞空 \(airTime)")
    }

    /// 踏み切ってすぐ離しても、`RunnerRules.jumpCutGraceTime` ぶんは自然な弾道のまま
    /// 上昇してから切り詰められる（会長QA「進まねえ」2026-09-11 への対応。詳細は
    /// `RunnerRules.jumpCutGraceTime` のドキュメントを参照）。**猶予が明けるより前に離しても
    /// 結果は変わらない**——`endHold()` を踏み切った直後（0秒）に呼んでも、猶予の終わり
    /// （`jumpCutGraceTime`）に呼んでも、同じ頂点になる。それでも十分長く押した場合
    /// （`jumpApex`）よりは明確に低い。
    @Test("踏み切ってすぐ離しても猶予ぶんの弾道は保証され、全弾道よりは低い")
    func quickReleaseStillGetsGraceTrajectory() {
        func apex(releaseAfter delaySeconds: Double) -> Double {
            var field = RunnerField(stage: flatStage())
            field.jump()
            var released = false
            var top: Double = 0
            var frames = 0
            let step = 1.0 / 2400
            while !field.isGrounded, frames < 4000 {
                frames += 1
                if !released, Double(frames) * step >= delaySeconds {
                    field.endHold()
                    released = true
                }
                _ = field.step(dt: step)
                top = max(top, field.altitude)
            }
            return top
        }
        let instantRelease = apex(releaseAfter: 0)
        let releaseAtGraceEnd = apex(releaseAfter: RunnerRules.jumpCutGraceTime)
        let graceHeight = RunnerRules.jumpVelocity * RunnerRules.jumpCutGraceTime
            - RunnerRules.gravity * RunnerRules.jumpCutGraceTime * RunnerRules.jumpCutGraceTime / 2
        let expectedApex = graceHeight
            + RunnerRules.jumpCutVelocity * RunnerRules.jumpCutVelocity / (2 * RunnerRules.gravity)
        #expect(abs(instantRelease - expectedApex) < 0.3, "瞬間リリースの頂点 \(instantRelease)")
        #expect(abs(releaseAtGraceEnd - expectedApex) < 0.3, "猶予終了時リリースの頂点 \(releaseAtGraceEnd)")
        #expect(expectedApex < RunnerRules.jumpApex * 0.85, "十分長く押した場合よりはっきり低いこと")
    }

    /// 猶予（`jumpCutGraceTime`）を過ぎてから離すほど、すでに `vy` が重力で減っている
    /// ぶん切り詰めの影響が薄れ、より高く跳べる。猶予明け前はどのタイミングで離しても
    /// 同じ（上のテスト）だが、猶予を過ぎたあとは連続的に伸びる。
    @Test("猶予を過ぎてから離すのが遅いほど高く跳べる")
    func holdingPastGraceLongerJumpsHigher() {
        func apex(releaseAfter delaySeconds: Double) -> Double {
            var field = RunnerField(stage: flatStage())
            field.jump()
            var released = false
            var top: Double = 0
            var frames = 0
            let step = 1.0 / 2400
            while !field.isGrounded, frames < 4000 {
                frames += 1
                if !released, Double(frames) * step >= delaySeconds {
                    field.endHold()
                    released = true
                }
                _ = field.step(dt: step)
                top = max(top, field.altitude)
            }
            return top
        }
        let atGraceEnd = apex(releaseAfter: RunnerRules.jumpCutGraceTime)
        let midway = apex(releaseAfter: 0.18)
        let fullHold = apex(releaseAfter: 0.3)
        #expect(atGraceEnd < midway, "猶予明け直後より、もう少し粘ったほうが高い")
        #expect(midway < fullHold, "さらに粘ったほうがもっと高い")
        #expect(abs(fullHold - RunnerRules.jumpApex) < 0.3, "切り詰めが効かなくなる時間まで押せば全弾道")
    }

    @Test("空中でも一度だけ二段目を踏み切れる")
    func doubleJumpOnce() {
        var field = RunnerField(stage: flatStage())
        let first = field.jump()
        #expect(first)
        _ = field.step(dt: 1.0 / 60)
        let second = field.jump()
        #expect(second, "一段目のあと空中でも二段目は踏み切れる")
    }

    @Test("三段目は無い（空中で二段使い切ると着地まで踏み切れない）")
    func noThirdJump() {
        var field = RunnerField(stage: flatStage())
        _ = field.jump()
        _ = field.step(dt: 1.0 / 60)
        _ = field.jump()
        _ = field.step(dt: 1.0 / 60)
        let third = field.jump()
        #expect(!third, "二段使い切ったら着地するまで踏み切れない")
    }

    @Test("着地するとジャンプの回数がリセットされる")
    func jumpCountResetsOnLanding() {
        var field = RunnerField(stage: flatStage(segments: 30))
        _ = field.jump()
        _ = field.jump()
        var frames = 0
        while !field.isGrounded, frames < 60 * 10 {
            frames += 1
            _ = field.step(dt: 1.0 / 60)
        }
        #expect(field.isGrounded)
        let canJumpAgain = field.jump()
        #expect(canJumpAgain, "着地したのでまた一段目から踏み切れる")
    }

    /// 二段目も一段目と同じ初速で踏み切る。頂点付近で使うほど高く跳べてしまうと、
    /// 踏み切りのタイミング次第で地形の成立条件が変わってしまう（`RunnerStageTests` の前提が壊れる）。
    @Test("二段目の初速は一段目と同じ（踏み切るタイミングに左右されない）")
    func secondJumpUsesSameVelocityRegardlessOfTiming() {
        var field = RunnerField(stage: flatStage())
        _ = field.jump()
        // 頂点近くまで上がりきってから二段目を使う。
        var frames = 0
        while field.vy > 1, frames < 60 * 2 {
            frames += 1
            _ = field.step(dt: 1.0 / 60)
        }
        let altitudeBeforeSecond = field.altitude
        _ = field.jump()
        #expect(field.vy == RunnerRules.jumpVelocity, "踏み切った瞬間の速度は毎回同じ初速")
        #expect(field.altitude >= altitudeBeforeSecond - 0.01)
    }

    @Test("穴に入ると落ちる")
    func fallsIntoPit() {
        let stage = RunnerStage(number: 1, pattern: "--1---", speed: 40)
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        for _ in 0..<600 where !events.contains(.fell) {
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.fell))
        #expect(!events.contains(.reachedGoal), "落ちた時点で打ち切る")
    }

    /// 穴の判定は**中心の x** で行う（矩形にすると爪先が縁を越えた瞬間に落ちる）。
    @Test("爪先が穴の縁にかかっただけでは落ちない")
    func toesOverTheEdgeAreSafe() {
        let stage = RunnerStage(number: 1, pattern: "--1---", speed: 40)
        guard let pit = stage.hazards.first else { Issue.record("穴が無い"); return }
        var field = RunnerField(stage: stage)
        // 中心が縁の 1 手前、爪先だけが穴の上にある位置。
        field.placeForTesting(distance: pit.start - 1, altitude: 0, vy: 0)
        #expect(field.playerMaxX > pit.start, "爪先は穴の上にある")
        #expect(!field.step(dt: 1.0 / 600).contains(.fell))
    }

    @Test("障害物にぶつかると止まる")
    func crashesIntoBlock() {
        let stage = RunnerStage(number: 1, pattern: "--t---", speed: 40)
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        for _ in 0..<600 where !events.contains(.crashed) {
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.crashed))
    }

    @Test("障害物の上端より上を通れば当たらない")
    func flyingOverBlockIsSafe() {
        let stage = RunnerStage(number: 1, pattern: "--t---", speed: 40)
        guard let block = stage.hazards.first else { Issue.record("障害物が無い"); return }
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: block.start, altitude: block.height + 1, vy: 0)
        #expect(!field.step(dt: 1.0 / 600).contains(.crashed))
        // 上端より下に居れば当たる（境界の向きを取り違えていないことの対照）。
        field.placeForTesting(distance: block.start, altitude: block.height - 1, vy: 0)
        #expect(field.step(dt: 1.0 / 600).contains(.crashed))
    }

    @Test("大きな dt が来てもすり抜けない")
    func hugeStepDoesNotTunnel() {
        let stage = RunnerStage(number: 1, pattern: "--t---", speed: 40)
        var field = RunnerField(stage: stage)
        // 障害物の丸ごと向こう側まで進むだけの時間を 1 回で渡す。
        let events = field.step(dt: 5)
        #expect(events.contains(.crashed), "1 フレームで飛び越えて当たり判定を素通りしてはいけない")
    }

    @Test("チェックポイントとゴールを順に通過する")
    func passesCheckpointThenGoal() {
        let stage = flatStage(segments: 8)
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        for _ in 0..<60 * 60 where !events.contains(.reachedGoal) {
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.firstIndex(of: .passedCheckpoint)! < events.firstIndex(of: .reachedGoal)!)
        #expect(field.distance == stage.length, "ゴールで止まる")
    }

    @Test("チェックポイントから始めた場合は通過済みとして扱う")
    func startingAtCheckpoint() {
        let stage = flatStage(segments: 8)
        let field = RunnerField(stage: stage, startingAt: stage.checkpoint, passedCheckpoint: true)
        #expect(field.passedCheckpoint)
        #expect(field.distance == stage.checkpoint)
        #expect(field.isGrounded)
    }

    // MARK: - スピードアップアイテム（会長QA「スピードアップアイテムor床とかあったほうがいい」）

    /// (a) ピックアップに重なるとイベントが出て、ペダルの乗りが即座に上限まで上がること。
    @Test("ピックアップに触れるとイベントが出てペダルの乗りが上限まで即座に上がる")
    func collectingPickupBoostsPedalImmediately() {
        let stage = RunnerStage(number: 1, pattern: "--s---", speed: 40)
        guard let pickup = stage.pickups.first else { Issue.record("ピックアップが無い"); return }
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: pickup.start, altitude: 0, vy: 0)
        #expect(field.pedalBoost == 1, "取る前は下限のまま")
        let events = field.step(dt: 1.0 / 600)
        #expect(events.contains(.collectedSpeedItem))
        #expect(field.pedalBoost == RunnerRules.maxPedalBoost, "取った瞬間に上限まで乗る")
        #expect(field.collectedPickupCount == 1)
    }

    /// 乗りがすでに上限（`maxPedalBoost`）まで達している状態で取っても、
    /// `pedalBoost` 自体は頭打ちのままなので変化しないが、`currentSpeed` は
    /// `pickupOverboost` の上乗せぶんだけ確実に速くなる（会長QA「取るタイミングが
    /// 大体もうMAX速度で意味がない」2026-09-10 への対応）。
    @Test("乗りが上限のときにピックアップを取っても currentSpeed がさらに上がる")
    func collectingPickupAtMaxBoostStillSpeedsUp() {
        // 序盤に十分な平地を挟み、ピックアップへ着くころには自然に乗りが上限へ達するようにする。
        let stage = RunnerStage(number: 1, pattern: "----------s---", speed: 40)
        guard let pickup = stage.pickups.first else { Issue.record("ピックアップが無い"); return }
        var field = RunnerField(stage: stage)
        var speedBeforePickup: Double = 0
        var events: [RunnerEvent] = []
        for _ in 0..<6000 where !events.contains(.collectedSpeedItem) {
            speedBeforePickup = field.currentSpeed
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.collectedSpeedItem))
        #expect(field.pedalBoost == RunnerRules.maxPedalBoost, "前提: 取った時点で乗りは上限に達している")
        #expect(field.currentSpeed > speedBeforePickup, "上限のまま取っても、取った瞬間は必ず速くなる")
        // 上乗せは時間で減衰し、やがて元の（上限だけの）速さに戻る。
        for _ in 0..<Int(RunnerRules.pickupOverboostDuration * 60) + 10 { _ = field.step(dt: 1.0 / 60) }
        #expect(abs(field.currentSpeed - speedBeforePickup) < 0.5, "上乗せは時間切れで消える")
    }

    /// (b) 走者の当たり判定の矩形（幅 8）がピックアップの上を何フレームもまたぐあいだ、
    /// 一度取ったら 2 回目は発火しないこと。
    // MARK: - 乗れる台座（#674）

    /// 台座を 1 基だけ置いたコース。台座は前後に平地を連れて行く（`RunnerStage.patterns`）。
    private func platformStage(speed: Double = 40) -> RunnerStage {
        RunnerStage(number: 1, pattern: "---PP----", speed: speed)
    }

    /// 接地面の解決そのもの。台座の範囲内だけ上面へ、外は地面へ。
    @Test("接地面は台座の範囲内だけ上面になる")
    func surfaceFollowsPlatform() {
        let stage = platformStage()
        guard let platform = stage.platforms.first else { Issue.record("台座が無い"); return }
        let field = RunnerField(stage: stage)
        let ground = RunnerField.Metrics.groundY
        #expect(field.surfaceY(at: platform.start - 1) == ground, "手前は地面")
        #expect(field.surfaceY(at: platform.start) == ground + platform.top, "左端から上面")
        #expect(field.surfaceY(at: (platform.start + platform.end) / 2) == ground + platform.top)
        #expect(field.surfaceY(at: platform.end) == ground, "右端を出たら地面")
    }

    /// 跳んで乗り、上を走り、端から降りて地面へ着地する——台座の基本の一連。
    @Test("台座に跳んで乗れ、上を走れ、端から降りて着地する")
    func ridesOntoPlatformAndOffTheEnd() {
        let stage = platformStage()
        guard let platform = stage.platforms.first else { Issue.record("台座が無い"); return }
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        var onPlatform = false
        var frames = 0
        while frames < 60 * 60, !events.contains(where: { $0.isTerminal }) {
            frames += 1
            // 自動操縦の判断そのもので踏み切る（製品コードと同じ関数・#494 の作法）。
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            events += field.step(dt: 1.0 / 60)
            if field.isGrounded, field.distance > platform.start, field.distance < platform.end {
                onPlatform = true
                #expect(
                    field.altitude == platform.top,
                    "台座の上では足が上面（地面から \(platform.top)）にある"
                )
            }
            if onPlatform, field.distance > platform.end + 30 { break }
        }
        #expect(!events.contains(.crashed), "台座に当たってはいけない")
        #expect(onPlatform, "台座の上を走れていない")
        #expect(field.isGrounded, "端から降りたあと地面に着地している")
        #expect(field.altitude == 0, "降りたら地面の高さへ戻る")
        #expect(events.filter { $0 == .landed }.count >= 2, "乗るときと降りるときで 2 回着地する")
    }

    /// 正面から突っ込めば高い障害物と同じくミス（#674 の受け入れ条件）。
    @Test("台座に正面から突っ込むとミスになる")
    func crashesIntoPlatformFace() {
        let stage = platformStage()
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        // 一度も跳ばなければ台座の左端に当たる。
        for _ in 0..<60 * 60 where !events.contains(where: { $0.isTerminal }) {
            events += field.step(dt: 1.0 / 60)
        }
        #expect(events.contains(.crashed))
        #expect(!events.contains(.reachedGoal), "当たった時点で打ち切る")
    }

    /// 上面より上を通っていれば当たらない（境界の向きを取り違えていないことの対照。
    /// 岩の `flyingOverBlockIsSafe` と同じ形で確かめる）。
    @Test("上面より下で台座の左端に入ると当たり、上面より上なら当たらない")
    func platformFaceBoundary() {
        let stage = platformStage()
        guard let platform = stage.platforms.first else { Issue.record("台座が無い"); return }
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: platform.start - 1, altitude: platform.top + 1, vy: 0)
        #expect(field.playerMaxX > platform.start, "爪先は台座に掛かっている")
        #expect(!field.step(dt: 1.0 / 600).contains(.crashed), "上面より上なら乗れる")

        field.placeForTesting(distance: platform.start - 1, altitude: platform.top - 1, vy: 0)
        #expect(field.step(dt: 1.0 / 600).contains(.crashed), "上面より下なら正面衝突")
    }

    /// **台座の上を走り切って端から降りる瞬間は正面衝突ではない**（矩形の重なりだけで
    /// 判定すると、尻がまだ台座に重なったまま足が下がるここで誤ってミスになる）。
    @Test("台座の右端から降りてもミスにならない")
    func leavingPlatformIsNotACrash() {
        let stage = platformStage()
        guard let platform = stage.platforms.first else { Issue.record("台座が無い"); return }
        var field = RunnerField(stage: stage)
        // 右端の 1 手前に、上面に立った状態で置く。
        field.placeForTesting(distance: platform.end - 1, altitude: platform.top, vy: 0)
        #expect(field.isGrounded, "上面に接地している")
        var events: [RunnerEvent] = []
        for _ in 0..<600 where field.distance < platform.end + 20 {
            events += field.step(dt: 1.0 / 600)
        }
        #expect(!events.contains(.crashed), "降りる動きを正面衝突と取り違えている")
        #expect(events.contains(.landed), "地面へ着地する")
        #expect(field.altitude == 0)
    }

    /// 台座の端から出た先が穴なら、そのまま穴に落ちる（#674 の受け入れ条件）。
    /// 落下の処理は地面のときと同じで、穴の判定（中心の x）がそのまま効く。
    @Test("台座の端から穴に落ちる")
    func fallsIntoPitFromPlatformEdge() {
        // 台座の直後の区画に穴を置く（本編のステージでは作らない配置。判定の確認用）。
        let stage = RunnerStage(number: 1, pattern: "---PP3----", speed: 40)
        guard let platform = stage.platforms.first, let pit = stage.hazards.first else {
            Issue.record("台座か穴が無い"); return
        }
        #expect(pit.kind == .pit)
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: pit.start - 1, altitude: platform.top, vy: 0)
        #expect(field.distance > platform.end, "台座から降りて穴の手前にいる")
        var events: [RunnerEvent] = []
        for _ in 0..<600 where !events.contains(where: { $0.isTerminal }) {
            events += field.step(dt: 1.0 / 600)
        }
        #expect(events.contains(.fell))
    }

    /// 台座を乗り継ぐ（階段状の連続台座・#674 の受け入れ条件）。
    /// 1 基目を降りて 2 基目へ、を自動操縦の判断だけで通せること。
    @Test("連続して並んだ台座を順に乗り継げる")
    func ridesAcrossConsecutivePlatforms() {
        let stage = RunnerStage(number: 1, pattern: "---PP-PP-PP---", speed: 40)
        #expect(stage.platforms.count == 3, "3 基が別々の台座として展開される")
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        // どの台座にも足が乗ったことを 1 基ずつ確かめる。
        var ridden = Set<Int>()
        var frames = 0
        while frames < 60 * 120, !events.contains(where: { $0.isTerminal }) {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            events += field.step(dt: 1.0 / 60)
            for (index, platform) in stage.platforms.enumerated()
            where field.isGrounded && field.altitude == platform.top
                && platform.start < field.distance && field.distance < platform.end {
                ridden.insert(index)
            }
        }
        #expect(!events.contains(.crashed), "乗り継ぎの途中で台座に当たっている")
        #expect(events.contains(.reachedGoal), "ゴールまで通せていない")
        #expect(ridden.count == 3, "乗れた台座 \(ridden.sorted())")
    }

    /// 台座が無いコースでは接地面が地面のまま——既存 15 ステージの物差しが動いていないこと。
    @Test("台座の無いコースでは接地面が常に地面")
    func surfaceIsGroundWithoutPlatforms() {
        let field = RunnerField(stage: flatStage(segments: 8))
        for x in stride(from: 0.0, through: 8 * 64, by: 8) {
            #expect(field.surfaceY(at: x) == RunnerField.Metrics.groundY)
        }
    }

    @Test("同じピックアップは同じ走行中に一度しか取れない")
    func pickupIsCollectedOnlyOnce() {
        let stage = RunnerStage(number: 1, pattern: "--s---", speed: 40)
        #expect(stage.pickups.count == 1)
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        for _ in 0..<600 { events += field.step(dt: 1.0 / 60) }
        #expect(events.filter { $0 == .collectedSpeedItem }.count == 1, "重なっている間ずっと発火してはいけない")
        #expect(field.collectedPickupCount == 1)
    }
}

@Suite("チャリンコおじさん: 障害の展開")
struct RunnerHazardLayoutTests {

    @Test("区画記号が障害の位置と長さに展開される")
    func expandsSegments() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        let stage = RunnerStage(number: 1, pattern: "-3-n", speed: 40)
        #expect(stage.hazards.count == 2)
        // 穴は「表記の数字 + 1 タイル」の幅で展開される（会長QA: 見た目どおりの幅にする）。
        #expect(stage.hazards[0] == RunnerHazard(
            kind: .pit, start: segment + offset, length: RunnerRules.tileWidth * 4
        ))
        #expect(stage.hazards[1] == RunnerHazard(
            kind: .lowBlock, start: segment * 3 + offset, length: RunnerRules.tileWidth
        ))
        #expect(stage.length == segment * 4)
    }

    @Test("区画記号と障害の種類・高さの対応が定義どおり")
    func hazardKinds() {
        #expect(RunnerStage.segmentSpec("_") == nil, "穴の長さは 1〜3 の数字で書く")
        #expect(RunnerStage.segmentSpec("2")?.kind == .pit)
        // 実際のタイル数は表記の数字 + 1（会長QA: 穴の見た目の幅を広げた）。
        #expect(RunnerStage.segmentSpec("2")?.tiles == 3)
        #expect(RunnerStage.segmentSpec("n")?.kind == .lowBlock)
        #expect(RunnerStage.segmentSpec("t")?.kind == .tallBlock)
        #expect(RunnerStage.segmentSpec("-") == nil, "平地")
        #expect(RunnerHazardKind.pit.height == 0)
        #expect(RunnerHazardKind.lowBlock.height < RunnerHazardKind.tallBlock.height)
        #expect(RunnerHazardKind.tallBlock.height < RunnerRules.jumpApex, "跳んで越えられる高さ")
    }

    /// 鳥（`b`）の区画記号が正しく `RunnerHazardKind.bird` に展開されること
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。
    @Test("鳥の区画記号が正しく展開される")
    func birdSymbolExpandsToBirdHazard() {
        #expect(RunnerStage.segmentSpec("b")?.kind == .bird)
        #expect(RunnerStage.segmentSpec("b")?.tiles == 1)
        let stage = RunnerStage(number: 1, pattern: "--b---", speed: 40)
        #expect(stage.hazards.count == 1)
        #expect(stage.hazards.first?.kind == .bird)
        // 当たり判定・クリア可能性の数学は lowBlock/tallBlock と同じ（高さは両者の中間）。
        #expect(RunnerHazardKind.lowBlock.height < RunnerHazardKind.bird.height)
        #expect(RunnerHazardKind.bird.height < RunnerHazardKind.tallBlock.height)
        #expect(RunnerHazardKind.bird.height < RunnerRules.jumpApex, "跳んで越えられる高さ")
    }
}
