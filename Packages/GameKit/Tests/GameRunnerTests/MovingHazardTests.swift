import Core
import Foundation
import Testing
@testable import GameRunner

/// 動く障害（#796 飛び立つ鳥・#800 犬・#801 イノシシ）の軌道と当たり判定。
///
/// どれも**走者の距離で決まる決定論**（`RunnerHazard.frame(atRunnerDistance:)`）なので、
/// シミュレータ抜きで「出現・飛び立ち・追いつき・予告」の地点を数値で固定できる。
/// ステージの成立条件が使う等価な静止区間（`RunnerHazard.encounter`）が実際の当たり判定と
/// 一致することも、ここで走査して確かめる。
@Suite("チャリンコおじさん: 動く障害")
struct RunnerHazardMotionTests {
    private static let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
    private static let half = RunnerField.Metrics.playerHalfWidth

    /// 接地した走者（矩形 `[d − 4, d + 4] × [0, 11]`）が `hazard` と重なる走者の距離の範囲を、
    /// 距離を細かく刻んで実測する。`encounter` の検算に使う。
    private static func measuredEncounter(_ hazard: RunnerHazard, from: Double, to: Double) -> ClosedRange<Double>? {
        var lower: Double?, upper: Double?
        var d = from
        while d <= to {
            if let frame = hazard.frame(atRunnerDistance: d),
               frame.start < d + half, d - half < frame.end,
               frame.bottom < RunnerField.Metrics.playerHeight, frame.top > 0 {
                lower = lower ?? d
                upper = d
            }
            d += 0.01
        }
        guard let lower, let upper else { return nil }
        return lower...upper
    }

    /// ステージ制と同じ置き方で 1 つ置く（区画中央）。
    private static func hazard(_ kind: RunnerHazardKind, segmentIndex: Int = 4, stopAt: Double? = nil) -> RunnerHazard {
        RunnerHazard(
            kind: kind,
            start: Double(segmentIndex) * segment + Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth,
            length: RunnerRules.tileWidth,
            stopAt: stopAt
        )
    }

    // MARK: - 等価な静止区間

    /// `encounter`（成立条件が使う静的換算）が、実際の当たり判定（`frame`）を刻んで測った
    /// 重なりの範囲と一致すること。ここがずれると、テストは緑なのに詰む配置ができる。
    @Test("等価な静止区間は、当たり判定を刻んで測った重なりと一致する", arguments: [
        RunnerHazardKind.lowBlock, .bird, .dog, .boar,
    ])
    func encounterMatchesMeasuredOverlap(kind: RunnerHazardKind) {
        let hazard = Self.hazard(kind)
        let encounter = hazard.encounter
        guard let measured = Self.measuredEncounter(hazard, from: hazard.start - 200, to: hazard.start + 200) else {
            Issue.record("\(kind) が一度も走者と重ならない")
            return
        }
        // 前端が触れる地点 = `encounter.start − 4`、後端が抜ける地点 = `encounter.end + 4`。
        #expect(abs(measured.lowerBound - (encounter.start - Self.half)) < 0.02, "\(kind): 触れ始め \(measured.lowerBound) vs \(encounter.start - Self.half)")
        #expect(abs(measured.upperBound - (encounter.end + Self.half)) < 0.02, "\(kind): 抜け \(measured.upperBound) vs \(encounter.end + Self.half)")
        #expect(encounter.height == RunnerHazardKind.lowBlock.height, "出会うときの高さは低い岩と同じ")
    }

    @Test("岩で止まったイノシシの等価な静止区間は、岩の右側の 1 タイル")
    func stoppedBoarEncounterIsAtTheRock() {
        let rock = Self.hazard(.tallBlock, segmentIndex: 5)
        let boar = Self.hazard(.boar, segmentIndex: 4, stopAt: rock.end)
        #expect(boar.encounter == RunnerHazardEncounter(start: rock.end, length: RunnerRules.tileWidth, height: 5))
        let measured = Self.measuredEncounter(boar, from: boar.start - 200, to: boar.start + 200)
        #expect(measured?.lowerBound.rounded() == (rock.end - Self.half).rounded())
    }

