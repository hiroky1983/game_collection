import Foundation
import SpriteKit
import Testing
@testable import GameRunner

/// 温泉街（37〜42 面・#1938）の新しい仕掛け 2 つ——間欠泉（`g`）と湯けむり（`m`）。
///
/// どちらも**走者の距離だけで決まる**（時計を持たない）ので、ペダルの乗り・ゆっくりモード・一時停止に
/// 左右されない。間欠泉は噴いていない間に走者の x と重ならないこと（＝重なる区間は常に噴き切っている）が
/// 公平さの根拠で、湯けむりは踏み切りの地点を決して隠さないことが根拠。
@Suite("チャリンコおじさん: 温泉街の間欠泉と湯けむり")
@MainActor
struct RunnerOnsenGimmickTests {
    private static let half = RunnerField.Metrics.playerHalfWidth
    private static let onsenStages = RunnerStage.all.filter { RunnerWorld.world(forStage: $0.number) == .onsen }

    private static func geyser(segmentIndex: Int = 4) -> RunnerHazard {
        RunnerHazard(
            kind: .geyser,
            start: Double(segmentIndex) * Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
                + Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth,
            length: RunnerRules.tileWidth
        )
    }

    // MARK: - 間欠泉の時刻表

    @Test("間欠泉は 噴く → 引く → 止まる（泡立ち）→ 噴き切る → 居座る → 引く の順で、間合いだけで決まる")
    func geyserFollowsItsSchedule() {
        let g = Self.geyser()
        let full = RunnerHazardKind.shootTop
        func rise(atGap gap: Double) -> Double {
            g.geyserRise(atRunnerDistance: g.start - Self.half - gap)
        }
        #expect(rise(atGap: RunnerRules.geyserViewDistance + 1) == 0, "画面の外")
        #expect(rise(atGap: 65) == full, "1 回目の噴き")
        let falling = rise(atGap: 56)
        #expect(falling > 0 && falling < full, "湯柱が引いていく（\(falling)）")
        #expect(rise(atGap: 48) == 0, "止まっている")
        let rising = rise(atGap: 39)
        #expect(rising > 0 && rising < full, "2 回目の噴きが伸びていく（\(rising)）")
        #expect(rise(atGap: RunnerRules.geyserEruptFullGap) == full)
        for gap in stride(from: RunnerRules.geyserEruptFullGap, through: -(g.length + RunnerField.Metrics.playerWidth), by: -1) {
            #expect(rise(atGap: gap) == full, "重なる区間は常に噴き切っている（間合い \(gap)）")
        }
        #expect(rise(atGap: -200) == 0, "走者の後ろでは引き切っている")
        // 引くのは単調（途中で戻らない）で、伸びるのも単調。
        var previous = 0.0
        for gap in stride(from: RunnerRules.geyserRestUntilGap, through: RunnerRules.geyserEruptFullGap, by: -0.5) {
            let r = rise(atGap: gap)
            #expect(r >= previous, "伸びる途中で戻っている（間合い \(gap)）")
            previous = r
        }
    }

    @Test("泡立ち（噴く前の合図）は止まってから噴き切るまでの間だけ出る")
    func simmerCueWindow() {
        let g = Self.geyser()
        func simmering(atGap gap: Double) -> Bool {
            g.isSimmering(atRunnerDistance: g.start - Self.half - gap)
        }
        #expect(!simmering(atGap: 65), "1 回目の噴きの最中は泡立たない")
        #expect(simmering(atGap: 50))
        #expect(simmering(atGap: 40))
        #expect(!simmering(atGap: RunnerRules.geyserEruptFullGap), "噴き切ったら止まる")
        #expect(!simmering(atGap: 0))
    }

