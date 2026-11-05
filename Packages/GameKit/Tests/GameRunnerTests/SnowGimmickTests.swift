import Core
import CoreEngine
import Foundation
import SpriteKit
import Testing
@testable import GameRunner

/// 雪国（43〜48 面・#2729）の新しい仕掛け——二段ジャンプでしか渡れない広い裂け目（`V`・`RunnerHazardKind.chasm`）。
///
/// 裂け目は「幅だけが違う穴」なので、当たり判定・置き方の検査は穴と塀の既存の仕組み
/// （`RunnerStageTests.everyHazardIsClearable` / `hazardsAreFarEnoughApart`）にそのまま乗る。
/// **ここで固定するのは高い塀（`RunnerDoubleJumpWallTests`）と同じ 2 点**——一段ではどう跳んでも渡れないことと、
/// 二段目の押し始めに十分な幅があること——と、塀から写した置き方の決まり（着地点・鳥）、雪国の描画経路。
@Suite("チャリンコおじさん: 雪国の裂け目と着せ替え")
struct RunnerSnowGimmickTests {
    private static let half = RunnerField.Metrics.playerHalfWidth
    private static let snowStages = RunnerStage.all.filter { RunnerWorld.world(forStage: $0.number) == .snow }

    /// 本編で裂け目が置かれている面の基準速（雪国は全部 60）。
    private static var chasmStageSpeeds: [Double] {
        Array(Set(RunnerStage.all.filter { $0.hazards.contains { $0.kind == .chasm } }.map(\.speed))).sorted()
    }

    /// 裂け目 1 つだけを置いた検証用のコース。前後は平地で、踏み切りの余地を十分に取る。
    private static func soloStage(speed: Double) -> RunnerStage {
        RunnerStage(number: 0, pattern: "-----V------", speed: speed)
    }

    private struct Run {
        var crossed = false
        var fell = false
        var usedSecondJump = false
    }

    /// 1 回のジャンプで裂け目に挑む。`secondJumpAt` に秒を渡すと踏み切りからその時間が経った最初のフレームで
    /// 二段目を踏む（nil なら一段だけ）。踏み切る地点は自動操縦と同じ（`RunnerAutoPilot.lead` = 穴と同じ縁の手前）で、
    /// `takeOffShift` でそこから前後にずらせる。
    private static func attempt(
        speed: Double, secondJumpAt: Double?, tapFirstJump: Bool = false, takeOffShift: Double = 0
    ) -> Run {
        let stage = soloStage(speed: speed)
        guard let chasm = stage.hazards.first(where: { $0.kind == .chasm }) else { return Run() }
        var field = RunnerField(stage: stage)
        let takeOff = chasm.start - RunnerAutoPilot.lead(for: chasm, speed: speed) + takeOffShift
        var result = Run()
        var elapsed: Double?
        let dt = 1.0 / 120
        for _ in 0..<(120 * 20) {
            if field.isGrounded, field.distance >= takeOff, elapsed == nil {
                field.jump()
                if tapFirstJump { field.endHold() }
                elapsed = 0
            } else if let since = elapsed, let at = secondJumpAt, !result.usedSecondJump, since >= at {
                field.endHold()
                result.usedSecondJump = field.jump()
            }
            let events = field.step(dt: dt)
            if let since = elapsed { elapsed = since + dt }
            if events.contains(.fell) || events.contains(.crashed) {
                result.fell = true
                return result
            }
            if field.isGrounded, field.distance >= chasm.end {
                result.crossed = true
                return result
            }
        }
        return result
    }

    // MARK: - 幅の設計

