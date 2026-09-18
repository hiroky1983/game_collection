import CoreEngine
import Foundation
import Testing
@testable import GameRunner

/// 二段ジャンプでしか越えられない高い塀（#1091・里山＝石垣・港町＝積まれたコンテナ）の検証。
///
/// 塀は「高さだけが違う高い岩」なので当たり判定・置き方の検査は既存の仕組み
/// （`RunnerStageTests.everyHazardIsClearable` / `hazardsAreFarEnoughApart`）にそのまま乗る。
/// **ここで固定するのは決裁が「妥協しない」と書いた 2 点**——
/// 一段ではどう跳んでも越えられないことと、二段目の押し始めに十分な幅があること——と、
/// #1009 の「入れない組み合わせ」（着地点・鳥・イノシシ）。
@Suite("チャリンコおじさん: 二段ジャンプの高い塀")
struct RunnerDoubleJumpWallTests {
    /// 本編で塀が置かれている面の基準速（決裁の「置いた面の速さ（48.4〜57.2）それぞれで」）。
    private static var wallStageSpeeds: [Double] {
        RunnerStage.all.filter { $0.hazards.contains { $0.kind == .wall } }.map(\.speed)
    }

    /// 塀 1 つだけを置いた検証用のコース。前後は平地で、踏み切りの余地を十分に取る。
    private static func soloStage(speed: Double) -> RunnerStage {
        RunnerStage(number: 0, pattern: "-----w------", speed: speed)
    }

    /// 走らせた結果。`cleared` は塀の右端を体ごと通り抜けたか。
    private struct Run {
        var cleared = false
        var crashed = false
        var usedSecondJump = false
        var peak: Double = 0
    }

    /// 1 回のジャンプで塀に挑む。`secondJumpAt` に秒を渡すと、踏み切りからその時間が経った
    /// 最初のフレームで二段目を踏む（nil なら一段だけ）。`tapFirstJump` は「押して即離す」操作。
    ///
    /// 踏み切る地点は自動操縦と同じ（`RunnerAutoPilot.lead`）。`takeOffShift` でそこから
    /// 前後にずらせる——「どう跳んでも一段では越えられない」を踏み切り位置ごと確かめるため。
    private static func attempt(
        speed: Double, secondJumpAt: Double?, tapFirstJump: Bool = false, takeOffShift: Double = 0
    ) -> Run {
        let stage = soloStage(speed: speed)
        guard let wall = stage.hazards.first(where: { $0.kind == .wall }) else { return Run() }
        var field = RunnerField(stage: stage)
        let takeOff = wall.start - RunnerAutoPilot.lead(for: wall, speed: speed) + takeOffShift
        var result = Run()
        var elapsed: Double?
        let dt = 1.0 / 120
        for _ in 0..<(120 * 20) {
            if field.isGrounded, field.distance >= takeOff {
                field.jump()
                if tapFirstJump { field.endHold() }
                elapsed = 0
            } else if let since = elapsed, let at = secondJumpAt, !result.usedSecondJump, since >= at {
                // 実際の操作と同じ「一度離してから押し直す」順（`RunnerModel.press()` は
                // 押しっぱなしの二度押しを弾く）。
                field.endHold()
                result.usedSecondJump = field.jump()
            }
            let events = field.step(dt: dt)
            if let since = elapsed { elapsed = since + dt }
            result.peak = max(result.peak, field.altitude)
            if events.contains(.crashed) || events.contains(.fell) {
                result.crashed = true
                return result
            }
            if field.playerMinX > wall.end {
                result.cleared = true
                return result
            }
        }
        return result
    }

    // MARK: - 高さの設計

