import Core
import Foundation
import Testing
@testable import GameRunner

/// 動く障害（#796 飛び立つ鳥・#944 追い越す犬・#801 イノシシ）の軌道と当たり判定。
///
/// どれも**走者の距離で決まる決定論**（`RunnerHazard.frame(atRunnerDistance:)`）なので、
/// シミュレータ抜きで「出現・飛び立ち・追い越し・予告」の地点を数値で固定できる。
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

    // MARK: - 犬（#944）

    @Test("犬は予告の瞬間に画面の左（走者の後ろ）の外に現れ、走者を追い越して右へ消える")
    func dogOvertakesFromBehind() {
        let dog = Self.hazard(.dog)
        let bark = dog.dogBarkDistance
        let contact = dog.dogContactDistance
        let behind = RunnerField.Metrics.playerX
        let ahead = RunnerField.Metrics.width - RunnerField.Metrics.playerX
        #expect(dog.frame(atRunnerDistance: bark - 0.01) == nil, "予告の前は現れていない")
        #expect(abs(contact - bark - RunnerRules.dogChaseDistance) < 1e-9, "予告から触れるまでは 12 タイル")
        guard let spawned = dog.frame(atRunnerDistance: bark) else { Issue.record("予告の瞬間に現れない"); return }
        #expect(spawned.end < bark - behind, "現れた瞬間は画面の左の外（後端 \(spawned.end) vs 画面の左端 \(bark - behind)）")
        #expect(spawned.advance == RunnerRules.dogAdvance && spawned.advance > 1, "現れた瞬間から走者より速く走っている")
        #expect(spawned.top == RunnerHazardKind.lowBlock.height && spawned.bottom == 0, "当たり判定は低い岩と同じ高さの矩形")

        // 触れるまでは背中の後ろ、触れる瞬間に鼻先が背中に届き、そこからは前へ抜けていく。
        var previous = spawned.start
        for d in stride(from: bark + 1, through: contact + 60, by: 1) {
            guard let frame = dog.frame(atRunnerDistance: d) else { Issue.record("犬が消えた（\(d)）"); return }
            #expect(frame.start > previous, "止まらず右へ走り続ける（\(d)）")
            #expect(frame.end - frame.start == dog.length && frame.top == 5, "矩形は犬と一緒に動く")
            if d < contact { #expect(frame.end < d - Self.half, "触れる前は背中の後ろ（\(d)）") }
            previous = frame.start
        }
        guard let touching = dog.frame(atRunnerDistance: contact) else { Issue.record("犬が居ない"); return }
        #expect(abs(touching.end - (contact - Self.half)) < 1e-9, "触れる瞬間、鼻先が走者の背中に届く")
        #expect(abs(contact + Self.half - dog.start) < 1e-9, "そのとき走者の前端は置いた位置（区画中央）")
        let passed = dog.frame(atRunnerDistance: dog.encounter.end + Self.half)
        #expect((passed?.start ?? 0) >= dog.encounter.end + Self.half * 2 - 1e-9, "後端が抜けた瞬間、犬は走者の前")
        // 相対速度は走者の速さそのものなので、触れてから画面 1 つぶん（100）進めば前方 74 の先へ抜けている。
        let later = contact + RunnerField.Metrics.width
        let gone = dog.frame(atRunnerDistance: later)
        #expect((gone?.start ?? 0) > later + ahead, "走者が画面 1 つぶん進むまでに画面の右へ消えている（\(gone?.start ?? 0)）")

        // 走者から見た等価な静止区間。速さ 2 なら置いた位置の低い岩そのもの。
        let k = RunnerRules.dogAdvance
        let width = RunnerField.Metrics.playerWidth
        #expect(dog.encounter.start == dog.start)
        #expect(abs(dog.encounter.length - ((dog.length + width) / (k - 1) - width)) < 1e-9)
        #expect(dog.encounter == RunnerHazardEncounter(start: dog.start, length: dog.length, height: 5), "速さ 2 の犬は置いた位置の低い岩と同じ")
        #expect(dog.activeRange.lowerBound == bark && dog.activeRange.upperBound == dog.encounter.end + Self.half)
    }

    @Test("自動操縦は後ろから来る犬を、置いた位置の低い岩として前方に見る")
    func autoPilotSeesTheDogAsItsEquivalentBlock() {
        let stage = RunnerStage(number: 1, pattern: "---d---", speed: 40)
        let dog = stage.hazards[0]
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: dog.dogBarkDistance - 1, altitude: 0, vy: 0)
        #expect(field.nextHazard(from: field.playerMaxX) == nil, "予告の前は踏み切りの相手がいない")
        field.placeForTesting(distance: dog.dogBarkDistance + 1, altitude: 0, vy: 0)
        let seen = field.nextHazardFrame(from: field.playerMaxX)
        #expect(seen?.hazard == dog)
        #expect(seen?.frame == RunnerHazardFrame(start: dog.start, end: dog.end, bottom: 0, top: 5, advance: 0), "等価な静止区間を静止した岩の形で")
        #expect((dog.frame(atRunnerDistance: field.distance)?.end ?? 0) < field.playerMinX, "実際の犬はまだ後ろ")
        // 追い越されたあとは相手ではない（前を走り去るだけで追いつけない）。
        field.placeForTesting(distance: dog.encounter.end + Self.half + 1, altitude: 0, vy: 0)
        #expect(field.nextHazard(from: field.playerMaxX) == nil, "抜けたあとの犬は踏み切りの相手ではない")
        #expect((dog.frame(atRunnerDistance: field.distance)?.start ?? 0) > field.playerMaxX, "実際の犬は前を走っている")
    }

    @Test("犬は追い越す前に予告が 1 回出て、跳ばないと当たり、跳べば越えられる")
    func dogBarksOnceThenMustBeJumped() {
        for speed in [41.2, 54.4] {
            let stage = RunnerStage(number: 1, pattern: "---d---", speed: speed)
            let dog = stage.hazards[0]
            var idle = RunnerField(stage: stage)
            idle.placeForTesting(distance: dog.dogBarkDistance - 30, altitude: 0, vy: 0)
            var events: [RunnerEvent] = []
            var cueAt: Double?
            var crashedAt: Double?
            while idle.distance < dog.end + 40, !events.contains(where: { $0.isTerminal }) {
                let step = idle.step(dt: 1.0 / 600)
                if step.contains(.dogBarking) { cueAt = idle.distance }
                if step.contains(.crashed) { crashedAt = idle.distance }
                events += step
            }
            #expect(events.filter { $0 == .dogBarking }.count == 1, "速さ \(speed): 予告は 1 回")
            #expect(abs((cueAt ?? 0) - dog.dogBarkDistance) < 0.2, "速さ \(speed): 予告は触れる 12 タイル手前")
            #expect(events.contains(.crashed) && idle.lastMissCause == .animal, "速さ \(speed): 跳ばなければ犬に当たる")
            #expect((cueAt ?? .infinity) < (crashedAt ?? 0), "速さ \(speed): 予告は追い越される前")
            #expect(abs((crashedAt ?? 0) - dog.dogContactDistance) < 0.5, "速さ \(speed): 当たるのは鼻先が背中に触れる瞬間（\(crashedAt ?? 0)）")

            var piloted = RunnerField(stage: stage)
            piloted.placeForTesting(distance: dog.dogBarkDistance - 30, altitude: 0, vy: 0)
            events = []
            while piloted.distance < dog.end + 40, !events.contains(where: { $0.isTerminal }) {
                if RunnerAutoPilot.shouldJump(field: piloted) { piloted.jump() }
                if RunnerAutoPilot.shouldRelease(field: piloted) { piloted.endHold() }
                events += piloted.step(dt: 1.0 / 60)
            }
            #expect(!events.contains(.crashed), "速さ \(speed): 普通のジャンプで越えられない")
            #expect(events.contains(.landed))
            #expect(events.filter { $0 == .dogBarking }.count == 1, "速さ \(speed): 跳んでも予告は 1 回")
        }
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
