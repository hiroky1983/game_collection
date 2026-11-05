import Core
import CoreEngine
import CoreTestSupport
import Foundation
import GameKitTestSupport
import SpriteKit
import Testing
@testable import GameRunner

/// 富士山（55〜60 面・#2729）の新しい仕掛け——斜面の上から転がってくる落石（`r`・`RunnerHazardKind.rockfall`）。
///
/// 落石は「予告のあと、決まった間合いで前から向かって来る高い岩」で、位置も高さも走者の距離だけで決まる
/// （`RunnerHazard.frame(atRunnerDistance:)`）。等価な静止区間・踏み切りの余裕は犬・イノシシと同じ式に乗るので、
/// 全ステージの成立条件（`RunnerStageTests`）と動く障害の検算（`RunnerHazardMotionTests`）がそのまま効く。
/// **ここで固定するのは落石にだけある決まり**——予告から出会いまでの間合いが常に同じこと、踏み切る前に必ず路面に
/// 着いていること、予告から踏み切りまで読む時間があること、跳べば越えられて跳ばなければ当たること、置き方の決まり、
/// 富士山の描画経路と色。
@Suite("チャリンコおじさん: 富士山の落石と着せ替え")
struct RunnerFujiGimmickTests {
    private static let fujiStages = RunnerStage.all.filter { RunnerWorld.world(forStage: $0.number) == .fuji }
    private static let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
    private static let half = RunnerField.Metrics.playerHalfWidth
    /// 画面の先読み（走者の前端から画面の右端まで）。
    private static let lookAhead = RunnerField.Metrics.width - RunnerField.Metrics.playerX - half

    /// 本編で落石が置かれている面の基準速（富士山は全部 60）。
    private static var rockfallStageSpeeds: [Double] {
        Array(Set(RunnerStage.all.filter { $0.hazards.contains { $0.kind == .rockfall } }.map(\.speed))).sorted()
    }

    /// 落石 1 つだけを置いた検証用のコース。前後は平地で、予告から出会いまで何も無い。
    private static func soloStage(speed: Double) -> RunnerStage {
        RunnerStage(number: 0, pattern: "------r------", speed: speed)
    }

    // MARK: - 寸法と動き（決まった間合い）

    @Test("落石は幅 2 タイル・高さは高い岩と同じ 9 で、出会うときの等価な静止区間は短い高い岩")
    func rockfallIsATallRollingRock() throws {
        let stage = Self.soloStage(speed: 60)
        let rock = try #require(stage.hazards.first)
        #expect(rock.kind == .rockfall)
        #expect(rock.length == 2 * RunnerRules.tileWidth)
        #expect(rock.height == RunnerHazardKind.tallBlock.height)
        #expect(rock.start == 6 * Self.segment + Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth)
        #expect(RunnerStage.segmentSpec("r")?.kind == .rockfall)
        // 相対速度 1.5 で体を通り抜けるので、静止した高い岩（長さ 4）より短い。
        let encounter = rock.encounter
        #expect(encounter.start == rock.start)
        #expect(encounter.length > 0 && encounter.length < RunnerRules.tileWidth, "等価な静止区間の長さ \(encounter.length)")
        #expect(encounter.height == RunnerHazardKind.tallBlock.height && encounter.height < RunnerRules.jumpApex)
        // 解析の死因は岩と同じ。動物ではないので犬・イノシシの規則（`isAnimal`）にも岩の規則（`isRock`）にも入らない。
        #expect(RunnerHazardKind.rockfall.missCause == .rock)
        #expect(!RunnerHazardKind.rockfall.isAnimal && !RunnerHazardKind.rockfall.isRock)
    }

