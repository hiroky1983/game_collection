import Core
import CoreEngine
import Foundation
import GameKitTestSupport
import SpriteKit
import Testing
@testable import GameRunner

/// 東京（49〜54 面・#2729）の新しい仕掛け——二段ジャンプでしか乗れない高い台座（`H`・歩道橋・
/// `RunnerRules.highPlatformHeight` = 16）。
///
/// 高い台座は「上面が 2 段ぶん高い台座」なので、接地面の解決・正面の当たり判定・置き方の検査は台座の既存の
/// 仕組み（`RunnerField.surfaceY` / `hittingPlatformFace` / `RunnerStageTests.platformsHaveFlatGroundOnBothSides`）に
/// そのまま乗る。**ここで固定するのは高い塀（`RunnerDoubleJumpWallTests`）・裂け目（`RunnerSnowGimmickTests`）と
/// 同じ 2 点**——一段ではどう跳んでも乗れないことと、二段目の押し始めに十分な幅があること——と、階段（`PH` / `HP`）が
/// 1 回ずつのジャンプ／走り出るだけで上がり降りできること、台座から写した置き方の決まり、東京の描画経路。
@Suite("チャリンコおじさん: 東京の歩道橋と着せ替え")
struct RunnerTokyoGimmickTests {
    private static let tokyoStages = RunnerStage.all.filter { RunnerWorld.world(forStage: $0.number) == .tokyo }
    private static let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth

    /// 本編で高い台座が置かれている面の基準速（東京は全部 60）。
    private static var footbridgeStageSpeeds: [Double] {
        Array(Set(RunnerStage.all.filter { $0.platforms.contains(where: \.isHigh) }.map(\.speed))).sorted()
    }

    /// 高い台座 1 基だけを置いた検証用のコース。前後は平地で、踏み切りの余地を十分に取る。
    private static func soloStage(speed: Double) -> RunnerStage {
        RunnerStage(number: 0, pattern: "-----H------", speed: speed)
    }

    /// 自動操縦と同じ踏み切りの余裕（地面から高い台座へ: 二段ジャンプで上面まで上がる時間）。
    private static func lead(for platform: RunnerPlatform, speed: Double) -> Double {
        RunnerAutoPilot.baseLead + speed * RunnerRules.doubleJumpRiseTime(to: platform.top + RunnerAutoPilot.clearance)
    }

    private struct Run {
        var landedOnTop = false
        var crashed = false
        var usedSecondJump = false
        var missObject: RunnerMissObject?
    }