    @Test("塀の高さは一段の頂点より高く、二段の頂点より低い")
    func wallHeightSitsBetweenTheTwoApexes() {
        let top = RunnerHazardKind.wall.height
        #expect(top == RunnerHazardKind.wallTop)
        #expect(top > RunnerRules.jumpApex + RunnerAutoPilot.clearance, "一段で越えられてしまう高さ")
        #expect(top < RunnerRules.doubleJumpApex, "二段でも越えられない高さ")
        // 決裁の受け入れ条件「両側の余裕とその根拠」。下側は**走者の背丈の 1/4 以上**
        // （3.94 ≒ 11 / 2.8）——踏み切り方の違いで埋まる差ではない。上側の余裕は
        // 「二段目の押し始めの猶予」そのものなので、`doubleJumpWindowIsGenerousOnEveryStage` が測る。
        #expect(
            top - RunnerRules.jumpApex >= RunnerField.Metrics.playerHeight / 4,
            "一段の頂点との余裕が薄い（\(top - RunnerRules.jumpApex)）"
        )
        #expect(top >= RunnerHazardKind.tallBlock.height * 2, "高い岩の 2 倍に届かない高さ")
        // 当たり判定は高い岩と同じ作り（地面から生えていて、上には乗れない）で、高さだけが違う。
        #expect(RunnerHazardKind.wall.bottom == 0)
        #expect(top > RunnerHazardKind.tallBlock.height)
        #expect(RunnerHazardKind.wall.missCause == RunnerHazardKind.tallBlock.missCause)
        #expect(!RunnerHazardKind.wall.isRock, "塀が岩に数えられている（イノシシが止まってしまう）")
    }

    @Test("区画記号 w が幅 1 タイルの塀に展開される")
    func wallSymbolExpandsToASingleTileHazard() {
        let stage = RunnerStage(number: 1, pattern: "--w--", speed: 40)
        #expect(stage.hazards.count == 1)
        let wall = stage.hazards[0]
        #expect(wall.kind == .wall)
        #expect(wall.length == RunnerRules.tileWidth)
        #expect(wall.height == RunnerHazardKind.wallTop)
        // 台座ではない（上には乗れない）。
        #expect(stage.platforms.isEmpty)
        // 横に動かないので、走者から見た区間は置いた位置そのもの。
        #expect(wall.encounter.start == wall.start)
        #expect(wall.encounter.length == wall.length)
        #expect(wall.frame(atRunnerDistance: 0)?.top == RunnerHazardKind.wallTop)
        #expect(wall.frame(atRunnerDistance: 10_000)?.advance == 0)
    }

    // MARK: - 公平さ（決裁「妥協しない」）

    /// **一段ジャンプではどう跳んでも越えられない**こと。踏み切る地点を塀の手前 60 単位から
    /// 塀の先 20 単位まで 2 単位ずつずらし、**いちばん伸びる全弾道（押しっぱなし）**で挑んで
    /// すべてミスになることを実際に走らせて確かめる（頂点が 14.06 で塀が 18 なので、
    /// 本当は踏み切り位置に関係なく届かない——それでも位置を振るのは、式ではなく実測で言うため）。
    @Test("一段ジャンプでは、どこで踏み切っても塀を越えられない")
    func singleJumpNeverClearsTheWall() {
        for speed in Self.wallStageSpeeds {
            for shift in stride(from: -60.0, through: 20.0, by: 2.0) {
                let run = attemptSingle(speed: speed, takeOffShift: shift)
                #expect(!run.cleared, "速さ \(speed)・ずらし \(shift) で一段のまま越えられた")
                #expect(run.peak < RunnerHazardKind.wallTop, "一段で塀の高さ \(run.peak) まで上がった")
            }
        }
    }

    private func attemptSingle(speed: Double, takeOffShift: Double) -> Run {
        Self.attempt(speed: speed, secondJumpAt: nil, takeOffShift: takeOffShift)
    }

    /// **二段目の押し始めに十分な幅がある**こと（決裁「目安 0.2 秒以上」）。
    ///
    /// 踏み切りは自動操縦と同じ地点に固定し、二段目を踏む時刻だけを 1/120 秒刻みで動かして
    /// 「越えられた時刻の連続した幅」を測る。**一段目を長押しした場合と、押して即離した
    /// （＝弾道が切り詰められる）場合の両方**で見る。
    @Test("二段目の押し始めの猶予が、置いた面の速さすべてで 0.2 秒以上ある")
    func doubleJumpWindowIsGenerousOnEveryStage() {
        for speed in Self.wallStageSpeeds {
            for tap in [false, true] {
                let window = Self.widestWindow(speed: speed, tapFirstJump: tap)
                #expect(
                    window >= 0.2,
                    "速さ \(speed)（一段目は\(tap ? "タップ" : "長押し")）の二段目の猶予が \(window) 秒しかない"
                )
            }
        }
    }

    /// 越えられる「二段目の押し始め」の連続した幅（秒）。
    ///
    /// 踏み切る地点も遊ぶ人が選べるので、**自動操縦の踏み切り（＝いちばん遅い地点）から
    /// 手前へずらした場合も含めていちばん広い幅**を採る。刻みを細かくするほど正確になるが、
    /// 走らせる回数がそのまま CI の時間になる（#1039）ので 3 単位刻みで足りる粗さにしてある。
    private static func widestWindow(speed: Double, tapFirstJump: Bool) -> Double {
        let step = 1.0 / 120
        var best = 0.0
        for shift in stride(from: 0.0, through: -12.0, by: -6.0) {
            var current = 0.0
            for t in stride(from: 0.0, through: 0.9, by: step) {
                let run = attempt(
                    speed: speed, secondJumpAt: t, tapFirstJump: tapFirstJump, takeOffShift: shift
                )
                if run.cleared, run.usedSecondJump {
                    current += step
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
        }
        return best
    }

    /// 自動操縦（= テストと撮影が共有する操作）が、実際に二段目を踏んで塀を越えること。
    @Test("自動操縦は塀の前で二段目を踏み、塀のある面を走り切れる")
    func autoPilotUsesTheSecondJump() {
        for stage in RunnerStage.all where stage.hazards.contains(where: { $0.kind == .wall }) {
            var field = RunnerField(stage: stage)
            var maxJumpCount = 0
            var crashed = false
            for _ in 0..<(60 * 300) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                let events = field.step(dt: 1.0 / 60)
                maxJumpCount = max(maxJumpCount, field.jumpCount)
                if events.contains(.crashed) || events.contains(.fell) { crashed = true; break }
                if events.contains(.reachedGoal) { break }
            }
            #expect(!crashed, "ステージ \(stage.number) で自動操縦がミスした")
            #expect(maxJumpCount == 2, "ステージ \(stage.number) で二段目を一度も踏んでいない")
        }
    }

    /// 二段目を踏まなければ当たること（塀が「跳べば越えられる岩」に退化していない裏取り）。
    @Test("塀の手前で一段だけ跳ぶと必ずぶつかり、死因は岩と同じ rock")
    func ignoringTheSecondJumpCrashesWithRockCause() {
        let speed = Self.wallStageSpeeds.min() ?? RunnerRules.baseSpeed
        let stage = Self.soloStage(speed: speed)
        var field = RunnerField(stage: stage)
        guard let wall = stage.hazards.first(where: { $0.kind == .wall }) else {
            Issue.record("塀が無い"); return
        }
        let takeOff = wall.start - RunnerAutoPilot.lead(for: wall, speed: speed)
        var crashed = false
        for _ in 0..<(60 * 20) {
            if field.isGrounded, field.distance >= takeOff { field.jump() }
            if field.step(dt: 1.0 / 60).contains(.crashed) { crashed = true; break }
        }
        #expect(crashed, "一段だけで通り抜けてしまった")
        #expect(field.lastMissCause == .rock, "死因が \(String(describing: field.lastMissCause))")
    }

    /// ゆっくりモード（アクセシビリティ）でも同じ操作で越えられること。時間が一様に遅くなるだけで
    /// 軌道は相似なので、**押し始めの実時間の猶予はむしろ広がる**。
    @Test("ゆっくりモードでも二段ジャンプで越えられ、猶予は狭くならない")
    @MainActor
    func slowModeKeepsTheWallClearable() {
        let speed = Self.wallStageSpeeds.max() ?? RunnerRules.baseSpeed
        let stage = Self.soloStage(speed: speed)
        guard let wall = stage.hazards.first(where: { $0.kind == .wall }) else {
            Issue.record("塀が無い"); return
        }
        var field = RunnerField(stage: stage)
        let takeOff = wall.start - RunnerAutoPilot.lead(for: wall, speed: speed)
        var cleared = false
        var secondJumps = 0
        // ゆっくりモードは `RunnerModel` が `dt` に `slowFactor` を掛ける（`RunnerField` は
        // 時間の出所を知らない）ので、ここでは同じ形——刻みを遅くして走らせる。
        for _ in 0..<(120 * 30) {
            if field.isGrounded, field.distance >= takeOff {
                field.jump()
            } else if !field.isGrounded, field.jumpCount == 1, field.vy <= 0 {
                field.endHold()
                if field.jump() { secondJumps += 1 }
            }
            let events = field.step(dt: RunnerRules.slowFactor / 120)
            if events.contains(.crashed) || events.contains(.fell) { break }
            if field.playerMinX > wall.end { cleared = true; break }
        }
        #expect(secondJumps == 1)
        #expect(cleared, "ゆっくりモードで越えられない")
    }

    // MARK: - 置き方（#1009 の「入れない組み合わせ」）

    @Test("塀は 19 面以降にだけ置かれていて、里山・港町の両方にある")
    func wallsOnlyAppearInTheNewWorlds() {
        for stage in RunnerStage.all.prefix(18) {
            #expect(!stage.pattern.contains("w"), "ステージ \(stage.number) に塀がある: \(stage.pattern)")
        }
        for (world, range) in [(RunnerWorld.satoyama, 19...24), (.harbor, 25...30)] {
            let count = RunnerStage.all
                .filter { range.contains($0.number) }
                .reduce(0) { $0 + $1.hazards.filter { $0.kind == .wall }.count }
            #expect(count >= 1, "\(world) に塀が \(count) 本しかない")
        }
    }

    /// **新しい仕組みは初めて出す面で前後を平地にして単独で見せる**（#1009 C2）。
    /// 石垣は 24 面、コンテナは 27 面が初出。
    @Test("塀の初出（24 面・27 面）の 1 本目は前後が素の平地")
    func firstWallOfEachWorldStandsAlone() {
        for number in [24, 27] {
            let pattern = Array(RunnerStage.all[number - 1].pattern)
            guard let index = pattern.firstIndex(of: "w") else {
                Issue.record("ステージ \(number) に塀が無い")
                continue
            }
            #expect(index > 0 && pattern[index - 1] == "-", "ステージ \(number): 1 本目の手前が平地でない")
            #expect(
                index + 1 < pattern.count && pattern[index + 1] == "-",
                "ステージ \(number): 1 本目の直後が平地でない"
            )
        }
    }

    /// 決裁の「入れない組み合わせ」: **着地点に穴・突き上げ・沈む床・動物を置かない**
    /// （滞空が長いぶん着地点を選べない）。着地点は塀の右端から
    /// `RunnerRules.wallLandingSegments` 区画（= 二段ジャンプの飛距離を区画に切り上げた長さ）。
    @Test("塀の着地点に穴・突き上げ・沈む床・動物が無い")
    func wallsLeaveSafeLandingGround() {
        var seen = 0
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "w" {
                seen += 1
                for offset in 1...RunnerRules.wallLandingSegments {
                    let landing = index + offset
                    guard pattern.indices.contains(landing) else { continue }
                    #expect(
                        !"123^~di".contains(pattern[landing]),
                        "ステージ \(stage.number): 塀（区画 \(index)）の着地点 \(landing) が \(pattern[landing])"
                    )
                }
            }
        }
        #expect(seen > 0, "塀が 1 本も置かれていない（この検証が空振りしている）")
        // 二段ジャンプの飛距離が、見ている区画数の内側に収まっていること（区画数の根拠）。
        let fastest = RunnerStage.all.map(\.speed).max() ?? RunnerRules.baseSpeed
        let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        #expect(
            RunnerRules.doubleJumpRange(at: fastest)
                <= Double(RunnerRules.wallLandingSegments) * segment
        )
    }

    /// 決裁の「入れない組み合わせ」: **塀の手前の一定距離に鳥を置かない**
    /// （鳥は下を走り抜ける相手で、塀を越える二段ジャンプの軌道はその帯を必ず通る）。
    @Test("塀の手前に鳥が無く、鳥をくぐってから踏み切り直す余地がある")
    func noBirdRightBeforeAWall() {
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "w" {
                for offset in 1...RunnerRules.wallBirdClearanceSegments {
                    let before = index - offset
                    guard pattern.indices.contains(before) else { continue }
                    #expect(
                        pattern[before] != "b",
                        "ステージ \(stage.number): 塀（区画 \(index)）の \(offset) 区画手前が鳥"
                    )
                }
            }
            // 字面だけでなく座標でも見る: 鳥のくぐる区間が、塀の踏み切り地点より手前で終わること。
            for wall in stage.hazards where wall.kind == .wall {
                let takeOff = wall.start - RunnerAutoPilot.lead(for: wall, speed: stage.speed)
                for bird in stage.hazards where bird.kind == .bird {
                    let mustRun = bird.encounter.start...bird.encounter.end
                    guard mustRun.lowerBound < wall.start else { continue }
                    #expect(
                        mustRun.upperBound + RunnerField.Metrics.playerHalfWidth < takeOff,
                        "ステージ \(stage.number): 鳥（\(bird.start)）をくぐってから塀の踏み切り（\(takeOff)）に間に合わない"
                    )
                }
            }
        }
    }

    /// 決裁の「入れない組み合わせ」: **塀の手前にイノシシを置かない**。
    /// 塀は岩に数えないので（`RunnerHazardKind.isRock`）、並べてもイノシシは止まらない
    /// ——「岩の手前に置くと岩で止まる」という読みが崩れる並びなので置かない。
    @Test("塀の手前の区画にイノシシが無く、イノシシは塀で止まらない")
    func noBoarRightBeforeAWall() {
        for stage in RunnerStage.all {
            let pattern = Array(stage.pattern)
            for (index, symbol) in pattern.enumerated() where symbol == "w" && index > 0 {
                #expect(pattern[index - 1] != "i", "ステージ \(stage.number): 区画 \(index) の塀の手前がイノシシ")
            }
            let wallEnds = Set(stage.hazards.filter { $0.kind == .wall }.map(\.end))
            for boar in stage.hazards where boar.kind == .boar {
                guard let stopAt = boar.stopAt else { continue }
                #expect(!wallEnds.contains(stopAt), "ステージ \(stage.number): イノシシが塀で止まっている")
            }
        }
        // 上の 2 つは今の並びに `iw` が無いので常に真。決定そのものを直接固定する。
        let synthetic = RunnerStage(number: 0, pattern: "---iw-----", speed: 40)
        let boar = synthetic.hazards.first { $0.kind == .boar }
        #expect(boar != nil, "合成ステージにイノシシが無い（空振り防止）")
        #expect(boar?.stopAt == nil, "イノシシが次の区画の塀で止まっている")
        #expect(synthetic.hazards.contains { $0.kind == .wall }, "合成ステージに塀が無い（空振り防止）")
    }

    /// エンドレス（#1086）には置かない（決裁「生成器には今回は置かない」）。
    @Test("エンドレスのコースには塀が出ない")
    func endlessCourseHasNoWalls() {
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                if let next = field.nextHazard(from: field.playerMaxX) {
                    #expect(next.kind != .wall, "種 \(seed) のエンドレスに塀が出た")
                }
            }
        }
    }

    /// QA 用ショーケース（`-simulateRunner wall` / `wall-double` の撮影）で塀を単体で見られること。
    @Test("QA用ショーケースに塀があり、前後は素の平地")
    func showcaseHasAWall() {
        let pattern = Array(RunnerStage.debugShowcase.pattern)
        guard let index = pattern.firstIndex(of: "w") else {
            Issue.record("ショーケースに塀が無い"); return
        }
        #expect(pattern[index - 1] == "-")
        #expect(pattern[index + 1] == "-")
        #expect(RunnerStage.debugShowcase.hazards.contains { $0.kind == .wall })
        // ショーケースの速さ（1 面と同じ 34）でも二段で越えられること。**本編より遅いぶん
        // 塀の横に居る時間が長く、猶予は本編の面より狭い**（撮影用のコースで、本編には出ない）。
        let window = Self.widestWindow(speed: RunnerStage.debugShowcase.speed, tapFirstJump: false)
        #expect(window >= 0.2, "ショーケースの猶予が \(window) 秒")
    }
}