    @Test("予告の前は斜面の上（当たり判定なし）、予告から一定の傾きで下りて間合い 24 で路面に着き、出会う瞬間に左端が置いた位置に着く")
    func rockfallFollowsTheRunnersDistance() throws {
        let rock = try #require(Self.soloStage(speed: 60).hazards.first)
        let cue = rock.rockfallCueDistance
        #expect(cue + Self.half == rock.start - RunnerRules.rockfallCueDistance, "予告は前端が 18 タイル手前に入った瞬間")
        #expect(rock.frame(atRunnerDistance: cue - 0.01) == nil, "予告の前に現れている")
        let first = try #require(rock.frame(atRunnerDistance: cue))
        #expect(abs(first.bottom - RunnerRules.rockfallDropHeight) < 1e-9, "予告の瞬間は斜面の上")
        #expect(first.advance == -RunnerRules.rockfallAdvance)
        // 予告の瞬間、岩は画面の外（先読み 70 より先）にいる——現れる瞬間に画面の中へ湧かない。
        #expect(first.start - (cue + Self.half) > Self.lookAhead, "予告の瞬間に岩が画面の中にいる")
        // 下りているあいだは帯の厚みが変わらず、下端が単調に下がる。
        var previous = first.bottom
        for d in stride(from: cue + 1, through: rock.start - Self.half, by: 1) {
            let frame = try #require(rock.frame(atRunnerDistance: d))
            #expect(abs(frame.top - frame.bottom - rock.height) < 1e-9)
            #expect(frame.bottom <= previous + 1e-9, "距離 \(d) で上へ戻った")
            previous = frame.bottom
        }
        let landing = rock.start - Self.half - RunnerRules.rockfallLandingGap
        #expect(rock.frame(atRunnerDistance: landing)?.bottom == 0, "間合い 24 で路面に着いていない")
        #expect((rock.frame(atRunnerDistance: landing - 1)?.bottom ?? 0) > 0, "間合い 24 より手前で着いている")
        // 出会う瞬間（前端が置いた位置に入る）に、岩の左端もちょうど置いた位置にいる。
        let meet = try #require(rock.frame(atRunnerDistance: rock.start - Self.half))
        #expect(abs(meet.start - rock.start) < 1e-9 && meet.bottom == 0)
        // 予告から出会いまで、岩の左端は自分の区画の中を動き、右端が次の区画にかかるのは高い塀より高いところだけ
        // ——隣の区画の岩・台座・塀と交わらない。
        let segmentStart = (rock.start / Self.segment).rounded(.down) * Self.segment
        for d in stride(from: cue, through: rock.start - Self.half, by: 0.5) {
            let frame = try #require(rock.frame(atRunnerDistance: d))
            #expect(frame.start >= segmentStart && frame.start < segmentStart + Self.segment, "距離 \(d) で左端が区画の外")
            if frame.end > segmentStart + Self.segment {
                #expect(frame.bottom > RunnerHazardKind.wallTop, "距離 \(d) で次の区画の低いところにかかる（下端 \(frame.bottom)）")
            }
        }
        #expect(meet.start >= segmentStart)
    }

    /// **決まった間合いで来る**（会長決裁）。予告の手応えは 1 回だけ、予告から出会うまでの走者の進みは速さ・ペダルの乗り・
    /// ゆっくりモードによらず `rockfallCueDistance` そのもの（乱数も時計も使わない）。
    @Test("予告（ゴロゴロ）は 1 回だけ出て、予告から出会いまでの走者の進みは速さ・ゆっくりモードによらず同じ")
    func cueAlwaysComesAtTheSameDistance() throws {
        for (speed, dt) in [(RunnerRules.baseSpeed, 1.0 / 120), (60, 1.0 / 120), (60, RunnerRules.slowFactor / 120)] {
            let stage = Self.soloStage(speed: speed)
            let rock = try #require(stage.hazards.first)
            var field = RunnerField(stage: stage)
            field.placeForTesting(distance: rock.rockfallCueDistance - 40, altitude: 0, vy: 0)
            var cueAt: Double?
            var events: [RunnerEvent] = []
            while field.distance < rock.start - Self.half, !events.contains(where: { $0.isTerminal }) {
                let step = field.step(dt: dt)
                if step.contains(.rockfallRumbling), cueAt == nil { cueAt = field.distance }
                events += step
            }
            #expect(events.filter { $0 == .rockfallRumbling }.count == 1, "速さ \(speed): 予告は 1 回")
            let cue = try #require(cueAt)
            #expect(abs(cue - rock.rockfallCueDistance) < 1.0, "速さ \(speed): 予告の地点 \(cue)")
            #expect(!events.contains(.boarCharging), "イノシシの予告と取り違えている")
        }
        #expect(RunnerHazard(kind: .rockfall, start: 400, length: 8).cue?.event == .rockfallRumbling)
        #expect(RunnerFeedbackCue.cue(for: .rockfallRumbling, lastLandingWasJust: false) == .impact(.rigid))
        #expect(!RunnerEvent.rockfallRumbling.isTerminal)
    }