    @Test("止まっている・伸びている最中の間欠泉は、走者の x と重ならない（当たる時は必ず噴き切っている）")
    func geyserNeverOverlapsTheRunnerWhileResting() {
        for stage in Self.onsenStages {
            for geyser in stage.hazards where geyser.kind == .geyser {
                var d = geyser.geyserCueDistance - 20
                while d < geyser.end + 40 {
                    defer { d += 0.25 }
                    guard let frame = geyser.frame(atRunnerDistance: d) else {
                        Issue.record("間欠泉の枠が無い（\(stage.number) 面）")
                        return
                    }
                    let overlaps = frame.start < d + Self.half && d - Self.half < frame.end
                    if overlaps { #expect(frame.top == RunnerHazardKind.shootTop, "\(stage.number) 面・距離 \(d): 噴き切る前に重なっている") }
                }
            }
        }
    }

    @Test("間欠泉は踏み切りの地点より手前で噴き切っていて、最速でも反応する余裕がある")
    func geyserFinishesRisingBeforeTheTakeOffPoint() {
        var checked = 0
        for stage in Self.onsenStages {
            for geyser in stage.hazards where geyser.kind == .geyser {
                checked += 1
                let takeOff = geyser.encounter.start - RunnerAutoPilot.lead(for: geyser, speed: stage.speed)
                #expect(geyser.geyserRise(atRunnerDistance: takeOff) == RunnerHazardKind.shootTop, "\(stage.number) 面")
                // 噴き切った地点から踏み切り地点まで。ペダルが上限（1.55 倍）まで乗った速さでも 0.18 秒以上。
                let fullAt = geyser.start - Self.half - RunnerRules.geyserEruptFullGap
                let seconds = (takeOff - fullAt) / (stage.speed * RunnerRules.maxPedalBoost)
                #expect(seconds > 0.18, "\(stage.number) 面: 噴き切りから踏み切りまで \(seconds) 秒")
            }
        }
        #expect(checked >= 12, "温泉街の間欠泉が \(checked) 本しかない（空振り防止）")
    }

    @Test("間欠泉を跳ばずに走ると、その間欠泉でミスになる（岩のかわりに何もしないと当たる）")
    func ignoringAGeyserCrashes() {
        for stage in Self.onsenStages {
            for geyser in stage.hazards where geyser.kind == .geyser {
                var field = RunnerField(stage: stage)
                field.placeForTesting(
                    distance: geyser.encounter.start - RunnerAutoPilot.lead(for: geyser, speed: stage.speed),
                    altitude: 0, vy: 0
                )
                var events: [RunnerEvent] = []
                var frames = 0
                while frames < 600, !events.contains(where: { $0 == .crashed || $0 == .fell }) {
                    frames += 1
                    events += field.step(dt: 1.0 / 60)
                    if field.distance > geyser.end + 20 { break }
                }
                #expect(events.contains(.crashed), "\(stage.number) 面の間欠泉を跳ばずに通り抜けられた")
                #expect(field.lastMissCause == .rock, "死因は岩と同じ（`AnalyticsEndCause` は増やさない）")
            }
        }
    }

    @Test("間欠泉は温泉街にだけ置かれ、各面に 2 本以上、後ろの面ほど減らない。37 面の初出は前後が平地")
    func geysersAppearOnlyInOnsen() {
        for stage in RunnerStage.all where stage.number < 37 {
            #expect(!stage.pattern.contains("g"), "ステージ \(stage.number) に間欠泉がある")
        }
        let counts = Self.onsenStages.map { $0.hazards.filter { $0.kind == .geyser }.count }
        #expect(counts.allSatisfy { $0 >= 2 }, "間欠泉が 2 本未満の面がある: \(counts)")
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 <= $1 || $0 - $1 <= 1 }, "後ろの面で大きく減っている: \(counts)")
        let first = Array(RunnerStage.all[36].pattern)
        let index = try? #require(first.firstIndex(of: "g"))
        if let index {
            #expect(first[index - 1] == "-", "37 面の初出の手前が平地でない")
            #expect(first[index + 1] == "-" || first[index + 1] == RunnerStage.steamSymbol, "37 面の初出の直後が平地（か湯けむり）でない")
        }
        #expect(RunnerHazardKind.geyser.missCause == .rock)
        #expect(RunnerHazardKind.geyser.height == RunnerHazardKind.tallBlock.height, "噴き切った高さは高い岩と同じ")
        #expect(!RunnerHazardKind.geyser.isRock, "突き上げと同じく、イノシシが止まる岩には数えない")
    }

    // MARK: - 湯けむり

    @Test("連続する m は 1 つの区間にまとまり、障害・台座・床には重ならない")
    func steamBanksMergeAndStayOnFlatGround() {
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let banks = RunnerStage.makeSteamBanks(pattern: "--m--mm-m")
        #expect(banks == [
            RunnerSteamBank(start: 2 * segment, length: segment),
            RunnerSteamBank(start: 5 * segment, length: 2 * segment),
            RunnerSteamBank(start: 8 * segment, length: segment),
        ])
        for stage in Self.onsenStages {
            let symbols = Array(stage.pattern)
            for (index, symbol) in symbols.enumerated() where symbol == RunnerStage.steamSymbol {
                for neighbour in [index - 1, index + 1] where symbols.indices.contains(neighbour) {
                    #expect(!"PC=".contains(symbols[neighbour]), "ステージ \(stage.number): 湯けむりが台座・床の隣")
                }
            }
            for bank in stage.steamBanks {
                #expect(!stage.hazards.contains { $0.start < bank.end && bank.start < $0.end }, "障害に重なっている")
            }
        }
    }

    @Test("湯けむりは温泉街の全面にあり、他の世界には無い")
    func steamOnlyInOnsen() {
        for stage in RunnerStage.all where stage.number < 37 {
            #expect(stage.steamBanks.isEmpty, "ステージ \(stage.number) に湯けむりがある")
        }
        for stage in Self.onsenStages {
            #expect(!stage.steamBanks.isEmpty, "ステージ \(stage.number) に湯けむりが無い")
        }
    }

    @Test("湯けむりの濃さは区間の中で 1、前後で線形に 0 へ、区間の無い面では常に 0")
    func steamIntensityRamp() {
        let bank = RunnerSteamBank(start: 200, length: 64)
        let ramp = RunnerRules.steamRampDistance
        #expect(bank.intensity(atRunnerDistance: 200 - ramp - 1) == 0)
        #expect(abs(bank.intensity(atRunnerDistance: 200 - ramp / 2) - 0.5) < 1e-9)
        #expect(bank.intensity(atRunnerDistance: 200) == 1)
        #expect(bank.intensity(atRunnerDistance: 232) == 1)
        #expect(bank.intensity(atRunnerDistance: 264) == 1)
        #expect(abs(bank.intensity(atRunnerDistance: 264 + ramp / 2) - 0.5) < 1e-9)
        #expect(bank.intensity(atRunnerDistance: 264 + ramp + 1) == 0)
        let plain = RunnerStage.all[0]
        #expect(plain.steamIntensity(atRunnerDistance: 100) == 0)
        let onsen = RunnerStage.all[36]
        let bankStart = try? #require(onsen.steamBanks.first).start
        if let bankStart { #expect(onsen.steamIntensity(atRunnerDistance: bankStart + 10) == 1) }
        #expect(onsen.steamIntensity(atRunnerDistance: 0) == 0)
    }

    @Test("湯けむりは踏み切りの地点（手前の間合い）を隠さず、濃さの上限も控えめ")
    func steamNeverHidesTheTakeOffZone() {
        var longestLead = 0.0
        for stage in RunnerStage.all {
            for hazard in stage.hazards {
                longestLead = max(longestLead, RunnerAutoPilot.lead(for: hazard, speed: stage.speed))
            }
        }
        #expect(
            RunnerRules.steamNearClearGap > longestLead,
            "かぶせない間合い \(RunnerRules.steamNearClearGap) が最長の踏み切りの余裕 \(longestLead) 以下"
        )
        #expect(RunnerRules.steamMaxAlpha <= 0.6, "濃すぎる")
        #expect(RunnerRules.steamNearClearGap < RunnerRules.shootTriggerDistance, "近くを空けすぎて、遠くに何もかぶせられない")
    }

    @Test("湯けむりの層は、区間に入ると見えて濃くなり、抜けると消える。走者より奥に置く")
    func steamLayerFollowsTheBank() throws {
        let model = RunnerModel(startingAt: 37, preference: makePreference("steam-layer"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        #expect(scene.steamLayer.isHidden, "走り出しでは湯けむりは見えない")
        #expect(RunnerScene.LayerZ.steam > RunnerScene.LayerZ.course && RunnerScene.LayerZ.steam < RunnerScene.LayerZ.player)
        let bank = try #require(model.field.stage.steamBanks.first)
        var field = model.field
        field.placeForTesting(distance: bank.start + 10, altitude: 0, vy: 0)
        scene.syncSteam(field)
        #expect(!scene.steamLayer.isHidden)
        #expect(abs(Double(scene.steamLayer.alpha) - RunnerRules.steamMaxAlpha) < 1e-6)
        #expect(!scene.steamLayer.children.isEmpty, "湯気の塊が無い")
        let left = RunnerField.Metrics.playerX + RunnerField.Metrics.playerHalfWidth + RunnerRules.steamNearClearGap
        #expect(scene.steamLayer.children.allSatisfy { $0.position.x >= left }, "近くにかぶさっている")
        field.placeForTesting(distance: bank.end + RunnerRules.steamRampDistance + 5, altitude: 0, vy: 0)
        scene.syncSteam(field)
        #expect(scene.steamLayer.isHidden)
        // 湯けむりの無い面では層は空のまま。
        let plain = RunnerModel(startingAt: 1, preference: makePreference("steam-layer-plain"))
        let plainScene = RunnerScene(model: plain)
        plainScene.rebuildCourse()
        #expect(plainScene.steamLayer.children.isEmpty)
    }

    // MARK: - 描画

    @Test("温泉街のコースは間欠泉の湯柱・湯けむり・サル・湯桶・足湯を組み、走らせても落ちない")
    func onsenSceneBuilds() throws {
        let model = RunnerModel(startingAt: 37, preference: makePreference("onsen-scene"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        #expect(scene.world == .onsen)
        let stage = model.field.stage
        let geysers = stage.hazards.filter { $0.kind == .geyser }
        let views = scene.movingHazards.filter { $0.hazard.kind == .geyser }
        #expect(views.count == geysers.count && !views.isEmpty, "間欠泉のノードが本数ぶん無い")
        #expect(scene.cachedShootStyles == [.steamColumn], "湯柱以外のテクスチャを作っている")
        let target = try #require(views.first)
        var field = RunnerField(stage: stage)
        // 噴いている・止まっている・伸びている各局面で、絵の位置が当たり判定の高さに追従する。
        for gap in [65.0, 56, 48, 39, 20, 0] {
            field.placeForTesting(distance: target.hazard.start - RunnerField.Metrics.playerHalfWidth - gap, altitude: 0, vy: 0)
            scene.syncMovingHazard(target, field: field)
            let frame = try #require(target.hazard.frame(atRunnerDistance: field.distance))
            #expect(!target.node.isHidden, "間欠泉は止まっていても隠さない（泡立ちの合図を見せる）")
            let expected = frame.top - RunnerHazardKind.shootTop
            #expect(abs(Double(target.riser?.position.y ?? 99) - expected) < 1e-6, "間合い \(gap): 絵が判定の高さに追従していない")
        }
        // 泡立ちの間だけ揺れる。
        field.placeForTesting(distance: target.hazard.start - RunnerField.Metrics.playerHalfWidth - 48, altitude: 0, vy: 0)
        scene.syncMovingHazard(target, field: field)
        #expect(target.state == .moving, "泡立ちの間は揺れる")
        field.placeForTesting(distance: target.hazard.start - RunnerField.Metrics.playerHalfWidth - 10, altitude: 0, vy: 0)
        scene.syncMovingHazard(target, field: field)
        #expect(target.state == .stopped, "噴き切ったら止まる")
    }
}
