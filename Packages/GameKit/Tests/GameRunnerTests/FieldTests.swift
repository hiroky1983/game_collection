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

    @Test("押さないジャンプの頂点と滞空時間が定数どおり")
    func jumpArcMatchesRules() {
        var field = RunnerField(stage: flatStage())
        field.jump()
        field.endHold()
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

    @Test("押し続けると高く跳べる（大ジャンプ）")
    func holdingJumpsHigher() {
        func apex(holding: Bool) -> Double {
            var field = RunnerField(stage: flatStage())
            field.jump()
            if !holding { field.endHold() }
            var top: Double = 0
            var frames = 0
            while !field.isGrounded, frames < 400 {
                frames += 1
                _ = field.step(dt: 1.0 / 240)
                top = max(top, field.altitude)
            }
            return top
        }
        #expect(apex(holding: true) > apex(holding: false) + 3)
    }

    @Test("押しっぱなしでも浮き続けられない（上限は maxHoldTime）")
    func holdIsCapped() {
        var field = RunnerField(stage: flatStage(segments: 30))
        field.jump()
        var frames = 0
        while !field.isGrounded, frames < 60 * 10 {
            frames += 1
            _ = field.step(dt: 1.0 / 60)
        }
        #expect(field.isGrounded, "いつかは必ず着地する")
        #expect(Double(frames) / 60 < RunnerRules.jumpAirTime + RunnerRules.maxHoldTime * 2)
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
}