    /// 自動操縦（= 遊ぶ人の正しい踏み切り）が踏み切る地点では、岩は**必ず路面にいて高さは高い岩と同じ**——斜面の途中の岩に
    /// 向かって跳ぶ場面は無い。路面に着いてから踏み切るまで、走者の進みで 1 タイル以上ある。
    @Test("踏み切りの地点より手前で落石は路面に着き、頭より上にいるあいだは跳ぶ相手にならない")
    func rockfallLandsBeforeTheTakeOffPoint() throws {
        #expect(!Self.rockfallStageSpeeds.isEmpty, "本編に落石が無い（空振り防止）")
        for speed in Self.rockfallStageSpeeds + [RunnerRules.baseSpeed] {
            let rock = try #require(Self.soloStage(speed: speed).hazards.first)
            let takeOff = rock.encounter.start - RunnerAutoPilot.lead(for: rock, speed: speed)
            let landing = rock.start - Self.half - RunnerRules.rockfallLandingGap
            #expect(takeOff - landing > RunnerRules.tileWidth, "速さ \(speed): 着いてから踏み切りまで \(takeOff - landing)")
            #expect(rock.frame(atRunnerDistance: takeOff)?.bottom == 0)
        }
        // 頭より上（帯の下端 ≥ 11）にいるあいだは `nextHazard` の対象にならない。
        let stage = Self.soloStage(speed: 60)
        let rock = stage.hazards[0]
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: rock.rockfallCueDistance + 1, altitude: 0, vy: 0)
        #expect((rock.frame(atRunnerDistance: field.distance)?.bottom ?? 0) > RunnerField.Metrics.playerHeight)
        #expect(field.nextHazard(from: field.playerMaxX) == nil, "斜面の上の岩に向かって跳ぼうとしている")
    }

    /// 予告から踏み切りの地点まで読む時間があること。物差しは突き上げ（#1010）と同じ「ペダルが上限 1.55 倍まで乗った
    /// 速さで 0.6 秒以上」（`RunnerHazardMotionTests.shootCueLeavesTimeToRead`）。
    @Test("予告から踏み切りの地点まで、ペダルが上限まで乗った速さでも 0.6 秒以上ある")
    func cueLeavesTimeToRead() throws {
        for speed in Self.rockfallStageSpeeds {
            let rock = try #require(Self.soloStage(speed: speed).hazards.first)
            let takeOff = rock.encounter.start - RunnerAutoPilot.lead(for: rock, speed: speed)
            let travel = takeOff - rock.rockfallCueDistance
            let fastest = speed * RunnerRules.maxPedalBoost
            #expect(travel / fastest >= 0.6, "速さ \(speed): 予告から踏み切りまで \(travel / fastest) 秒")
            // 岩が画面に入ってから踏み切りまでも、基準速で 0.4 秒以上（見えてから跳ぶ判断ができる）。
            let enters = rock.start - Self.half - Self.lookAhead / (1 + RunnerRules.rockfallAdvance)
            #expect((takeOff - enters) / speed >= 0.4, "速さ \(speed): 見えてから踏み切りまで \((takeOff - enters) / speed) 秒")
        }
    }

    // MARK: - 越えられる・越えないと当たる

    @Test("自動操縦の踏み切りで全弾道なら越えられ、一度も跳ばなければ落石に当たってミスになる（死因は rock）")
    func jumpingClearsAndIgnoringHits() throws {
        for speed in Self.rockfallStageSpeeds {
            let stage = Self.soloStage(speed: speed)
            let rock = try #require(stage.hazards.first)
            // 越える: 踏み切りの地点で跳び、着地まで押し続ける。
            var jumper = RunnerField(stage: stage)
            jumper.placeForTesting(distance: rock.encounter.start - RunnerAutoPilot.lead(for: rock, speed: speed), altitude: 0, vy: 0)
            jumper.jump()
            var events: [RunnerEvent] = []
            while jumper.distance < rock.start + 30, !events.contains(where: { $0.isTerminal }) { events += jumper.step(dt: 1.0 / 240) }
            #expect(!events.contains(where: { $0.isTerminal }), "速さ \(speed): 踏み切っても越えられない")
            // 当たる: 跳ばずに走る。
            var idle = RunnerField(stage: stage)
            idle.placeForTesting(distance: rock.rockfallCueDistance - 10, altitude: 0, vy: 0)
            var idleEvents: [RunnerEvent] = []
            while idle.distance < rock.start + 30, !idleEvents.contains(where: { $0.isTerminal }) { idleEvents += idle.step(dt: 1.0 / 240) }
            #expect(idleEvents.contains(.crashed), "速さ \(speed): 跳ばなくても当たらない")
            #expect(idle.lastMissCause == .rock && idle.lastMissObject == .hazard(.rockfall))
        }
        #expect(RunnerView.missText(cause: .rock, object: .hazard(.rockfall), world: .fuji) == "落石にぶつかった")
    }

    /// 本編の落石はどれも、その落石にだけ踏み切らずに走ると（他の障害は自動操縦どおり越える）その落石でミスになる。
    /// 本来のパターン（たこ焼きあり）のまま走らせるので、「取って無敵のまま落石へ着く並び」が無いことも押さえる。
    @Test("本編の落石は、跳ばなければ必ず当たる（たこ焼きの無敵で素通りできる並びが無い）")
    func everyRockfallHitsWhenIgnored() {
        var checked = 0
        for stage in Self.fujiStages {
            for rock in stage.hazards where rock.kind == .rockfall {
                checked += 1
                var field = RunnerField(stage: stage)
                var events: [RunnerEvent] = []
                var frames = 0
                while field.distance < rock.activeRange.upperBound + 8, frames < 60 * 120 {
                    frames += 1
                    if RunnerAutoPilot.shouldJump(field: field) {
                        let target = RunnerAutoPilot.nextTarget(field: field)?.start
                        let own = rock.frame(atRunnerDistance: field.distance)?.start
                        if target != own { field.jump() }
                    }
                    if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                    events += field.step(dt: 1.0 / 60)
                    if events.contains(where: { $0.isTerminal }) { break }
                }
                #expect(
                    events.contains(.crashed) && field.lastMissObject == .hazard(.rockfall),
                    "ステージ \(stage.number) の落石（\(rock.start)）は跳ばなくても当たらない（\(String(describing: field.lastMissObject))）"
                )
            }
        }
        #expect(checked >= 10, "落石が \(checked) 本しか無い（空振り防止）")
    }

    /// 無敵（たこ焼き）は落石も素通りする——だから置き方の決まり（手前 5 区画にたこ焼きを置かない）が要る。
    @Test("たこ焼きの無敵のあいだは落石も素通りする（置き方の決まりの根拠）")
    func invincibilityPassesThroughTheRock() throws {
        let stage = RunnerStage(number: 0, pattern: "--k---r------", speed: 60)
        let rock = try #require(stage.hazards.first)
        var field = RunnerField(stage: stage)
        var events: [RunnerEvent] = []
        while field.distance < rock.start + 30, !events.contains(where: { $0.isTerminal }) { events += field.step(dt: 1.0 / 120) }
        #expect(events.contains(.collectedInvincibleItem))
        #expect(!events.contains(where: { $0.isTerminal }), "無敵なのに落石に当たった")
    }

    @Test("自動操縦は落石のある面を全部走り切り、どの落石も路面に着いてから踏み切って越える")
    func autoPilotClearsEveryRockfallStage() {
        for stage in Self.fujiStages {
            var field = RunnerField(stage: stage)
            var finished = false
            var jumpsAtFallingRock = 0
            for _ in 0..<(60 * 300) {
                if RunnerAutoPilot.shouldJump(field: field) {
                    if field.isGrounded, let next = field.nextHazardFrame(from: field.playerMaxX),
                       next.hazard.kind == .rockfall, next.frame.bottom > 0 {
                        jumpsAtFallingRock += 1
                    }
                    field.jump()
                }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                let events = field.step(dt: 1.0 / 60)
                if events.contains(.crashed) || events.contains(.fell) {
                    Issue.record("ステージ \(stage.number) で自動操縦がミスした（\(String(describing: field.lastMissObject))）")
                    break
                }
                if events.contains(.reachedGoal) { finished = true; break }
            }
            #expect(finished, "ステージ \(stage.number) を走り切れない")
            #expect(jumpsAtFallingRock == 0, "ステージ \(stage.number): 斜面の途中の落石に向かって踏み切った")
        }
    }

    @Test("ゆっくりモードでも同じ操作で落石を越えられる")
    func slowModeKeepsTheRockfallClearable() throws {
        let stage = Self.soloStage(speed: 60)
        let rock = try #require(stage.hazards.first)
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: rock.rockfallCueDistance - 10, altitude: 0, vy: 0)
        var events: [RunnerEvent] = []
        while field.distance < rock.start + 30, !events.contains(where: { $0.isTerminal }) {
            if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
            if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
            events += field.step(dt: RunnerRules.slowFactor / 120)
        }
        #expect(!events.contains(where: { $0.isTerminal }), "ゆっくりモードで落石に当たった")
    }

    // MARK: - 置き方

    @Test("落石は富士山にだけ置かれ、55 面に 1 本・60 面に 4 本、どの面にも 1 本以上あり、後ろの面ほど減らない")
    func rockfallsAppearOnlyInFuji() {
        for stage in RunnerStage.all where RunnerWorld.world(forStage: stage.number) != .fuji {
            #expect(!stage.pattern.contains("r"), "ステージ \(stage.number) に落石がある")
        }
        let counts = Self.fujiStages.map { $0.hazards.filter { $0.kind == .rockfall }.count }
        #expect(counts.count == 6)
        #expect(counts.first == 1, "初出の 55 面は 1 本だけで覚えさせる: \(counts)")
        #expect(counts.last == 4, "締めの 60 面: \(counts)")
        for (previous, next) in zip(counts, counts.dropFirst()) {
            #expect(previous <= next, "落石の本数が面を追って減っている: \(counts)")
        }
        for stage in Self.fujiStages {
            #expect(stage.speed == RunnerRules.endlessMaxSpeed, "ステージ \(stage.number) の速さが \(stage.speed)")
            #expect(stage.pattern.count == RunnerRules.maxSegments, "ステージ \(stage.number) の区画数が上限で止まっていない")
            #expect(!stage.pattern.contains("H"), "ステージ \(stage.number) に東京の歩道橋が混ざっている")
        }
    }

    /// **新しい仕組みは初めて出す面で前後を平地にして単独で見せる**（#1009 C2）。
    @Test("落石の初出（55 面）は前後 2 区画ずつ素の平地")
    func firstRockfallStandsAlone() {
        let pattern = Array(RunnerStage.all[54].pattern)
        guard let index = pattern.firstIndex(of: "r") else { Issue.record("55 面に落石が無い"); return }
        for offset in [-2, -1, 1, 2] {
            #expect(pattern[index + offset] == "-", "55 面の落石（区画 \(index)）の \(offset) が \(pattern[index + offset])")
        }
    }

    /// 落石の置き方の決まり（`RunnerStage+Patterns.swift` の富士山の注記）:
    /// - 隣の区画に鳥・沈む床・台座（崩れる足場・高い台座を含む）・加速床を置かない
    /// - 手前の区画にイノシシを置かない
    /// - たこ焼きを 5 区画以内の手前に置かない（無敵は落石を素通りする・`invincibilityPassesThroughTheRock`）
    /// - 高い塀・裂け目の着地点（2 区画）に置かない
    @Test("落石の隣に鳥・沈む床・台座・加速床が無く、手前にイノシシ・5 区画以内のたこ焼き・塀と裂け目の着地点が無い")
    func rockfallsKeepTheirApproach() {
        var seen = 0
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "r" {
                seen += 1
                for neighbor in [index - 1, index + 1] where pattern.indices.contains(neighbor) {
                    #expect(!"b~PCH=".contains(pattern[neighbor]), "ステージ \(stage.number): 落石（区画 \(index)）の隣が \(pattern[neighbor])")
                }
                #expect(pattern[index - 1] != "i", "ステージ \(stage.number): 落石（区画 \(index)）の手前がイノシシ")
                for offset in 1...5 where pattern.indices.contains(index - offset) {
                    #expect(pattern[index - offset] != RunnerStage.takoyakiSymbol, "ステージ \(stage.number): 落石（区画 \(index)）の \(offset) 区画手前がたこ焼き")
                }
                for offset in 1...RunnerRules.wallLandingSegments where pattern.indices.contains(index - offset) {
                    #expect(!"wV".contains(pattern[index - offset]), "ステージ \(stage.number): 落石（区画 \(index)）が塀・裂け目の着地点にある")
                }
            }
        }
        #expect(seen >= 10, "落石が \(seen) 本しか無い（この検証が空振りしている）")
    }

    @Test("QA用ショーケースとエンドレスには落石が出ない")
    func rockfallIsNotInTheShowcaseOrEndless() {
        #if DEBUG
        #expect(!RunnerStage.debugShowcase.pattern.contains("r"))
        #endif
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                if let next = field.nextHazard(from: field.playerMaxX) {
                    #expect(next.kind != .rockfall, "種 \(seed) のエンドレスに落石が出た")
                }
            }
        }
    }

    // MARK: - 色（#929 の規則）

    /// 富士山の着せ替えた手前の物と落石も、濃い側の色が淡い背景の全部と 3:1 以上（縁取りに頼らない部品は主色だけで）。
    @Test("富士山の着せ替え（落石・石積みの目地・溶岩の石垣の目地・砂煙の陰・ザレ場の小石）は背景と 3:1 以上")
    func fujiDressedForegroundStandsOut() {
        typealias P = RunnerWorld.DressingPalette
        let art = RunnerPixelArt.palette
        let fuji = RunnerWorld.fuji
        let items: [(String, UInt32)] = [
            ("落石の本体", fuji.palette.rockBody), ("落石の縁取り", fuji.outline),
            ("石積みの目地", P.stoneStackLine), ("溶岩の石垣の目地", art["V"]!), ("溶岩の石垣の石", art["v"]!),
            ("砂煙の右の陰", art["z"]!), ("ザレ場の小石", P.screePebble), ("割れ目の底", P.volcanicCrackDeep),
        ]
        for (name, color) in items {
            for (backdrop, hex) in fuji.groundBackdrops {
                #expect(WCAG.contrast(color, hex) >= 3.0, "富士山の\(name)が \(backdrop) (\(String(hex, radix: 16))) に溶ける")
            }
        }
        // 縁取りで浮く部品（道標・石積みの面と上面）。
        for (name, main, edge) in [
            ("道標", art["M"]!, RunnerPixelArt.outline), ("石積み", P.stoneStackBody, fuji.outline),
            ("石積みの上面", P.stoneStackTop, fuji.outline), ("割れ目の縁", P.volcanicCrackLip, P.volcanicCrackDeep),
        ] {
            for (backdrop, hex) in fuji.groundBackdrops {
                #expect(max(WCAG.contrast(main, hex), WCAG.contrast(edge, hex)) >= 3.0, "富士山の\(name)が \(backdrop) に溶ける")
            }
        }
        // 路面の中に描くもの（加速床・沈む床・穴）は路面とだけ比べる。
        let asphalt = fuji.road.asphalt
        #expect(WCAG.contrast(P.sandRunSurface, asphalt) >= 3.0, "砂走りが登山道に溶ける")
        #expect(WCAG.contrast(P.sandRunArrow, P.sandRunSurface) >= 3.0, "砂走りの矢印が読めない")
        #expect(WCAG.contrast(P.screeSurface, asphalt) >= 3.0, "ザレ場が登山道に溶ける")
        #expect(WCAG.relativeLuminance(P.screeDeep) < WCAG.relativeLuminance(P.screeSurface), "ザレ場の底が面より明るい")
        #expect(WCAG.contrast(P.volcanicCrackDeep, asphalt) >= 3.0, "割れ目が登山道に溶ける")
        #expect(WCAG.relativeLuminance(P.volcanicCrackSurface) > WCAG.relativeLuminance(P.volcanicCrackDeep))
        #expect(WCAG.relativeLuminance(P.volcanicCrackLip) > WCAG.relativeLuminance(asphalt), "割れ目の縁が路面より暗い")
        // 砂煙・溶岩の石垣は、雪柱・石垣と同じ格子で色だけが違う（色替え）。濃い側が絵に実在する。
        let dust = RunnerPixelArt.dustSpoutRows.joined()
        #expect(dust.contains("z") && dust.contains("e") && dust.contains("E") && dust.contains("f"))
        #expect(RunnerPixelArt.dustSpoutRows.map(\.count) == RunnerPixelArt.snowSpoutRows.map(\.count))
        #expect(dust != RunnerPixelArt.snowSpoutRows.joined())
        let lava = RunnerPixelArt.lavaWallRows.joined()
        #expect(lava.contains("V") && lava.contains("v"))
        for other in ["G", "g", "W", "A", "R", "r", "Q", "q"] { #expect(!lava.contains(other), "溶岩の石垣に他の塀の色 \(other) が混ざっている") }
    }

    // MARK: - 絵

    @Test("落石の絵は 27×27 の正方形で余白が無く、色は世界の岩の 3 階調と縁取り")
    func fallingRockArt() throws {
        let sprite = RunnerPixelArt.fallingRock(world: .fuji)
        #expect(sprite.width == 27 && sprite.height == 27)
        #expect(sprite.undefinedKeys.isEmpty)
        let b = try #require(sprite.opaqueBounds)
        #expect(b.x == 0 && b.y == 0 && b.width == sprite.width && b.height == sprite.height, "落石の余白: \(b)")
        #expect(sprite.palette["B"] == RunnerWorld.fuji.palette.rockBody)
        #expect(sprite.palette["L"] == RunnerWorld.fuji.palette.rockLight)
        #expect(sprite.palette["D"] == RunnerWorld.fuji.palette.rockDark)
        #expect(sprite.palette["K"] == RunnerWorld.fuji.outline)
        // 90° 回しても外形が同じ（正方形・上下左右に縁取りが接する）。
        #expect(sprite.rows.first?.contains("K") == true && sprite.rows.last?.contains("K") == true)
        #expect(sprite.rows.allSatisfy { $0.first != nil })
    }

    @Test("ブルドーザーは排土板が左端の列にあり、2 コマは履帯より上が同じ絵")
    func bulldozerArt() {
        let walk0 = RunnerPixelArt.bulldozerDrive0Rows, walk1 = RunnerPixelArt.bulldozerDrive1Rows
        #expect(walk0.count == 23 && walk0.allSatisfy { $0.count == 33 })
        #expect(walk1.count == 23 && walk1.allSatisfy { $0.count == 33 })
        // 履帯（下の 5 行）より上は同じ。
        #expect(Array(walk0.dropLast(5)) == Array(walk1.dropLast(5)))
        #expect(walk0.suffix(5) != walk1.suffix(5), "履帯が動いていない")
        // 排土板（鋼 `S`）が絵の左端の列に接する（イノシシの鼻先・フォークの先と同じ約束）。
        let bladeRows = walk0.map(Array.init).filter { $0[0] == "K" && $0[1] == "S" }
        #expect(bladeRows.count >= 6, "左端に排土板が無い")
        // 屋根の回転灯（`Y`）が上の 2 行にある。
        #expect(walk0.prefix(2).contains { $0.contains("Y") })
        #expect(RunnerPixelArt.bulldozerRearWheelX > 33 / 2)
    }

    @Test("カモシカは頭が左で、頭の上に短い角（暗い `o`）があり、首輪を付けない")
    func serowArt() {
        let rows = RunnerPixelArt.serowWalk0Rows
        #expect(rows.count == 21 && rows.allSatisfy { $0.count == 30 })
        #expect(!rows.joined().contains("R"), "カモシカに首輪がある")
        #expect(rows.prefix(3).contains { $0.prefix(10).contains("o") }, "頭の上に角が無い")
        // 喉と頬の白い毛（`W`）が左（頭の側）にある。
        #expect(rows.contains { $0.prefix(6).contains("W") })
    }

    // MARK: - 描画

    private func fillCount(in node: SKNode, color hex: UInt32) -> Int {
        node.children.reduce(0) { total, child in
            var own = 0
            if let sprite = child as? SKSpriteNode, sprite.texture == nil, isSame(sprite.color, hex) { own = 1 }
            if let shape = child as? SKShapeNode, isSame(shape.fillColor, hex) { own = 1 }
            return total + own + fillCount(in: child, color: hex)
        }
    }

    private func spriteCount(in node: SKNode, texture: SKTexture) -> Int {
        node.children.reduce(0) { total, child in
            let own = (child as? SKSpriteNode)?.texture === texture ? 1 : 0
            return total + own + spriteCount(in: child, texture: texture)
        }
    }

    private func isSame(_ color: SKColor, _ hex: UInt32) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let lhs = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let rhs = RunnerPalette.color(hex).cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              lhs.count >= 3, rhs.count >= 3 else { return false }
        return abs(lhs[0] - rhs[0]) < 0.004 && abs(lhs[1] - rhs[1]) < 0.004 && abs(lhs[2] - rhs[2]) < 0.004
    }

    @Test("55 面は富士山の着せ替え（道標・火山岩・カモシカ・ブルドーザー・砂煙・ザレ場・石積み・砂走り・落石）で組まれ、走らせても落ちない")
    @MainActor
    func fujiSceneBuilds() throws {
        typealias P = RunnerWorld.DressingPalette
        let model = RunnerModel(startingAt: 55, preference: makePreference("fuji-scene"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        #expect(scene.world == .fuji)
        let stage = model.field.stage
        // 道標のテクスチャが高い岩の数だけ（低い岩は岩塊のままなのでテクスチャ無し）。
        let talls = stage.hazards.filter { $0.kind == .tallBlock }.count
        let signpost = try #require(scene.blockTextures[.signpost])
        #expect(talls > 0 && spriteCount(in: scene.courseLayer, texture: signpost) == talls)
        // 落石のテクスチャが落石の数だけ貼られ、動く障害として毎フレーム写される。
        let rocks = stage.hazards.filter { $0.kind == .rockfall }.count
        #expect(rocks == 1 && spriteCount(in: scene.courseLayer, texture: scene.fallingRockTexture(.fuji)) == rocks)
        #expect(scene.movingHazards.filter { $0.hazard.kind == .rockfall }.count == rocks)
        // 突き上げは砂煙（その世界のぶんしかテクスチャを作らない）。
        #expect(scene.cachedShootStyles == [.dustSpout], "作ったテクスチャ: \(scene.cachedShootStyles)")
        // ザレ場・石積み・砂走りの色が出ていて、他の世界の色は出ない。
        for (name, hex) in [("ザレ場", P.screeSurface), ("石積み", P.stoneStackBody), ("砂走り", P.sandRunSurface)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) > 0, "\(name)の色が出ていない")
        }
        for (name, hex) in [("足湯", P.footBathWater), ("新雪", P.freshSnowSurface), ("水たまり", P.puddleSurface), ("木箱", P.crateWood), ("雪のブロック", P.snowBlockBody), ("動く歩道", P.walkwayBelt)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) == 0, "富士山に\(name)の色が出ている")
        }
        // 犬の枠はカモシカの格子。
        let dogTextures = try #require(scene.dogTextures[.fuji])
        let serow = RunnerPixelArt.walker(.walk0, world: .fuji)
        #expect(serow.rows == RunnerPixelArt.serowWalk0Rows)
        #expect(Int(dogTextures[0].size().width) == serow.width && Int(dogTextures[0].size().height) == serow.height)
        // 遠景のタイルに丘以外（雲海・ロープ柵・山小屋か鳥居かハイマツ）が載っている。地平線には御来光の帯と朝日。
        for tile in scene.hillTiles { #expect(tile.children.count > 3, "遠景のタイルに丘しか無い") }
        #expect(fillCount(in: scene.backdropLayer, color: RunnerWorld.SceneryPalette.sun) == 1, "朝日が無い")
        #expect(fillCount(in: scene.backdropLayer, color: RunnerWorld.SceneryPalette.sunriseGlow) >= 1, "御来光の帯が無い")

        // 自動操縦で 20 秒ぶん走らせて反映しても落ちない（落石・ザレ場・吊り橋の経路を通る）。
        model.press()
        model.release()
        for _ in 0..<1200 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(model.phase.isRunning || model.phase == .cleared, "55 面で 20 秒以内にミスした")
    }

    /// 落石の絵は当たり判定の帯そのものに置かれ（斜面を下りているあいだは浮いている）、影は地面に残り、予告の小石は
    /// 岩が画面の外にいるあいだだけ画面の右上に出て、転がりは 90° ずつ。
    @Test("落石の絵は帯の位置に置かれ、予告の小石は岩が画面に入るまで出て、転がりは 90° ずつ")
    @MainActor
    func rockfallViewFollowsTheFrame() throws {
        let model = RunnerModel(startingAt: 55, preference: makePreference("fuji-rock-view"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        let view = try #require(scene.movingHazards.first { $0.hazard.kind == .rockfall })
        let rock = view.hazard
        model.press()
        model.release()
        var sawPebbles = false, sawDescent = false, sawRolling = false
        var rotations: Set<Int> = []
        var frames = 0
        while model.distance < rock.start + 20, model.phase.isRunning, frames < 60 * 120 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
            guard let frame = rock.frame(atRunnerDistance: model.field.distance) else {
                #expect(view.node.isHidden, "予告の前に落石が見えている")
                continue
            }
            #expect(!view.node.isHidden)
            // SpriteKit は位置を単精度で持つので、比べるのは 1/1000 単位まで。
            #expect(abs(Double(view.node.position.y) - (RunnerField.Metrics.groundY + frame.bottom)) < 1e-3, "絵が帯の高さに無い")
            #expect(abs(Double(view.node.position.x) - (frame.start - scene.renderOrigin)) < 1e-3, "絵が帯の位置に無い")
            // 影は地面に残る。
            let shadowY = Double(view.node.position.y) + Double(view.shadow?.position.y ?? 0)
            #expect(abs(shadowY - (RunnerField.Metrics.groundY + view.shadowBaseY)) < 1e-3, "影が地面に無い")
            let onScreen = frame.start < model.field.distance + RunnerField.Metrics.width - RunnerField.Metrics.playerX
            if let pebbles = view.cue {
                #expect(pebbles.isHidden == onScreen, "小石の出し入れが岩の位置と合っていない")
                if !pebbles.isHidden { sawPebbles = true }
            }
            if frame.bottom > 0 && onScreen { sawDescent = true }
            if frame.bottom == 0 { sawRolling = true }
            let sprite = try #require(view.node.childNode(withName: RunnerScene.fallingRockSpriteName))
            let quarter = Double(sprite.zRotation) / (Double.pi / 2)
            #expect(abs(quarter - quarter.rounded()) < 1e-6, "90° 刻みでない回転 \(sprite.zRotation)")
            rotations.insert(Int(quarter.rounded()))
        }
        #expect(sawPebbles, "予告の小石が一度も出ていない")
        #expect(sawDescent, "斜面を下りてくる岩が画面に映っていない")
        #expect(sawRolling, "路面を転がる岩が映っていない")
        #expect(rotations.count >= 3, "転がって見えない（回転 \(rotations)）")
    }

    @Test("58 面の溶岩の石垣（高い塀）は石垣・コンテナ・雪山・看板と別の絵で、その世界のぶんしかテクスチャを作らない")
    @MainActor
    func lavaWallUsesItsOwnArt() {
        let model = RunnerModel(startingAt: 58, preference: makePreference("fuji-wall"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        #expect(scene.world.dressing.wall == .lavaWall)
        #expect(scene.cachedWallStyles == [.lavaWall], "作ったテクスチャ: \(scene.cachedWallStyles)")
        let walls = model.field.stage.hazards.filter { $0.kind == .wall }
        #expect(walls.count == 1, "58 面の石垣が \(walls.count) 本（空振り防止）")
        #expect(spriteCount(in: scene.courseLayer, texture: scene.wallTexture(.lavaWall)) == walls.count)
    }

    @Test("落石の予告では硬い手応え（ゴロゴロ）が 1 回だけ鳴る")
    @MainActor
    func rockfallCuePlaysFeedback() throws {
        let spy = SpyFeedbackService()
        let model = RunnerModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy),
            startingAt: 55, preference: makePreference("fuji-cue")
        )
        let rock = try #require(model.stage.hazards.first { $0.kind == .rockfall })
        model.press()
        model.release()
        var frames = 0
        // 予告の 1 区画手前まで進めてから数え始める（スタートの手応えや手前の障害のぶんを数えない）。
        while model.phase.isRunning, model.distance < rock.rockfallCueDistance - 20, frames < 60 * 120 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        spy.reset()
        while model.phase.isRunning, model.distance < rock.rockfallCueDistance + 10, frames < 60 * 120 {
            frames += 1
            model.tick(dt: 1.0 / 60)
        }
        #expect(spy.impacts.filter { $0 == .rigid }.count == 1, "予告の手応え: \(spy.impacts)")
    }
}
