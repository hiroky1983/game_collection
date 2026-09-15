import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport

/// 動く障害（#796 飛び立つ鳥・#955 前から歩いて来る犬・#801 イノシシ）の軌道と当たり判定。
///
/// どれも**走者の距離で決まる決定論**（`RunnerHazard.frame(atRunnerDistance:)`）なので、
/// シミュレータ抜きで「出現・飛び立ち・すれ違い・予告」の地点を数値で固定できる。
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
        RunnerHazardKind.bird, .dog, .boar,
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

    // MARK: - 犬（#955）

    /// 受け入れ条件 1: 右から現れ、左へ歩き、走者とすれ違って左へ消える。
    @Test("犬は画面の右の外に現れ、左へ歩いて来て走者とすれ違い、画面の左へ消える")
    func dogWalksInFromTheFront() {
        let dog = Self.hazard(.dog)
        let appear = dog.dogAppearDistance
        let contact = dog.dogContactDistance
        let behind = RunnerField.Metrics.playerX
        let ahead = RunnerField.Metrics.width - RunnerField.Metrics.playerX
        #expect(dog.frame(atRunnerDistance: appear - 0.01) == nil, "現れる前は居ない")
        #expect(abs(contact - appear - RunnerRules.dogApproachDistance) < 1e-9, "現れてから触れるまでは 14 タイル")
        guard let spawned = dog.frame(atRunnerDistance: appear) else { Issue.record("現れない"); return }
        #expect(spawned.start > appear + ahead, "現れた瞬間は画面の右の外（鼻先 \(spawned.start) vs 画面の右端 \(appear + ahead)）")
        #expect(spawned.advance == -RunnerRules.dogAdvance && spawned.advance < 0 && spawned.advance > -1, "現れた瞬間から走者より遅く左へ歩いている")
        #expect(spawned.top == RunnerHazardKind.lowBlock.height && spawned.bottom == 0, "当たり判定は低い岩と同じ高さの矩形")

        // 触れるまでは前端の前、触れる瞬間に鼻先が前端に届き、そこからは体の中を抜けて後ろへ。
        var previous = spawned.start
        for d in stride(from: appear + 1, through: contact + 60, by: 1) {
            guard let frame = dog.frame(atRunnerDistance: d) else { Issue.record("犬が消えた（\(d)）"); return }
            #expect(frame.start < previous, "止まらず左へ歩き続ける（\(d)）")
            #expect(frame.end - frame.start == dog.length && frame.top == 5, "矩形は犬と一緒に動く")
            if d < contact { #expect(frame.start > d + Self.half, "触れる前は前端の前（\(d)）") }
            previous = frame.start
        }
        guard let touching = dog.frame(atRunnerDistance: contact) else { Issue.record("犬が居ない"); return }
        #expect(abs(touching.start - (contact + Self.half)) < 1e-9, "触れる瞬間、鼻先が走者の前端に届く")
        #expect(abs(touching.start - dog.start) < 1e-9, "そのとき鼻先は置いた位置（区画中央）")
        let passed = dog.frame(atRunnerDistance: dog.encounter.end + Self.half)
        #expect(abs((passed?.end ?? .infinity) - dog.encounter.end) < 1e-9, "後端が抜けた瞬間、犬の尻尾が走者の背中（\(dog.encounter.end)）に届く")
        // 触れてから画面 1 つぶん（100）進めば、後ろ 26 の外へ消えている。
        let later = contact + RunnerField.Metrics.width
        let gone = dog.frame(atRunnerDistance: later)
        #expect((gone?.end ?? .infinity) < later - behind, "走者が画面 1 つぶん進むまでに画面の左へ消えている（\(gone?.end ?? 0)）")

        // 走者から見た等価な静止区間。イノシシと同じ式で、静止した低い岩（長さ 4）より短い。
        let k = RunnerRules.dogAdvance
        let width = RunnerField.Metrics.playerWidth
        #expect(dog.encounter.start == dog.start)
        #expect(abs(dog.encounter.length - ((dog.length + width) / (1 + k) - width)) < 1e-9)
        #expect(dog.encounter.length >= 0 && dog.encounter.length < Self.hazard(.lowBlock).encounter.length, "重なりは静止した低い岩より短い（\(dog.encounter.length)）")
        #expect(dog.activeRange.lowerBound == appear && dog.activeRange.upperBound == dog.encounter.end + Self.half)
    }

    /// 受け入れ条件 3: 画面に入ってから触れるまで 1.5 秒以上（1 面の速さ）。
    /// 画面の先読み（前端から 70）を相対速度 `1 + dogAdvance` で詰めるので、`dogAdvance` の上限を固定する。
    @Test("犬は画面に見えてから触れるまで、1 面の速さで 1.5 秒以上ある")
    func dogIsVisibleLongEnoughBeforeContact() {
        let dog = Self.hazard(.dog)
        let ahead = RunnerField.Metrics.width - RunnerField.Metrics.playerX
        // 鼻先が画面の右端に入る走者の距離を実測する。
        var d = dog.dogAppearDistance
        while let frame = dog.frame(atRunnerDistance: d), frame.start > d + ahead { d += 0.01 }
        let visible = dog.dogContactDistance - d
        #expect(abs(visible - (ahead - Self.half) / (1 + RunnerRules.dogAdvance)) < 0.05, "見えてから触れるまでの進みは 70 / (1 + k)")
        #expect(visible / RunnerRules.baseSpeed >= 1.5, "1 面の速さで \(visible / RunnerRules.baseSpeed) 秒しか無い")
        #expect(d > dog.dogAppearDistance, "現れた瞬間はまだ画面の外")
        // 静止した低い岩と比べ、重なっている時間は短い（速さに依らない比）。
        let rock = Self.hazard(.lowBlock)
        let width = RunnerField.Metrics.playerWidth
        #expect(dog.encounter.length + width < rock.encounter.length + width)
    }

    /// 受け入れ条件 2: 何もしなければ当たり、普通のジャンプで跳び越せる。予告のできごとは出ない。
    @Test("犬は跳ばないと鼻先が触れる瞬間に当たり、普通のジャンプで越えられ、予告は出ない")
    func dogMustBeJumpedWithoutCue() {
        for speed in [RunnerRules.baseSpeed, 41.2, 54.4] {
            let stage = RunnerStage(number: 1, pattern: "---d---", speed: speed)
            let dog = stage.hazards[0]
            var idle = RunnerField(stage: stage)
            idle.placeForTesting(distance: dog.dogAppearDistance - 30, altitude: 0, vy: 0)
            #expect(idle.nextHazard(from: idle.playerMaxX) == nil, "速さ \(speed): 現れる前は踏み切りの相手がいない")
            var events: [RunnerEvent] = []
            var crashedAt: Double?
            while idle.distance < dog.end + 40, !events.contains(where: { $0.isTerminal }) {
                let step = idle.step(dt: 1.0 / 600)
                if step.contains(.crashed) { crashedAt = idle.distance }
                events += step
            }
            #expect(events.filter { $0 == .boarCharging }.isEmpty, "速さ \(speed): 犬に予告は無い")
            #expect(events.contains(.crashed) && idle.lastMissCause == .animal, "速さ \(speed): 跳ばなければ犬に当たる")
            #expect(abs((crashedAt ?? 0) - dog.dogContactDistance) < 0.5, "速さ \(speed): 当たるのは鼻先が前端に触れる瞬間（\(crashedAt ?? 0)）")

            var piloted = RunnerField(stage: stage)
            piloted.placeForTesting(distance: dog.dogAppearDistance - 30, altitude: 0, vy: 0)
            events = []
            var jumpedAt: Double?
            while piloted.distance < dog.end + 40, !events.contains(where: { $0.isTerminal }) {
                if RunnerAutoPilot.shouldJump(field: piloted) {
                    piloted.jump()
                    jumpedAt = jumpedAt ?? piloted.distance
                }
                if RunnerAutoPilot.shouldRelease(field: piloted) { piloted.endHold() }
                events += piloted.step(dt: 1.0 / 60)
            }
            #expect(!events.contains(.crashed), "速さ \(speed): 普通のジャンプで越えられない")
            #expect(events.contains(.landed))
            // 踏み切りは犬が見えてから（画面の先読み 74 の中に入ってから）。
            if let jumpedAt, let frame = dog.frame(atRunnerDistance: jumpedAt) {
                #expect(frame.start - jumpedAt < RunnerField.Metrics.width - RunnerField.Metrics.playerX, "速さ \(speed): 見えないうちに跳んでいる")
                #expect(frame.start > jumpedAt + Self.half, "速さ \(speed): 触れる前に踏み切っている")
            } else { Issue.record("速さ \(speed): 自動操縦が犬に踏み切っていない") }
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

    @MainActor
    @Test("イノシシの予告で「ドドド」（rigid）が 1 回鳴る")
    func boarChargeFeedback() {
        let spy = SpyFeedbackService()
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