    /// 走っている最中の踏み切り判断（相対速度で見る `lead(for:frame:speed:)`）と、成立条件が
    /// 使う静的な余裕（`lead(for:speed:)` を `encounter` に当てる）が**同じ踏み切り地点**を指すこと。
    @Test("動く相手への踏み切り地点は、静的換算と相対速度の見積もりで一致する", arguments: [
        RunnerHazardKind.bird, .boar,
    ])
    func dynamicLeadAgreesWithStaticLead(kind: RunnerHazardKind) {
        let hazard = Self.hazard(kind)
        let speed = 40.0
        let takeOff = hazard.encounter.start - RunnerAutoPilot.lead(for: hazard, speed: speed)
        guard let frame = hazard.frame(atRunnerDistance: takeOff) else { Issue.record("\(kind) が現れていない"); return }
        let dynamic = RunnerAutoPilot.lead(for: hazard, frame: frame, speed: speed)
        #expect(abs((frame.start - takeOff) - dynamic) < 1e-6, "\(kind): 相対速度の見積もり \(dynamic) vs 実際の間合い \(frame.start - takeOff)")
    }

    // MARK: - 飛び立つ鳥（#796）

    @Test("鳥は前端が手前 6 タイルに入るまで動かず、そこから右上へ飛び立つ")
    func birdTakesOffWhenApproached() {
        let bird = Self.hazard(.bird)
        let takeoff = bird.birdTakeoffDistance
        #expect(takeoff + Self.half == bird.start - 6 * RunnerRules.tileWidth, "前端が 6 タイル手前")
        for d in [takeoff - 50, takeoff - 1, takeoff] {
            let frame = bird.frame(atRunnerDistance: d)
            #expect(frame?.start == bird.start && frame?.advance == 0, "まだ止まっている（\(d)）")
            #expect(frame?.top == RunnerHazardKind.birdLowTop, "止まっているときも高さは低い岩と同じ")
        }
        // 飛び立ってから 3 タイルは低いまま、そこから上がって 3 タイルで下端が 13。
        let lowEnd = takeoff + RunnerRules.birdLowDistance / RunnerRules.birdAdvance
        let highAt = lowEnd + RunnerRules.birdClimbDistance / RunnerRules.birdAdvance
        for d in stride(from: takeoff + 0.5, through: lowEnd, by: 3) {
            let frame = bird.frame(atRunnerDistance: d)
            #expect(frame?.top == RunnerHazardKind.birdLowTop, "低く飛んでいる（\(d)）")
            #expect(frame?.advance == RunnerRules.birdAdvance)
            #expect((frame?.start ?? 0) > bird.start, "右へ進んでいる")
        }
        let high = bird.frame(atRunnerDistance: highAt)
        #expect(abs((high?.bottom ?? 0) - RunnerHazardKind.birdHighBottom) < 1e-9, "3 タイルで 13 に届く")
        // 13 で止まらず、同じ傾きで上がり続ける（走者は追い越しているので、鳥は後ろで画面外へ抜ける）。
        let beyond = bird.frame(atRunnerDistance: highAt + 100)
        let climbed = (beyond?.bottom ?? 0) - RunnerHazardKind.birdHighBottom
        #expect(abs(climbed - 100 * RunnerRules.birdAdvance * RunnerRules.birdClimbSlope) < 1e-9, "13 に届いたあとも同じ傾きで上がる")
    }