    /// 1 回のジャンプで高い台座に挑む。`secondJumpAt` に秒を渡すと踏み切りからその時間が経った最初のフレームで
    /// 二段目を踏む（nil なら一段だけ）。踏み切る地点は自動操縦と同じで、`takeOffShift` でそこから前後にずらせる。
    private static func attempt(
        speed: Double, secondJumpAt: Double?, tapFirstJump: Bool = false, takeOffShift: Double = 0
    ) -> Run {
        let stage = soloStage(speed: speed)
        guard let bridge = stage.platforms.first(where: \.isHigh) else { return Run() }
        var field = RunnerField(stage: stage)
        let takeOff = bridge.start - lead(for: bridge, speed: speed) + takeOffShift
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
            if events.contains(.crashed) || events.contains(.fell) {
                result.crashed = true
                result.missObject = field.lastMissObject
                return result
            }
            if field.isGrounded, field.altitude == bridge.top, bridge.start < field.distance, field.distance < bridge.end {
                result.landedOnTop = true
                return result
            }
            if field.isGrounded, field.distance >= bridge.end { return result }
        }
        return result
    }

    // MARK: - 高さの設計

    @Test("高い台座は台座のちょうど 2 段ぶんで、一段の頂点より高く二段の頂点より低い")
    func highPlatformIsTwoSteps() {
        #expect(RunnerRules.highPlatformHeight == RunnerRules.platformHeight * 2)
        #expect(RunnerRules.highPlatformHeight > RunnerRules.jumpApex, "一段で乗れてしまう高さ")
        #expect(RunnerRules.highPlatformHeight + RunnerAutoPilot.clearance < RunnerRules.doubleJumpApex, "二段でも乗れない高さ")
        // 台座（8）から見れば 1 段ぶんなので、階段は一段のジャンプで上がれる。
        #expect(RunnerRules.highPlatformHeight - RunnerRules.platformHeight + RunnerAutoPilot.clearance < RunnerRules.jumpApex)
        // 降りた先の 1 区画で足りる: 高さ 16 を落ちるあいだに進む距離が 1 区画より十分短い。
        let fall = (2 * RunnerRules.highPlatformHeight / RunnerRules.gravity).squareRoot()
        #expect(RunnerRules.endlessMaxSpeed * fall < Self.segment / 2)
    }

    @Test("区画記号 H は高さ 16 の台座に展開され、P の隣では融合せず階段になる")
    func highPlatformSymbolExpands() {
        let stage = RunnerStage(number: 1, pattern: "-H-PH-HP-HH-", speed: 60)
        let s = Self.segment
        #expect(stage.platforms == [
            RunnerPlatform(start: s, length: s, top: RunnerRules.highPlatformHeight),
            RunnerPlatform(start: s * 3, length: s, top: RunnerRules.platformHeight),
            RunnerPlatform(start: s * 4, length: s, top: RunnerRules.highPlatformHeight),
            RunnerPlatform(start: s * 6, length: s, top: RunnerRules.highPlatformHeight),
            RunnerPlatform(start: s * 7, length: s, top: RunnerRules.platformHeight),
            RunnerPlatform(start: s * 9, length: s * 2, top: RunnerRules.highPlatformHeight),
        ])
        #expect(stage.platforms.filter(\.isHigh).count == 4)
        #expect(stage.platforms.allSatisfy { $0.kind == .solid })
        #expect(stage.hazards.isEmpty, "高い台座は障害ではない")
        #expect(RunnerStage.segmentSpec(RunnerStage.highPlatformSymbol) == nil)
        #expect(RunnerStage.platformKind(RunnerStage.highPlatformSymbol) == .solid)
        #expect(RunnerStage.platformSpec("H")?.top == RunnerRules.highPlatformHeight)
        #expect(RunnerStage.platformSpec("P")?.top == RunnerRules.platformHeight)
        // 接地面は高い台座の範囲で 16、台座で 8、外は地面。
        let field = RunnerField(stage: stage)
        let ground = RunnerField.Metrics.groundY
        #expect(field.surfaceY(at: s + 1) == ground + 16)
        #expect(field.surfaceY(at: s * 3 + 1) == ground + 8)
        #expect(field.surfaceY(at: s * 4 + 1) == ground + 16)
        #expect(field.surfaceY(at: s * 2 + 1) == ground)
    }

    // MARK: - 公平さ（塀・裂け目と同じ「妥協しない」）

    /// **一段ジャンプではどう跳んでも乗れない**こと。踏み切る地点を手前 60 から先 20 まで 2 単位ずつずらし、
    /// いちばん伸びる全弾道（押しっぱなし）で挑んで、すべて正面に当たってミス（高い台座の正面）になることを実走で確かめる。
    @Test("一段ジャンプでは、どこで踏み切っても高い台座に乗れず、歩道橋の正面でミスになる")
    func singleJumpNeverLandsOnTheFootbridge() {
        #expect(!Self.footbridgeStageSpeeds.isEmpty, "本編に高い台座が無い（空振り防止）")
        for speed in Self.footbridgeStageSpeeds {
            for shift in stride(from: -60.0, through: 20.0, by: 2.0) {
                let run = Self.attempt(speed: speed, secondJumpAt: nil, takeOffShift: shift)
                #expect(!run.landedOnTop, "速さ \(speed)・ずらし \(shift) で一段のまま乗れた")
                #expect(run.crashed, "速さ \(speed)・ずらし \(shift) でミスにならなかった")
                #expect(run.missObject == .highPlatformFace, "速さ \(speed)・ずらし \(shift) のミスの相手が \(String(describing: run.missObject))")
            }
        }
        var field = RunnerField(stage: Self.soloStage(speed: 60))
        let bridge = field.stage.platforms[0]
        field.placeForTesting(distance: bridge.start - Self.lead(for: bridge, speed: 60), altitude: 0, vy: 0)
        field.jump()
        var events: [RunnerEvent] = []
        for _ in 0..<600 where !events.contains(where: { $0.isTerminal }) { events += field.step(dt: 1.0 / 120) }
        #expect(events.contains(.crashed) && field.lastMissCause == .rock && field.lastMissObject == .highPlatformFace)
    }

    /// **二段目の押し始めに十分な幅がある**こと（塀・裂け目と同じ「目安 0.2 秒以上」）。
    @Test("二段目の押し始めの猶予が、置いた面の速さすべてで 0.2 秒以上ある")
    func doubleJumpWindowIsGenerous() {
        for speed in Self.footbridgeStageSpeeds {
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
                if run.landedOnTop, run.usedSecondJump {
                    current += step
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
        }
        return best
    }

    /// 自動操縦（= テストと撮影が共有する操作）が、実際に二段目を踏んで高い台座の上を走ること。
    @Test("自動操縦は高い台座の前で二段目を踏み、置いた高い台座すべての上を走り切る")
    func autoPilotRidesEveryFootbridge() {
        var checked = 0
        for stage in RunnerStage.all where stage.platforms.contains(where: \.isHigh) {
            checked += 1
            var field = RunnerField(stage: stage)
            var ridden: Set<Double> = []
            var secondJumpsTowardBridges = 0
            var finished = false
            for _ in 0..<(60 * 300) {
                if RunnerAutoPilot.shouldJump(field: field) {
                    if !field.isGrounded, let next = field.nextPlatform(from: field.playerMaxX), next.isHigh { secondJumpsTowardBridges += 1 }
                    field.jump()
                }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                let events = field.step(dt: 1.0 / 60)
                for bridge in stage.platforms where bridge.isHigh && field.isGrounded
                    && field.altitude == bridge.top && bridge.start < field.distance && field.distance < bridge.end {
                    ridden.insert(bridge.start)
                }
                if events.contains(.crashed) || events.contains(.fell) { Issue.record("ステージ \(stage.number) で自動操縦がミスした"); break }
                if events.contains(.reachedGoal) { finished = true; break }
            }
            #expect(finished, "ステージ \(stage.number) を走り切れない")
            #expect(ridden.count == stage.platforms.filter(\.isHigh).count, "ステージ \(stage.number): 乗っていない高い台座がある")
            #expect(secondJumpsTowardBridges >= 1, "ステージ \(stage.number) で高い台座に向かう二段目を一度も踏んでいない")
        }
        #expect(checked == 6, "高い台座のある面が \(checked) 面（東京の 6 面全部に置く）")
    }

    /// 階段。`PH` は台座（8）→ 高い台座（16）を**一段のジャンプ**ずつで上がり、`HP` は走り出れば**跳ばずに**降りて乗る。
    @Test("PH の階段は一段ずつのジャンプで上がり、HP の階段は跳ばずに降りる")
    func stairsNeedOnlySingleJumps() {
        for (pattern, expectJumpsOnFirst) in [("---PH-----", 1), ("---HP-----", 0)] {
            let stage = RunnerStage(number: 0, pattern: pattern, speed: 60)
            #expect(stage.platforms.count == 2, "\(pattern): 階段が 2 基に展開されない")
            let first = stage.platforms[0], second = stage.platforms[1]
            var field = RunnerField(stage: stage)
            var maxJumpCount = 0
            var jumpsOnFirst = 0
            var rodeFirst = false, rodeSecond = false
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) {
                    if field.isGrounded, first.start < field.distance, field.distance < first.end { jumpsOnFirst += 1 }
                    field.jump()
                }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                let events = field.step(dt: 1.0 / 60)
                maxJumpCount = max(maxJumpCount, field.jumpCount)
                if field.isGrounded, field.altitude == first.top, first.start < field.distance, field.distance < first.end { rodeFirst = true }
                if field.isGrounded, field.altitude == second.top, second.start < field.distance, field.distance < second.end { rodeSecond = true }
                if events.contains(.crashed) || events.contains(.fell) { Issue.record("\(pattern) でミスした"); break }
                if events.contains(.reachedGoal) { break }
            }
            #expect(rodeFirst && rodeSecond, "\(pattern): 階段の両方に乗っていない（\(rodeFirst), \(rodeSecond)）")
            #expect(jumpsOnFirst == expectJumpsOnFirst, "\(pattern): 1 基目の上で \(jumpsOnFirst) 回踏み切った")
            if pattern.hasPrefix("---P") {
                #expect(maxJumpCount == 1, "\(pattern): 上りの階段で二段目を踏んだ")
            } else {
                #expect(maxJumpCount == 2, "\(pattern): 地面から高い台座へ二段で乗っていない")
            }
        }
    }

    /// ゆっくりモードでも同じ操作で乗れること（時間が一様に遅くなるだけで軌道は相似）。
    @Test("ゆっくりモードでも二段ジャンプで乗れる")
    func slowModeKeepsTheFootbridgeReachable() {
        let speed = Self.footbridgeStageSpeeds.max() ?? RunnerRules.endlessMaxSpeed
        let stage = Self.soloStage(speed: speed)
        let bridge = stage.platforms[0]
        var field = RunnerField(stage: stage)
        let takeOff = bridge.start - Self.lead(for: bridge, speed: speed)
        var landed = false
        var secondJumps = 0
        for _ in 0..<(120 * 30) {
            if field.isGrounded, field.distance >= takeOff, secondJumps == 0, field.jumpCount == 0, field.altitude == 0 {
                field.jump()
            } else if !field.isGrounded, field.jumpCount == 1, field.vy <= 0 {
                field.endHold()
                if field.jump() { secondJumps += 1 }
            }
            let events = field.step(dt: RunnerRules.slowFactor / 120)
            if events.contains(.crashed) || events.contains(.fell) { break }
            if field.isGrounded, field.altitude == bridge.top { landed = true; break }
        }
        #expect(secondJumps == 1)
        #expect(landed, "ゆっくりモードで乗れない")
    }

    // MARK: - 置き方（台座から写した決まり）

    @Test("高い台座は東京にだけ置かれ、49 面に 1 基、54 面に階段 PH があり、どの面にも 1 基以上ある")
    func footbridgesAppearOnlyInTokyo() {
        for stage in RunnerStage.all where RunnerWorld.world(forStage: stage.number) != .tokyo {
            #expect(!stage.pattern.contains("H"), "ステージ \(stage.number) に高い台座がある")
        }
        let counts = Self.tokyoStages.map { $0.platforms.filter(\.isHigh).count }
        #expect(counts.count == 6)
        #expect(counts.allSatisfy { $0 >= 1 }, "高い台座の無い面がある: \(counts)")
        #expect(counts.first == 1, "初出の 49 面は 1 基だけで覚えさせる: \(counts)")
        #expect(RunnerStage.all[53].pattern.contains("PH"), "締めの 54 面に上りの階段が無い")
        #expect(RunnerStage.all[49].pattern.contains("PH") && RunnerStage.all[49].pattern.contains("HP"), "50 面に上りと下りの階段が無い")
        for stage in Self.tokyoStages {
            #expect(stage.speed == RunnerRules.endlessMaxSpeed, "ステージ \(stage.number) の速さが \(stage.speed)")
            #expect(stage.pattern.count == RunnerRules.maxSegments, "ステージ \(stage.number) の区画数が上限で止まっていない")
        }
    }

    /// **新しい仕組みは初めて出す面で前後を平地にして単独で見せる**（#1009 C2）。
    @Test("高い台座の初出（49 面）は前後が素の平地")
    func firstFootbridgeStandsAlone() {
        let pattern = Array(RunnerStage.all[48].pattern)
        guard let index = pattern.firstIndex(of: "H") else { Issue.record("49 面に高い台座が無い"); return }
        #expect(index > 0 && pattern[index - 1] == "-")
        #expect(index + 1 < pattern.count && pattern[index + 1] == "-")
    }

    /// 台座と同じ決まり（前後は素の平地）に、階段の例外と、高い台座にだけ要る 2 つを足す:
    /// **たこ焼きを 5 区画以内の手前に置かない**（無敵は台座の正面を素通りして上面に乗れるので、二段を踏まずに乗れてしまう）、
    /// **塀・裂け目の着地点の直後に置かない**（二段で降りてすぐの二段の踏み切りは間に合わない）。
    @Test("高い台座の隣は平地か階段の台座で、手前 5 区画にたこ焼きが無く、塀・裂け目の着地点の直後ではない")
    func footbridgesKeepTheirApproach() {
        var seen = 0
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "H" {
                seen += 1
                for neighbor in [index - 1, index + 1] where pattern.indices.contains(neighbor) {
                    #expect(
                        pattern[neighbor] == "-" || pattern[neighbor] == "P" || pattern[neighbor] == "H",
                        "ステージ \(stage.number): 高い台座（区画 \(index)）の隣（区画 \(neighbor)）が \(pattern[neighbor])"
                    )
                }
                for offset in 1...5 {
                    let before = index - offset
                    guard pattern.indices.contains(before) else { continue }
                    #expect(pattern[before] != RunnerStage.takoyakiSymbol, "ステージ \(stage.number): 高い台座（区画 \(index)）の \(offset) 区画手前がたこ焼き")
                }
                for offset in 1...2 {
                    let before = index - offset
                    guard pattern.indices.contains(before) else { continue }
                    #expect(!"wV".contains(pattern[before]), "ステージ \(stage.number): 高い台座（区画 \(index)）の \(offset) 区画手前が \(pattern[before])")
                }
            }
            // 上には何も置かない（台座と同じ）。
            for bridge in stage.platforms where bridge.isHigh {
                for hazard in stage.hazards {
                    #expect(!(hazard.start < bridge.end && bridge.start < hazard.end), "ステージ \(stage.number): 高い台座の上に障害がある")
                }
                for pickup in stage.pickups {
                    #expect(!(bridge.start <= pickup.start && pickup.start < bridge.end), "ステージ \(stage.number): 高い台座の上にアイテムがある")
                }
            }
        }
        #expect(seen >= 8, "高い台座が \(seen) 基しか無い（この検証が空振りしている）")
    }

    /// QA用ショーケース（速さ 34）には置かない（二段の踏み切りの余裕は 60 で確かめてある）。エンドレスの生成器にも教えていない。
    @Test("QA用ショーケースとエンドレスには高い台座が出ない")
    func footbridgeIsNotInTheShowcaseOrEndless() {
        #if DEBUG
        #expect(!RunnerStage.debugShowcase.pattern.contains("H"))
        #endif
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                if let next = field.nextPlatform(from: field.playerMaxX) {
                    #expect(!next.isHigh, "種 \(seed) のエンドレスに高い台座が出た")
                }
            }
        }
    }

    // MARK: - 色（#929 の規則）

    /// 東京の着せ替えた手前の物も、濃い側の主色が背景の全部と 3:1 以上（縁取りに頼らない部品）。
    @Test("東京の着せ替え（歩道橋の鉄骨・古い板の桁・動く歩道の帯・塗りたての舗装・看板の桁・蒸気の陰）は背景と 3:1 以上")
    func tokyoDressedForegroundStandsOut() {
        typealias P = RunnerWorld.DressingPalette
        let art = RunnerPixelArt.palette
        let items: [(String, UInt32)] = [
            ("歩道橋の桁", P.footbridgeGirder), ("歩道橋の鉄柵", P.footbridgeRail),
            ("古い歩道橋の板の桁", P.footbridgeDeckSeam), ("古い歩道橋の杭", P.footbridgePost),
            ("動く歩道の帯", P.walkwayBelt), ("塗りたての舗装", P.freshAsphaltSurface),
            ("看板の桁", art["q"]!), ("蒸気の陰", art["g"]!), ("カラーコーンの台", art["g"]!),
        ]
        for (name, color) in items {
            for (backdrop, hex) in RunnerWorld.tokyo.groundBackdrops {
                #expect(WCAG.contrast(color, hex) >= 3.0, "東京の\(name)が \(backdrop) (\(String(hex, radix: 16))) に溶ける")
            }
        }
        // 歩道橋の歩く面は台座の床板と同じく縁取り（世界の `outline`）で浮く。
        for (backdrop, hex) in RunnerWorld.tokyo.groundBackdrops {
            #expect(max(WCAG.contrast(P.footbridgeWalk, hex), WCAG.contrast(RunnerWorld.tokyo.outline, hex)) >= 3.0, "歩道橋の床板が \(backdrop) に溶ける")
        }
        // 看板の絵にコンテナ・石垣・雪山の色が混ざっていない。
        let sign = RunnerPixelArt.signboardStackRows.joined()
        #expect(sign.contains("Q") && sign.contains("q") && sign.contains("u"), "看板に青灰の階調が無い")
        for other in ["R", "r", "O", "G", "g", "F", "I", "J"] { #expect(!sign.contains(other), "看板に他の塀の色 \(other) が混ざっている") }
        // マンホールの蒸気は湯柱・雪柱と絵として別物（灰の階調 `c`/`p`）。
        let steam = RunnerPixelArt.manholeSteamRows.joined()
        #expect(steam.contains("c") && steam.contains("p") && steam.contains("g"))
        #expect(steam != RunnerPixelArt.steamColumnRows.joined() && steam != RunnerPixelArt.snowSpoutRows.joined())
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

    @Test("49 面は東京の着せ替え（歩道橋・カラーコーン・自動販売機・タクシー・蒸気・塗りたての舗装・古い板・動く歩道）で組まれ、走らせても落ちない")
    @MainActor
    func tokyoSceneBuilds() throws {
        typealias P = RunnerWorld.DressingPalette
        let model = RunnerModel(startingAt: 49, preference: makePreference("tokyo-scene"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        #expect(scene.world == .tokyo)
        let stage = model.field.stage
        // 歩道橋（高い台座）の歩く面と桁が基数ぶん塗られている。
        let bridges = stage.platforms.filter(\.isHigh).count
        #expect(bridges > 0 && fillCount(in: scene.courseLayer, color: P.footbridgeWalk) >= bridges, "歩道橋の床板が基数ぶん無い")
        #expect(fillCount(in: scene.courseLayer, color: P.footbridgeGirder) >= bridges, "歩道橋の桁が無い")
        #expect(fillCount(in: scene.courseLayer, color: P.footbridgeRail) >= bridges, "歩道橋の鉄柵が無い")
        // 足場（台座）は元の絵のまま。
        #expect(fillCount(in: scene.courseLayer, color: RunnerPalette.platformDeck) >= stage.platforms.filter { !$0.isHigh && $0.kind == .solid }.count)
        // カラーコーン・自動販売機のテクスチャが岩の数だけ。
        let lows = stage.hazards.filter { $0.kind == .lowBlock }.count
        let talls = stage.hazards.filter { $0.kind == .tallBlock }.count
        let cone = try #require(scene.blockTextures[.trafficCone])
        let vending = try #require(scene.blockTextures[.vendingMachine])
        #expect(lows > 0 && spriteCount(in: scene.courseLayer, texture: cone) == lows)
        #expect(talls > 0 && spriteCount(in: scene.courseLayer, texture: vending) == talls)
        // 突き上げはマンホールの蒸気（その世界のぶんしかテクスチャを作らない）。
        #expect(scene.cachedShootStyles == [.manholeSteam], "作ったテクスチャ: \(scene.cachedShootStyles)")
        // 塗りたての舗装・古い板・動く歩道の色が出ていて、他の世界の色は出ない。
        for (name, hex) in [("塗りたての舗装", P.freshAsphaltSurface), ("古い板", P.footbridgeDeck), ("動く歩道", P.walkwayBelt)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) > 0, "\(name)の色が出ていない")
        }
        for (name, hex) in [("足湯", P.footBathWater), ("新雪", P.freshSnowSurface), ("木の板", P.crumbleDeck), ("氷の板", P.iceDeck), ("コンベア", P.conveyorBelt), ("木箱", P.crateWood)] {
            #expect(fillCount(in: scene.courseLayer, color: hex) == 0, "東京に\(name)の色が出ている")
        }
        // 犬の枠は犬（秋田犬の色）で犬の格子。
        let dogTextures = try #require(scene.dogTextures[.tokyo])
        let dog = RunnerPixelArt.walker(.walk0, world: .tokyo)
        #expect(dog.rows == RunnerPixelArt.dogWalk0Rows)
        #expect(Int(dogTextures[0].size().width) == dog.width && Int(dogTextures[0].size().height) == dog.height)
        // 遠景のタイルに丘以外（ビル街・高架・電車・塔か信号機）が載っている。
        for tile in scene.hillTiles { #expect(tile.children.count > 3, "遠景のタイルに丘しか無い") }

        // 自動操縦で 15 秒ぶん走らせて反映しても落ちない（歩道橋の二段・塗りたての舗装・古い板の経路を通る）。
        model.press()
        model.release()
        for _ in 0..<900 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(model.phase.isRunning || model.phase == .cleared, "49 面で 15 秒以内にミスした")
    }

    @Test("52 面の看板（高い塀）は石垣・コンテナ・雪山と別の絵で、その世界のぶんしかテクスチャを作らない")
    @MainActor
    func signboardUsesItsOwnArt() {
        let model = RunnerModel(startingAt: 52, preference: makePreference("tokyo-wall"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        #expect(scene.world.dressing.wall == .signboardStack)
        #expect(scene.cachedWallStyles == [.signboardStack], "作ったテクスチャ: \(scene.cachedWallStyles)")
        let walls = model.field.stage.hazards.filter { $0.kind == .wall }
        #expect(walls.count == 1, "52 面の看板が \(walls.count) 本（空振り防止）")
        #expect(spriteCount(in: scene.courseLayer, texture: scene.wallTexture(.signboardStack)) == walls.count)
    }

    @Test("高い台座の正面に当たるとミスの相手は highPlatformFace、文言は歩道橋")
    func footbridgeFaceIsRecorded() {
        let stage = Self.soloStage(speed: 60)
        let bridge = stage.platforms[0]
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: bridge.start - 1, altitude: RunnerRules.platformHeight, vy: 0)
        #expect(field.isHittingPlatformFace)
        let events = field.step(dt: 1.0 / 120)
        #expect(events.contains(.crashed))
        #expect(field.lastMissCause == .rock && field.lastMissObject == .highPlatformFace)
        #expect(RunnerView.missText(cause: .rock, object: .highPlatformFace, world: .tokyo) == "歩道橋にぶつかった")
    }
}