    @Test("裂け目は幅だけが違う穴で、1 段の飛距離より広く、二段の飛距離より狭い")
    func chasmIsAWidePit() {
        let kind = RunnerHazardKind.chasm
        #expect(kind.height == 0 && kind.bottom == 0, "穴と同じく高さを持たない")
        #expect(kind.missCause == .pit, "死因は穴と同じ（`AnalyticsEndCause` は増やさない）")
        #expect(!kind.isRock && !kind.isAnimal)
        #expect(RunnerRules.chasmWidth == Double(RunnerRules.chasmTiles) * RunnerRules.tileWidth)
        // 跳べる最大幅の穴（`3`・4 タイル）の 3 倍以上——一目で別物と分かる幅。
        #expect(RunnerRules.chasmTiles >= 12)
        let speed = RunnerRules.endlessMaxSpeed
        // **下側**: 縁ぎりぎりで踏み切っても 1 段の着地（速さ × 滞空）が向こう岸に届かない。
        #expect(speed * RunnerRules.jumpAirTime < RunnerRules.chasmWidth, "1 段で渡れてしまう幅")
        // **上側**: 自動操縦の踏み切り（縁の手前 `baseLead`）から二段で跳ぶと 1 タイル以上余る。
        #expect(
            RunnerRules.doubleJumpRange(at: speed) > RunnerAutoPilot.baseLead + RunnerRules.chasmWidth + RunnerRules.tileWidth,
            "二段でも渡れない幅"
        )
        // 着地点は塀と同じ 2 区画に収まる（裂け目は区画の 6 タイル目から始まる）。
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        #expect(
            offset - RunnerAutoPilot.baseLead + RunnerRules.doubleJumpRange(at: speed)
                <= Double(RunnerRules.wallLandingSegments) * segment
        )
    }

    @Test("区画記号 V は穴と同じ位置から始まる幅 13 タイルの裂け目に展開される")
    func chasmSymbolExpandsToAWidePit() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        let stage = RunnerStage(number: 1, pattern: "--V---", speed: 60)
        #expect(stage.hazards.count == 1)
        let chasm = stage.hazards[0]
        #expect(chasm.kind == .chasm)
        #expect(chasm.start == segment * 2 + offset)
        #expect(chasm.length == RunnerRules.chasmWidth)
        #expect(chasm.end > segment * 3, "右端は次の区画へ食い込む（着地点 2 区画を平地にする決まりで吸収する）")
        // 横に動かないので、走者から見た区間は置いた位置そのもの。
        #expect(chasm.encounter.start == chasm.start && chasm.encounter.length == chasm.length)
        #expect(chasm.frame(atRunnerDistance: 0)?.advance == 0)
        #expect(chasm.cue == nil)
        #expect(stage.platforms.isEmpty && stage.sinkFloors.isEmpty)
        // 穴の判定（中心の x）がそのまま効く。
        let field = RunnerField(stage: stage)
        #expect(field.isPit(at: chasm.start) && field.isPit(at: chasm.end - 0.01) && !field.isPit(at: chasm.end))
        #expect(!field.isPit(at: chasm.start - 0.01))
    }

    // MARK: - 公平さ（塀と同じ「妥協しない」）

    /// **一段ジャンプではどう跳んでも渡れない**こと。踏み切る地点を縁の手前 60 から縁の先 20 まで 2 単位ずつずらし、
    /// いちばん伸びる全弾道（押しっぱなし）で挑んですべて落ちることを実際に走らせて確かめる。
    @Test("一段ジャンプでは、どこで踏み切っても裂け目を渡れず、死因は穴")
    func singleJumpNeverCrossesTheChasm() {
        #expect(!Self.chasmStageSpeeds.isEmpty, "本編に裂け目が無い（空振り防止）")
        for speed in Self.chasmStageSpeeds {
            for shift in stride(from: -60.0, through: 20.0, by: 2.0) {
                let run = Self.attempt(speed: speed, secondJumpAt: nil, takeOffShift: shift)
                #expect(!run.crossed, "速さ \(speed)・ずらし \(shift) で一段のまま渡れた")
                #expect(run.fell, "速さ \(speed)・ずらし \(shift) で落ちなかった")
            }
        }
        var field = RunnerField(stage: Self.soloStage(speed: 60))
        let chasm = field.stage.hazards[0]
        field.placeForTesting(distance: chasm.start - RunnerAutoPilot.baseLead, altitude: 0, vy: 0)
        field.jump()
        var events: [RunnerEvent] = []
        for _ in 0..<600 where !events.contains(where: { $0.isTerminal }) { events += field.step(dt: 1.0 / 120) }
        #expect(events.contains(.fell) && field.lastMissCause == .pit)
    }

    /// **二段目の押し始めに十分な幅がある**こと（塀と同じ「目安 0.2 秒以上」）。
    /// 二段目を踏む時刻を 1/120 秒刻みで動かし「渡れた時刻の連続した幅」を測る。一段目を長押しした場合と
    /// 押して即離した場合の両方で見る。
    @Test("二段目の押し始めの猶予が、置いた面の速さすべてで 0.2 秒以上ある")
    func doubleJumpWindowIsGenerous() {
        for speed in Self.chasmStageSpeeds {
            for tap in [false, true] {
                let window = Self.widestWindow(speed: speed, tapFirstJump: tap)
                #expect(window >= 0.2, "速さ \(speed)（一段目は\(tap ? "タップ" : "長押し")）の二段目の猶予が \(window) 秒しかない")
            }
        }
    }

    private static func widestWindow(speed: Double, tapFirstJump: Bool) -> Double {
        let step = 1.0 / 120
        var best = 0.0
        for shift in stride(from: 0.0, through: -12.0, by: -6.0) {
            var current = 0.0
            for t in stride(from: 0.0, through: 0.9, by: step) {
                let run = attempt(speed: speed, secondJumpAt: t, tapFirstJump: tapFirstJump, takeOffShift: shift)
                if run.crossed, run.usedSecondJump {
                    current += step
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
        }
        return best
    }

    /// 自動操縦（= テストと撮影が共有する操作）が、実際に二段目を踏んで裂け目を渡ること。
    @Test("自動操縦は裂け目の前で二段目を踏み、裂け目のある面を走り切れる")
    func autoPilotUsesTheSecondJump() {
        for stage in RunnerStage.all where stage.hazards.contains(where: { $0.kind == .chasm }) {
            var field = RunnerField(stage: stage)
            var maxJumpCount = 0
            var finished = false
            for _ in 0..<(60 * 300) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                let events = field.step(dt: 1.0 / 60)
                maxJumpCount = max(maxJumpCount, field.jumpCount)
                if events.contains(.crashed) || events.contains(.fell) { Issue.record("ステージ \(stage.number) で自動操縦がミスした"); break }
                if events.contains(.reachedGoal) { finished = true; break }
            }
            #expect(finished, "ステージ \(stage.number) を走り切れない")
            #expect(maxJumpCount == 2, "ステージ \(stage.number) で二段目を一度も踏んでいない")
        }
    }

    /// **本編に置いた裂け目は、二段目を踏まなければ必ず落ちる**こと。たこ焼きの無敵でも穴は落ちる（43 面はたこ焼きの
    /// 直後に裂け目がある）ので、塀と違ってたこ焼きの距離の決まりは要らない——それもここで実走で言い切る。
    @Test("本編の裂け目は、二段目を踏まなければ必ず落ちる（無敵でも落ちる）")
    func chasmsSwallowTheRunnerWhenTheSecondJumpIsSkipped() {
        var checked = 0
        var invincibleAtAChasm = false
        for stage in RunnerStage.all {
            let chasms = stage.hazards.filter { $0.kind == .chasm }
            for chasm in chasms {
                var field = RunnerField(stage: stage)
                var events: [RunnerEvent] = []
                var frames = 0
                while field.distance < chasm.end + 8, frames < 60 * 180 {
                    frames += 1
                    // **二段目を踏まないのは対象の裂け目だけ**。手前の塀・裂け目では踏んで越える。
                    if RunnerAutoPilot.shouldJump(field: field) {
                        let aiming = field.nextHazardFrame(from: field.playerMaxX)?.hazard
                        let skipping = RunnerAutoPilot.shouldTakeSecondJump(field: field) && aiming?.start == chasm.start
                        if !skipping { field.jump() }
                    }
                    if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                    if field.playerMaxX > chasm.start, field.isInvincible { invincibleAtAChasm = true }
                    events += field.step(dt: 1.0 / 60)
                    if events.contains(where: { $0.isTerminal }) { break }
                }
                checked += 1
                #expect(
                    events.contains(.fell) && field.lastMissCause == .pit,
                    "ステージ \(stage.number) の裂け目（\(chasm.start)）は二段目無しでも渡れる（\(events.last.map { "\($0)" } ?? "-")）"
                )
                #expect(
                    field.distance >= chasm.start && field.distance < chasm.end,
                    "ステージ \(stage.number): 対象の裂け目（\(chasm.start)〜\(chasm.end)）ではない場所で終わった（\(field.distance)）"
                )
            }
        }
        #expect(checked >= 10, "裂け目が \(checked) 本しか無い（この検証が空振りしている）")
        #expect(invincibleAtAChasm, "無敵のまま裂け目へ着く並びが 1 つも無い（43 面のたこ焼き → 裂け目）")
    }

    /// ゆっくりモードでも同じ操作で渡れること（時間が一様に遅くなるだけで軌道は相似）。
    @Test("ゆっくりモードでも二段ジャンプで渡れる")
    func slowModeKeepsTheChasmCrossable() {
        let speed = Self.chasmStageSpeeds.max() ?? RunnerRules.endlessMaxSpeed
        let stage = Self.soloStage(speed: speed)
        let chasm = stage.hazards[0]
        var field = RunnerField(stage: stage)
        let takeOff = chasm.start - RunnerAutoPilot.lead(for: chasm, speed: speed)
        var crossed = false
        var secondJumps = 0
        for _ in 0..<(120 * 30) {
            if field.isGrounded, field.distance >= takeOff, secondJumps == 0, field.jumpCount == 0 {
                field.jump()
            } else if !field.isGrounded, field.jumpCount == 1, field.vy <= 0 {
                field.endHold()
                if field.jump() { secondJumps += 1 }
            }
            let events = field.step(dt: RunnerRules.slowFactor / 120)
            if events.contains(.fell) { break }
            if field.isGrounded, field.distance >= chasm.end { crossed = true; break }
        }
        #expect(secondJumps == 1)
        #expect(crossed, "ゆっくりモードで渡れない")
    }

    // MARK: - 置き方（塀から写した「入れない組み合わせ」）

    @Test("裂け目は雪国より前には置かれず、雪国では 43 面に 1 本・48 面に 3 本、どの面にも 1 本以上ある")
    func chasmsAppearOnlyInSnow() {
        // 雪国で覚えた仕掛けは後ろの世界（東京・#2729）でも混ぜる（設計書「雪国の裂け目も混ぜてよい」）。
        // 置けるのは速さが上限 60 に達した面だけ（幅 52 の根拠）なので、雪国より前の面には無い。
        for stage in RunnerStage.all where stage.number < 43 {
            #expect(!stage.pattern.contains("V"), "ステージ \(stage.number) に裂け目がある")
        }
        for stage in RunnerStage.all where stage.hazards.contains(where: { $0.kind == .chasm }) {
            #expect(stage.speed == RunnerRules.endlessMaxSpeed, "ステージ \(stage.number) の裂け目は速さ \(stage.speed) の面に置かれている")
        }
        let counts = Self.snowStages.map { $0.hazards.filter { $0.kind == .chasm }.count }
        #expect(counts.count == 6)
        #expect(counts.allSatisfy { $0 >= 1 }, "裂け目の無い面がある: \(counts)")
        #expect(counts.first == 1, "初出の 43 面は 1 本だけで覚えさせる: \(counts)")
        #expect(counts.last == 3, "締めの 48 面は全部入り（3 本）: \(counts)")
        // 速さは全面 60（幅 52 の根拠はこの速さ。遅い面には置けない）。
        for stage in Self.snowStages {
            #expect(stage.speed == RunnerRules.endlessMaxSpeed, "ステージ \(stage.number) の速さが \(stage.speed)")
        }
    }

    /// **新しい仕組みは初めて出す面で前後を平地にして単独で見せる**（#1009 C2）。43 面の 1 本目はたこ焼きの直後
    /// （設計書「たこ焼きの後ろに置き『二段で渡る』だけに集中させる」）で、着地点は平地。
    @Test("裂け目の初出（43 面）の 1 本目は、手前がたこ焼きか平地で、着地点が平地")
    func firstChasmStandsAlone() {
        let pattern = Array(RunnerStage.all[42].pattern)
        guard let index = pattern.firstIndex(of: "V") else { Issue.record("43 面に裂け目が無い"); return }
        #expect(index > 0 && (pattern[index - 1] == "-" || pattern[index - 1] == RunnerStage.takoyakiSymbol))
        #expect(index + 1 < pattern.count && pattern[index + 1] == "-")
    }

    /// 塀と同じ決まり: **着地点（2 区画）に穴・突き上げ・沈む床・動物・鳥・崩れる足場を置かない**。
    /// 岩は 2 区画目に置いてよい（`V-n`「着地してすぐ軽く跳ぶ」。1 区画目は二段で降りてくる最中なので置けない）。
    @Test("裂け目の着地点に穴・突き上げ・沈む床・動物・鳥・崩れる足場が無く、1 区画目は素の平地")
    func chasmsLeaveSafeLandingGround() {
        var seen = 0
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "V" {
                seen += 1
                if pattern.indices.contains(index + 1) {
                    #expect(pattern[index + 1] == "-", "ステージ \(stage.number): 裂け目（区画 \(index)）の直後が平地でない")
                }
                for offset in 1...RunnerRules.wallLandingSegments {
                    let landing = index + offset
                    guard pattern.indices.contains(landing) else { continue }
                    #expect(
                        !"123^~dibCV".contains(pattern[landing]),
                        "ステージ \(stage.number): 裂け目（区画 \(index)）の着地点 \(landing) が \(pattern[landing])"
                    )
                }
            }
        }
        #expect(seen > 0, "裂け目が 1 本も置かれていない（この検証が空振りしている）")
    }

    /// 塀と同じ決まり: **手前の一定距離に鳥を置かない**（鳥は下を走り抜ける相手で、二段ジャンプの軌道は帯を通る）。
    /// 47 面は鳥を裂け目の 2 区画前に置いて「跳ぶな → 二段で跳べ」の切り替えを出す——そのぶん座標でも見る。
    @Test("裂け目の手前に鳥が無く、鳥をくぐってから踏み切り直す余地がある")
    func noBirdRightBeforeAChasm() {
        var birdsBeforeChasms = 0
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "V" {
                for offset in 1...RunnerRules.wallBirdClearanceSegments {
                    let before = index - offset
                    guard pattern.indices.contains(before) else { continue }
                    #expect(pattern[before] != "b", "ステージ \(stage.number): 裂け目（区画 \(index)）の \(offset) 区画手前が鳥")
                }
            }
            for chasm in stage.hazards where chasm.kind == .chasm {
                let takeOff = chasm.start - RunnerAutoPilot.lead(for: chasm, speed: stage.speed)
                for bird in stage.hazards where bird.kind == .bird {
                    let mustRun = bird.encounter.start...bird.encounter.end
                    guard mustRun.lowerBound < chasm.start, mustRun.upperBound > chasm.start - 3 * 64 else { continue }
                    birdsBeforeChasms += 1
                    #expect(
                        mustRun.upperBound + Self.half < takeOff,
                        "ステージ \(stage.number): 鳥（\(bird.start)）をくぐってから裂け目の踏み切り（\(takeOff)）に間に合わない"
                    )
                }
            }
        }
        #expect(birdsBeforeChasms > 0, "裂け目の 2〜3 区画前に鳥のある面（47 面）が無い（この検証が空振りしている）")
    }

    /// 速さ 34 のショーケースでは二段でも渡れない（幅は速さ 60 で決めた）ので置かない。エンドレスの生成器にも教えていない。
    @Test("QA用ショーケースとエンドレスには裂け目が出ない")
    func chasmIsNotInTheShowcaseOrEndless() {
        #if DEBUG
        #expect(!RunnerStage.debugShowcase.pattern.contains("V"))
        #expect(RunnerRules.doubleJumpRange(at: RunnerStage.debugShowcase.speed) < RunnerRules.chasmWidth + RunnerAutoPilot.baseLead,
                "ショーケースの速さでも渡れるなら置いて撮れる（この注記を直す）")
        #endif
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                if let next = field.nextHazard(from: field.playerMaxX) {
                    #expect(next.kind != .chasm, "種 \(seed) のエンドレスに裂け目が出た")
                }
            }
        }
    }

    // MARK: - 描画

    /// 子孫まで含めて、その色で塗られたノード（スプライトの色・図形の塗り）を数える（`RunnerWorldSceneTests` と同じ作法）。
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

    @Test("43 面は雪国の着せ替え（氷の裂け目・雪だるま・キツネ・雪柱・新雪・薄氷の橋・雪のブロック・アイスバーン）で組まれ、走らせても落ちない")
    @MainActor
    func snowSceneBuilds() throws {
        typealias P = RunnerWorld.DressingPalette
        let model = RunnerModel(startingAt: 43, preference: makePreference("snow-scene"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        #expect(scene.world == .snow)
        let stage = model.field.stage
        // 穴と裂け目は同じ氷の裂け目の絵（黒い水）で、本数ぶん塗られている。
        let gaps = stage.hazards.filter { $0.kind == .pit || $0.kind == .chasm }.count
        #expect(gaps > 0 && fillCount(in: scene.courseLayer, color: P.crevasseWater) >= gaps, "氷の裂け目の水が本数ぶん無い")
        // 裂け目の水は当たり判定の幅いっぱい（52）。
        let widths = scene.courseLayer.children.compactMap { ($0 as? SKSpriteNode) }
            .filter { $0.texture == nil && isSame($0.color, P.crevasseWater) }.map { Double($0.size.width) }
        #expect(widths.contains { abs($0 - RunnerRules.chasmWidth) < 1e-6 }, "裂け目の幅の水面が無い: \(widths)")
        // 雪だるまのテクスチャが低い岩の数だけ、高い岩は岩塊（テクスチャ無し）のまま。
        let lows = stage.hazards.filter { $0.kind == .lowBlock }.count
        let snowman = try #require(scene.blockTextures[.snowman])
        #expect(lows > 0 && spriteCount(in: scene.courseLayer, texture: snowman) == lows)
        // 突き上げは雪柱（その世界のぶんしかテクスチャを作らない）。
        #expect(scene.cachedShootStyles == [.snowSpout], "作ったテクスチャ: \(scene.cachedShootStyles)")
        // 沈む床（新雪）・崩れる足場（薄氷の橋）・台座（雪のブロック）・加速床（アイスバーン）の色が出ている。
        for (name, hex) in [("新雪", P.freshSnowSurface), ("薄氷の橋", P.iceDeck), ("雪のブロック", P.snowBlockTop), ("アイスバーン", P.iceSheet)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) > 0, "\(name)の色が出ていない")
        }
        // 他の世界の色（田んぼ・木の板・木箱・舗装）は 1 つも出ない。
        for (name, hex) in [("田んぼ", P.paddyWater), ("足湯", P.footBathWater), ("木の板", P.crumbleDeck), ("木箱", P.crateWood), ("舗装", P.pavedAsphalt)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) == 0, "雪国に\(name)の色が出ている")
        }
        // 犬の枠はキツネ（犬と同じ格子）。
        let dogTextures = try #require(scene.dogTextures[.snow])
        let fox = RunnerPixelArt.walker(.walk0, world: .snow)
        #expect(fox.rows == RunnerPixelArt.foxWalk0Rows)
        #expect(Int(dogTextures[0].size().width) == fox.width && Int(dogTextures[0].size().height) == fox.height)
        // 遠景のタイルに丘以外（雪の壁・かまくら・家・枯れ木・雪）が載っている。
        for tile in scene.hillTiles { #expect(tile.children.count > 3, "遠景のタイルに丘しか無い") }

        // 自動操縦で 15 秒ぶん走らせて反映しても落ちない（裂け目の二段・新雪・薄氷の経路を通る）。
        model.press()
        model.release()
        for _ in 0..<900 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(model.phase.isRunning || model.phase == .cleared, "43 面で 15 秒以内にミスした")
    }

    @Test("46 面の雪山（高い塀）は石垣・コンテナと別の絵で、その世界のぶんしかテクスチャを作らない")
    @MainActor
    func snowBankUsesItsOwnArt() {
        let model = RunnerModel(startingAt: 46, preference: makePreference("snow-wall"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        #expect(scene.world.dressing.wall == .snowBank)
        #expect(scene.cachedWallStyles == [.snowBank], "作ったテクスチャ: \(scene.cachedWallStyles)")
        let walls = model.field.stage.hazards.filter { $0.kind == .wall }
        #expect(walls.count == 1, "46 面の雪山が \(walls.count) 本（空振り防止）")
        #expect(spriteCount(in: scene.courseLayer, texture: scene.wallTexture(.snowBank)) == walls.count)
        let bank = RunnerPixelArt.snowBankRows.joined()
        #expect(bank.contains("F") && bank.contains("I") && bank.contains("J"), "雪山に雪と氷の階調が無い")
        for other in ["G", "g", "W", "R", "r", "O"] { #expect(!bank.contains(other), "雪山に石垣・コンテナの色 \(other) が混ざっている") }
    }
}