    /// #796 の受け入れ条件（3 ケース）。
    /// 距離で決まる相対軌道は 1 通りなので、違いは踏み切りの時機だけ:
    /// 1. 何もしない → 当たる（死因は鳥）
    /// 2. 岩と同じ間合い（自動操縦）で普通に跳ぶ → 越えられる
    /// 3. 早く跳びすぎて降りるところに鳥がいる → 1 段では当たり、頂点で 2 段目を使えば抜けられる
    @Test("鳥は、何もしないと当たり／普通に跳べば越え／早すぎた跳びは 2 段目で抜けられる")
    func birdThreeCases() {
        let stage = RunnerStage(number: 1, pattern: "--b---", speed: 40)
        let bird = stage.hazards[0]
        // 跳んだ先で着地するところまで見る（普通のジャンプは鳥を越えた先 20 ほどに降りる）。
        let goal = bird.encounter.end + 40

        func run(jumpAt: Double?, doubleJump: Bool) -> (events: [RunnerEvent], field: RunnerField) {
            var field = RunnerField(stage: stage)
            field.placeForTesting(distance: bird.activeRange.lowerBound - 20, altitude: 0, vy: 0)
            var events: [RunnerEvent] = []
            var jumps = 0
            while field.distance < goal, !events.contains(where: { $0.isTerminal }) {
                if let jumpAt, jumps == 0, field.distance >= jumpAt {
                    field.jump(); jumps = 1
                } else if doubleJump, jumps == 1, !field.isGrounded, field.vy <= 0 {
                    field.jump(); jumps = 2
                }
                events += field.step(dt: 1.0 / 600)
            }
            return (events, field)
        }

        // 1. 何もしない。
        let idle = run(jumpAt: nil, doubleJump: false)
        #expect(idle.events.contains(.crashed))
        #expect(idle.field.lastMissCause == .bird)

        // 2. 自動操縦と同じ間合い（等価な静止区間に対する岩と同じ余裕）で跳ぶ。
        let timed = run(jumpAt: bird.encounter.start - RunnerAutoPilot.lead(for: bird, speed: stage.speed), doubleJump: false)
        #expect(!timed.events.contains(.crashed), "普通のジャンプで越えられない")
        #expect(timed.events.contains(.landed))

        // 3. 飛び立った瞬間に跳ぶ（早すぎる）。
        let early = run(jumpAt: bird.birdTakeoffDistance, doubleJump: false)
        #expect(early.events.contains(.crashed), "早すぎる 1 段だけで越えられてしまう")
        let rescued = run(jumpAt: bird.birdTakeoffDistance, doubleJump: true)
        #expect(!rescued.events.contains(.crashed), "2 段目で救えない")
    }

    // MARK: - 死因（#796 `game_end` の `cause`）

    @Test("ミスの原因は、穴・岩・台座の正面・鳥・動物で分かれる")
    func missCauses() {
        func cause(_ pattern: String, at distance: Double, altitude: Double = 0) -> AnalyticsEndCause? {
            let stage = RunnerStage(number: 1, pattern: pattern, speed: 40)
            var field = RunnerField(stage: stage)
            field.placeForTesting(distance: distance, altitude: altitude, vy: 0)
            #expect(field.lastMissCause == nil)
            var events: [RunnerEvent] = []
            for _ in 0..<600 where !events.contains(where: { $0.isTerminal }) {
                events += field.step(dt: 1.0 / 600)
            }
            return field.lastMissCause
        }
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        #expect(cause("--1---", at: Self.segment * 2 + offset - 6) == .pit)
        #expect(cause("--n---", at: Self.segment * 2 + offset - 6) == .rock)
        #expect(cause("--t---", at: Self.segment * 2 + offset - 6) == .rock)
        #expect(cause("--P---", at: Self.segment * 2 - 6) == .rock, "台座の正面は岩と同じ")
        #expect(RunnerHazardKind.bird.missCause == .bird)
        #expect(RunnerHazardKind.dog.missCause == .animal)
        #expect(RunnerHazardKind.boar.missCause == .animal)
        #expect(AnalyticsEndCause.allCases.count == 4)
    }
}
