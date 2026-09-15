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

    /// 走者（矩形 `[d − 4, d + 4] × [0, head]`）が `hazard` と重なる走者の距離の範囲を、
    /// 距離を細かく刻んで実測する。`encounter` の検算に使う。`head` の既定は接地した走者の頭
    /// （11）。鳥（#945）は帯が頭より上にあって**跳んでいるあいだだけ当たる**ので、
    /// 呼び出し側が `head` を無限大にして横の重なりだけを測る。
    private static func measuredEncounter(
        _ hazard: RunnerHazard, from: Double, to: Double, head: Double = RunnerField.Metrics.playerHeight
    ) -> ClosedRange<Double>? {
        var lower: Double?, upper: Double?
        var d = from
        while d <= to {
            if let frame = hazard.frame(atRunnerDistance: d),
               frame.start < d + half, d - half < frame.end,
               frame.bottom < head, frame.top > 0 {
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
    /// 鳥（#945）は帯が頭より上を飛ぶので、横の重なりだけを測る（「跳んでいてはいけない区間」）。
    @Test("等価な静止区間は、当たり判定を刻んで測った重なりと一致する", arguments: [
        RunnerHazardKind.lowBlock, .bird, .dog, .boar,
    ])
    func encounterMatchesMeasuredOverlap(kind: RunnerHazardKind) {
        let hazard = Self.hazard(kind)
        let encounter = hazard.encounter
        let head: Double = kind == .bird ? .infinity : RunnerField.Metrics.playerHeight
        guard let measured = Self.measuredEncounter(hazard, from: hazard.start - 200, to: hazard.start + 200, head: head) else {
            Issue.record("\(kind) が一度も走者と重ならない")
            return
        }
        // 前端が触れる地点 = `encounter.start − 4`、後端が抜ける地点 = `encounter.end + 4`。
        #expect(abs(measured.lowerBound - (encounter.start - Self.half)) < 0.02, "\(kind): 触れ始め \(measured.lowerBound) vs \(encounter.start - Self.half)")
        #expect(abs(measured.upperBound - (encounter.end + Self.half)) < 0.02, "\(kind): 抜け \(measured.upperBound) vs \(encounter.end + Self.half)")
        if kind == .bird {
            // 鳥の `height` は止まっているあいだの上端（岩と同じ物差しで踏み切りの余裕・間隔を取るための値）。
            #expect(encounter.height == RunnerHazardKind.birdLowTop)
        } else {
            #expect(encounter.height == RunnerHazardKind.lowBlock.height, "出会うときの高さは低い岩と同じ")
        }
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

    // MARK: - 飛び立つ鳥（#796 → #945「跳んだ先にいる障害」）

    @Test("鳥は前端が手前 6 タイルに入るまで動かず、そこから 1 タイルで跳んだ先の高さまで上がって水平に飛ぶ")
    func birdTakesOffWhenApproached() {
        let bird = Self.hazard(.bird)
        let takeoff = bird.birdTakeoffDistance
        #expect(takeoff + Self.half == bird.start - 6 * RunnerRules.tileWidth, "前端が 6 タイル手前")
        for d in [takeoff - 50, takeoff - 1, takeoff] {
            let frame = bird.frame(atRunnerDistance: d)
            #expect(frame?.start == bird.start && frame?.advance == 0, "まだ止まっている（\(d)）")
            #expect(frame?.top == RunnerHazardKind.birdLowTop, "止まっているときの高さは低い岩と同じ")
        }
        // 飛び立ってから 1 タイル（走者の進みで 20）で帯の下端が跳んだ先の高さに届く。そのあいだは
        // 一定の傾きで上がり、右へ進んでいる。
        let highAt = takeoff + RunnerRules.birdClimbDistance / RunnerRules.birdAdvance
        var previousBottom = RunnerHazardKind.bird.bottom
        for d in stride(from: takeoff + 0.5, through: highAt, by: 2) {
            guard let frame = bird.frame(atRunnerDistance: d) else { Issue.record("鳥が居ない"); return }
            #expect(frame.bottom > previousBottom, "上がり続けている（\(d)）")
            #expect(frame.advance == RunnerRules.birdAdvance)
            #expect(frame.start > bird.start, "右へ進んでいる")
            #expect(abs(frame.top - frame.bottom - RunnerHazardKind.birdBandHeight) < 1e-9, "帯の厚みは変わらない")
            previousBottom = frame.bottom
        }
        let high = bird.frame(atRunnerDistance: highAt)
        #expect(abs((high?.bottom ?? 0) - RunnerHazardKind.birdMeetBottom) < 1e-9, "1 タイルで跳んだ先の高さに届く")
        // そこから先は同じ高さで飛び続ける（走者が下を抜けて追い越すので、後ろへ置き去りになる）。
        for d in [highAt + 10, highAt + 100] {
            let beyond = bird.frame(atRunnerDistance: d)
            #expect(abs((beyond?.bottom ?? 0) - RunnerHazardKind.birdMeetBottom) < 1e-9, "上がりきったあとは水平（\(d)）")
            #expect(beyond?.advance == RunnerRules.birdAdvance, "横には進み続ける")
        }
    }

    /// #945 の受け入れ条件 1: **走者が着く時点で帯の下端が「普通のジャンプの頂点付近」にある**。
    /// 前端が帯に触れる瞬間（`encounter.start − 4`）の帯の下端は頂点（`jumpApex`）そのもので、
    /// 接地した頭（11）より上——そのまま抜けられる高さ。横に重なっているあいだずっと同じ高さ。
    /// 動きは走者の距離で決まるので速さに依らず、この値は全ステージ・エンドレスで共通。
    @Test("走者の前端が帯に触れる時点で、帯の下端は普通のジャンプの頂点にあり、抜けるまで下がらない")
    func birdMeetsTheRunnerAtJumpApex() {
        let bird = Self.hazard(.bird)
        let contact = bird.encounter.start - Self.half
        guard let frame = bird.frame(atRunnerDistance: contact) else { Issue.record("鳥が居ない"); return }
        #expect(abs(frame.start - (contact + Self.half)) < 1e-9, "前端がちょうど帯に触れている")
        #expect(abs(frame.bottom - RunnerRules.jumpApex) < 1e-9, "帯の下端 = 普通のジャンプの頂点")
        #expect(frame.bottom >= RunnerField.Metrics.playerHeight + 3, "接地した頭の上に 3 の余裕（走ったまま抜けられる）")
        #expect(frame.top > RunnerRules.jumpApex, "帯の上端は頂点より上（1 段では上を越えられない）")
        for d in stride(from: contact, through: bird.encounter.end + Self.half, by: 0.5) {
            #expect((bird.frame(atRunnerDistance: d)?.bottom ?? 0) >= RunnerField.Metrics.playerHeight + 3, "重なっているあいだ帯が下がらない（\(d)）")
        }
    }

    /// 自動操縦は帯の下端が頭より低い鳥を「岩」として踏み切りの対象にする（`RunnerField.nextHazard`）。
    /// 鳥がその間合い（`RunnerAutoPilot.lead`・上限の速さでいちばん長い）に入る**前に**頭を越えて
    /// いなければ、自動操縦は跳んで鳥に当たる。`RunnerRules.birdClimbDistance` の上限を固定する。
    @Test("鳥は、自動操縦の踏み切りの間合いに入るより手前で頭より上へ上がりきる")
    func birdRisesAboveTheHeadBeforeTheTakeOffWindow() {
        let bird = Self.hazard(.bird)
        var d = bird.birdTakeoffDistance
        while let frame = bird.frame(atRunnerDistance: d), frame.bottom < RunnerField.Metrics.playerHeight {
            d += 0.01
        }
        guard let frame = bird.frame(atRunnerDistance: d) else { Issue.record("鳥が居ない"); return }
        let gap = frame.start - d
        let lead = RunnerAutoPilot.lead(for: bird, frame: frame, speed: RunnerRules.endlessMaxSpeed)
        #expect(gap > lead + 2, "頭を越えた時点の間合い \(gap) が踏み切りの間合い \(lead) に食い込んでいる")
    }

    /// #945 の受け入れ条件 2（3 ケース）。距離で決まる相対軌道は 1 通りなので、違いは踏み切りの時機だけ:
    /// 1. 何もしない（走ったまま） → 下を抜けられる
    /// 2. 着いてから跳ぶ（前端が帯に触れた瞬間に踏み切る） → 頭が帯に入って当たる（死因は鳥）
    /// 3. 飛び立った瞬間に跳ぶ（早すぎる） → 速い面では降りてくるところに鳥がいて当たる（跳んだ先にいる）
    @Test("鳥は、走ったまま下を抜けられ／着いてから跳ぶと当たり／速い面では早すぎる跳びも跳んだ先で当たる")
    func birdThreeCases() {
        func run(speed: Double, jumpAt: Double?) -> (events: [RunnerEvent], field: RunnerField) {
            let stage = RunnerStage(number: 1, pattern: "--b---", speed: speed)
            let bird = stage.hazards[0]
            var field = RunnerField(stage: stage)
            field.placeForTesting(distance: bird.activeRange.lowerBound - 20, altitude: 0, vy: 0)
            var events: [RunnerEvent] = []
            var jumped = false
            // 後端が抜けて着地するところまで見る。
            let goal = bird.encounter.end + 40
            while field.distance < goal, !events.contains(where: { $0.isTerminal }) {
                if let jumpAt, !jumped, field.distance >= jumpAt {
                    field.jump(); jumped = true
                }
                events += field.step(dt: 1.0 / 600)
            }
            return (events, field)
        }
        let slow = RunnerRules.baseSpeed
        let fast = RunnerStage.all.map(\.speed).max() ?? 54.4
        let contact = RunnerStage(number: 1, pattern: "--b---", speed: slow).hazards[0].encounter.start - Self.half
        let takeoff = RunnerStage(number: 1, pattern: "--b---", speed: slow).hazards[0].birdTakeoffDistance

        // 1. 何もしない → 抜けられる（遅い面・速い面とも）。
        for speed in [slow, fast] {
            let idle = run(speed: speed, jumpAt: nil)
            #expect(!idle.events.contains(where: { $0.isTerminal }), "速さ \(speed): 走ったままで当たる")
            #expect(idle.field.isGrounded && idle.field.distance >= contact + 40, "速さ \(speed): 鳥の向こうまで走り抜けている")
        }

        // 2. 着いてから跳ぶ → 当たる（死因は鳥）。
        for speed in [slow, fast] {
            let late = run(speed: speed, jumpAt: contact)
            #expect(late.events.contains(.crashed), "速さ \(speed): 着いてから跳んでも当たらない")
            #expect(late.field.lastMissCause == .bird)
        }

        // 3. 飛び立った瞬間に跳ぶ。速い面では 1 回のジャンプで進む距離（40.8）が触れるまでの進み（30）
        //    より長く、降りてくるところに鳥がいる。
        let early = run(speed: fast, jumpAt: takeoff)
        #expect(early.events.contains(.crashed), "速さ \(fast): 飛び立った瞬間に跳ぶと跳んだ先に鳥がいるはず")
        #expect(early.field.lastMissCause == .bird)
    }

    // MARK: - 犬（#800）

    @Test("犬は前端が手前 16 タイルに入ると走り出し、手前 4 タイルまで詰まると止まる")
    func dogRunsThenStops() {
        let dog = Self.hazard(.dog)
        let start = dog.dogStartDistance
        let stop = dog.dogStopDistance
        #expect(dog.dogOrigin < dog.start, "止まる位置（区画中央）より手前に立っている")
        #expect(start + Self.half == dog.dogOrigin - RunnerRules.dogTriggerDistance)
        #expect(dog.frame(atRunnerDistance: start - 1)?.start == dog.dogOrigin, "走り出す前は立ったまま")
        // 走っているあいだ、前端との間合いは 64 から 16 へ縮み、0 にはならない（追いつけない）。
        for d in stride(from: start, through: stop, by: 2) {
            guard let frame = dog.frame(atRunnerDistance: d) else { Issue.record("犬が居ない"); return }
            let gap = frame.start - (d + Self.half)
            #expect(gap >= RunnerRules.dogStopGap - 1e-9, "走っている犬に追いついてしまう（\(d): \(gap)）")
            #expect(gap <= RunnerRules.dogTriggerDistance + 1e-9)
        }
        let stopped = dog.frame(atRunnerDistance: stop)
        #expect(stopped?.start == dog.start && stopped?.advance == 0, "区画中央で止まる")
        #expect(abs((stopped?.start ?? 0) - (stop + Self.half) - RunnerRules.dogStopGap) < 1e-9, "止まる間合いは 4 タイル")
        #expect(dog.frame(atRunnerDistance: stop + 100)?.start == dog.start, "止まったら動かない")
        #expect(dog.encounter == RunnerHazardEncounter(start: dog.start, length: dog.length, height: 5), "止まった犬は低い岩そのもの")
    }

    @Test("犬に追いついた時点で跳ばないと当たり、跳べば越えられる")
    func dogMustBeJumped() {
        let stage = RunnerStage(number: 1, pattern: "---d---", speed: 40)
        let dog = stage.hazards[0]
        var idle = RunnerField(stage: stage)
        idle.placeForTesting(distance: dog.dogStartDistance - 10, altitude: 0, vy: 0)
        var events: [RunnerEvent] = []
        while idle.distance < dog.end + 20, !events.contains(where: { $0.isTerminal }) {
            events += idle.step(dt: 1.0 / 600)
        }
        #expect(events.contains(.crashed) && idle.lastMissCause == .animal)
        #expect(idle.distance > dog.dogStopDistance, "止まってから当たる（走っている犬には追いつけない）")

        var piloted = RunnerField(stage: stage)
        piloted.placeForTesting(distance: dog.dogStartDistance - 10, altitude: 0, vy: 0)
        events = []
        while piloted.distance < dog.end + 20, !events.contains(where: { $0.isTerminal }) {
            if RunnerAutoPilot.shouldJump(field: piloted) { piloted.jump() }
            if RunnerAutoPilot.shouldRelease(field: piloted) { piloted.endHold() }
            events += piloted.step(dt: 1.0 / 60)
        }
        #expect(!events.contains(.crashed))
        #expect(events.contains(.landed))
    }

    // MARK: - イノシシ（#801）

    @Test("イノシシは予告から出会いまでの走者の進みが一定（18 タイル）で、予告は 1 回だけ")
    func boarGraceIsConstant() {
        for speed in [41.2, 54.4] {
            let stage = RunnerStage(number: 1, pattern: "----i---", speed: speed)
            let boar = stage.hazards[0]
            #expect(boar.frame(atRunnerDistance: boar.boarChargeStartDistance - 0.01) == nil, "予告の前は現れていない")
            var field = RunnerField(stage: stage)
            field.placeForTesting(distance: boar.boarChargeStartDistance - 30, altitude: 0, vy: 0)
            var events: [RunnerEvent] = []
            var cueAt: Double?
            while field.distance < boar.start + 50, !events.contains(where: { $0.isTerminal }) {
                let step = field.step(dt: 1.0 / 600)
                if step.contains(.boarCharging) { cueAt = field.distance }
                events += step
            }
            #expect(events.filter { $0 == .boarCharging }.count == 1, "予告は 1 回")
            #expect(abs((cueAt ?? 0) - boar.boarChargeStartDistance) < 0.2, "予告は前端が 18 タイル手前に入った瞬間")
            #expect(events.contains(.crashed) && field.lastMissCause == .animal)
            // 予告から出会い（前端が触れる）までの走者の進みは速さに依らず 72。
            #expect(abs(field.distance - (boar.boarChargeStartDistance + RunnerRules.boarChargeDistance)) < 0.5, "速さ \(speed): 出会いの地点 \(field.distance)")
        }
    }

    @Test("イノシシは跳べば越えられ、跳んだ先で着地できる")
    func boarCanBeJumped() {
        let stage = RunnerStage(number: 1, pattern: "----i---", speed: 41.2)
        let boar = stage.hazards[0]
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: boar.boarChargeStartDistance - 30, altitude: 0, vy: 0)
        var events: [RunnerEvent] = []
        while field.distance < boar.start + 50, !events.contains(where: { $0.isTerminal }) {
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            events += field.step(dt: 1.0 / 60)
        }
        #expect(!events.contains(.crashed))
        #expect(events.contains(.landed))
    }

    @Test("岩の手前に置いたイノシシは岩で止まり、岩と一緒に跳び越せる")
    func boarStopsAtTheRock() {
        let stage = RunnerStage(number: 1, pattern: "---it---", speed: 41.2)
        let boar = stage.hazards[0], rock = stage.hazards[1]
        #expect(boar.kind == .boar && rock.kind == .tallBlock)
        #expect(boar.stopAt == rock.end, "次の区画の岩の右端で止まる")
        #expect(boar.boarSpawn > rock.end, "出現点は岩より先（だから岩にぶつかる）")
        // 突進してすぐ岩にぶつかり、以後は動かない。
        let far = boar.boarChargeStartDistance + 20
        let stopped = boar.frame(atRunnerDistance: far)
        #expect(stopped?.start == rock.end && stopped?.advance == 0)
        #expect(boar.frame(atRunnerDistance: far + 100)?.start == rock.end)

        // 岩の手前で跳ばなければ岩に当たる（死因は岩）。跳べば岩ごと越えられる。
        var idle = RunnerField(stage: stage)
        idle.placeForTesting(distance: boar.boarChargeStartDistance - 10, altitude: 0, vy: 0)
        var events: [RunnerEvent] = []
        while idle.distance < rock.end + 30, !events.contains(where: { $0.isTerminal }) {
            events += idle.step(dt: 1.0 / 600)
        }
        #expect(events.contains(.crashed) && idle.lastMissCause == .rock)

        var piloted = RunnerField(stage: stage)
        piloted.placeForTesting(distance: boar.boarChargeStartDistance - 10, altitude: 0, vy: 0)
        events = []
        while piloted.distance < rock.end + 30, !events.contains(where: { $0.isTerminal }) {
            if RunnerAutoPilot.shouldJump(field: piloted) { piloted.jump() }
            if RunnerAutoPilot.shouldRelease(field: piloted) { piloted.endHold() }
            events += piloted.step(dt: 1.0 / 60)
        }
        #expect(!events.contains(.crashed), "岩と止まったイノシシを一緒に越えられない")
        #expect(RunnerEndlessCourse.isClearableWithBoarBehind(rock, speed: stage.speed))
    }

    @Test("出会いの地点より手前の岩ではイノシシは止まらない")
    func boarIgnoresRocksBehindTheMeetingPoint() {
        let stage = RunnerStage(number: 1, pattern: "---ti---", speed: 41.2)
        let boar = stage.hazards[1]
        #expect(boar.kind == .boar && boar.stopAt == nil)
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

    // MARK: - 手応え

    /// `services.feedback` に届いた呼び出しを記録するスパイ。
    @MainActor
    private final class SpyFeedback: FeedbackService {
        private(set) var impacts: [FeedbackImpact] = []
        func impact(_ style: FeedbackImpact) { impacts.append(style) }
        func notify(_ type: FeedbackNotice) {}
    }

    @MainActor
    @Test("イノシシの予告で「ドドド」（rigid）が 1 回鳴る")
    func boarChargeFeedback() {
        let spy = SpyFeedback()
        let model = RunnerModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy),
            startingAt: 7, preference: makePreference("boar-cue")
        )
        guard let boar = model.stage.hazards.first(where: { $0.kind == .boar }) else {
            Issue.record("7 面にイノシシが無い"); return
        }
        model.press(); model.release()   // スタート（rigid）
        let startCues = spy.impacts.filter { $0 == .rigid }.count
        var frames = 0
        while model.phase.isRunning, model.distance < boar.boarChargeStartDistance + 10, frames < 60 * 60 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.phase.isRunning, "予告の地点まで走れている")
        #expect(spy.impacts.filter { $0 == .rigid }.count == startCues + 1)
    }
}
