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

    @Test("走ると距離が速さ×時間だけ進む")
    func runsForward() {
        var field = RunnerField(stage: flatStage())
        for _ in 0..<60 { _ = field.step(dt: 1.0 / 60) }
        #expect(abs(field.distance - 40) < 0.5)
        #expect(field.isGrounded, "平地では接地したまま")
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

    @Test("空中では二段ジャンプできない")
    func noDoubleJump() {
        var field = RunnerField(stage: flatStage())
        let first = field.jump()
        #expect(first)
        _ = field.step(dt: 1.0 / 60)
        let second = field.jump()
        #expect(!second, "接地していないので踏み切れない")
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
        #expect(stage.hazards[0] == RunnerHazard(
            kind: .pit, start: segment + offset, length: RunnerRules.tileWidth * 3
        ))
        #expect(stage.hazards[1] == RunnerHazard(
            kind: .lowBlock, start: segment * 3 + offset, length: RunnerRules.tileWidth
        ))
        #expect(stage.length == segment * 4)
    }

    @Test("記号と高さの対応が定義どおり")
    func hazardHeights() {
        #expect(RunnerHazardKind.from(symbol: "_") == .pit)
        #expect(RunnerHazardKind.from(symbol: "n") == .lowBlock)
        #expect(RunnerHazardKind.from(symbol: "t") == .tallBlock)
        #expect(RunnerHazardKind.from(symbol: ".") == nil)
        #expect(RunnerHazardKind.pit.height == 0)
        #expect(RunnerHazardKind.lowBlock.height < RunnerHazardKind.tallBlock.height)
    }
}
