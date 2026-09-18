import CoreEngine
import Foundation
import Testing
@testable import GameRunner

/// 乗ると崩れる足場（#1090・里山＝古い吊り橋・港町＝古い木の桟橋）の検証。
///
/// 足場は台座（`RunnerPlatform`）なので `RunnerHazard` の成立条件
/// （`RunnerStageTests.everyHazardIsClearable`）は掛からない。**「渡り切れない足場が置けない」
/// ことは、ここで板張りの長さとその面の速さから機械的に確かめる**。
@Suite("チャリンコおじさん: 崩れる足場")
struct RunnerCrumblingPlatformTests {
    private static let segment = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
    private static let bank = Double(RunnerRules.crumbleBankTiles) * RunnerRules.tileWidth
    /// 崩れる足場が置いてある面の基準速。遅い面ほど渡るのに時間がかかる＝不利なので、
    /// 実走の検証はこの最小値で行う。
    ///
    /// **QA 用ショーケース（速さ 34）も数える。** 本編の最遅は 24 面の 52.4 だが、
    /// 足場が実際に置いてあるいちばん遅いコースはショーケースで、猶予（1.6 秒）と
    /// 二段ジャンプの飛距離（58.0）の根拠もそちらの数字で書いてある
    /// ——ここを本編だけにすると、根拠に挙げた下限が実走で 1 度も踏まれない
    /// （2026-09-18 の敵対的検証の指摘）。
    private static var crumbleStageSpeeds: [Double] {
        var speeds = RunnerStage.all.filter { !$0.crumblingPlatforms.isEmpty }.map(\.speed)
        #if DEBUG
        if !RunnerStage.debugShowcase.crumblingPlatforms.isEmpty {
            speeds.append(RunnerStage.debugShowcase.speed)
        }
        #endif
        return speeds
    }

    /// 本編（`RunnerStage.all`）で崩れる足場が置かれる面のうち、いちばん遅い基準速。
    ///
    /// **「乗らずに跳び越せる」はこちらで見る。** 台座は正面が壁なので、左端に届く前に
    /// 上面より高く上がっておく助走（`riseTime(to:) × speed`）が要り、その助走ぶんは
    /// 速さに比例しない——**速い面ほど跳び越しやすい**。ショーケース（34）では
    /// 助走 12.4 ＋ 板張り 48 = 60.4 が二段ジャンプの飛距離 58.0 を上回って越えられないが、
    /// 本編で置いてあるのは 24 面（52.4）以降で、そこでは 62.8 < 89.5 で越えられる。
    private static var slowestStoryCrumbleSpeed: Double {
        RunnerStage.all.filter { !$0.crumblingPlatforms.isEmpty }.map(\.speed).min()
            ?? RunnerRules.baseSpeed
    }

    /// `pattern` の足場の上に走者を立たせた `RunnerField`。
    private static func boarded(
        pattern: String, speed: Double
    ) -> (field: RunnerField, platform: RunnerPlatform) {
        let stage = RunnerStage(number: 1, pattern: pattern, speed: speed)
        guard let platform = stage.crumblingPlatforms.first else {
            fatalError("この並びに崩れる足場が無い: \(pattern)")
        }
        var field = RunnerField(stage: stage)
        field.placeForTesting(
            distance: platform.start, altitude: RunnerRules.platformHeight, vy: 0
        )
        return (field, platform)
    }

    // MARK: - 区画記号の展開

    /// 台座（`P`）と同じく連続ぶんは 1 基にまとまる。違うのは**両端に岸を残す**ことと、
    /// **種類が違えばまとまらない**こと。
    @Test("区画記号 → 崩れる足場: 連続する C は 1 基にまとまり、両端に岸のぶんだけ短くなる")
    func crumblingSymbolExpandsToMergedRunsWithBanks() {
        let stage = RunnerStage(number: 1, pattern: "-CC--C-PP-", speed: 40)
        #expect(stage.platforms.count == 3)
        let long = stage.platforms[0]
        #expect(long.kind == .crumbling)
        #expect(long.start == Self.segment + Self.bank)
        #expect(long.length == Self.segment * 2 - Self.bank * 2)
        let short = stage.platforms[1]
        #expect(short.kind == .crumbling)
        #expect(short.start == Self.segment * 5 + Self.bank)
        #expect(short.length == RunnerRules.crumbleDeckLength)
        let solid = stage.platforms[2]
        #expect(solid.kind == .solid, "P は従来どおり崩れない台座")
        #expect(solid.start == Self.segment * 7, "崩れない台座は区画まるごとのまま")
        #expect(solid.length == Self.segment * 2)
        #expect(solid.top == RunnerRules.platformHeight)
        // 足場は障害でもアイテムでも床でもない。
        #expect(stage.hazards.isEmpty)
        #expect(stage.boostFloors.isEmpty)
        #expect(stage.sinkFloors.isEmpty)
        #expect(RunnerStage.segmentSpec(RunnerStage.crumblingPlatformSymbol) == nil)
    }

    /// 隣り合っていても**種類が違えば別の基**。融合させると、崩れた側と残る側が 1 基に
    /// 混ざって「半分だけ消えた台座」になってしまう。
    @Test("P と C が隣り合っても 1 基に融合しない")
    func solidAndCrumblingNeverMerge() {
        let stage = RunnerStage(number: 1, pattern: "PC", speed: 40)
        #expect(stage.platforms.count == 2)
        #expect(stage.platforms[0].kind == .solid)
        #expect(stage.platforms[1].kind == .crumbling)
        #expect(stage.platforms[0].end == Self.segment)
        #expect(stage.platforms[1].start == Self.segment + Self.bank)
    }

    // MARK: - 公平さ（決裁「最低の乗りでも渡り切れる長さにする」）

    /// **これが足場の長さの上限そのもの**。接地中の速さは `speed × 乗り`（乗りは 1 以上）、
    /// 空中の横速度は必ず `speed` なので、どう跳んでも横の進みは `speed` を下回らない。
    /// 板張りの長さが `speed × crumbleDuration` 未満なら、崩れ切る前に必ず渡り切れる。
    @Test("置いてある崩れる足場は、どれも最低の乗りの速さで崩れ切る前に渡り切れる長さ")
    func crumblingPlatformsAreCrossableAtMinimumPedal() {
        var stages = RunnerStage.all
        #if DEBUG
        stages.append(.debugShowcase)
        #endif
        var seen = 0
        for stage in stages {
            for platform in stage.crumblingPlatforms {
                seen += 1
                let limit = RunnerRules.crumbleMaxLength(at: stage.speed)
                #expect(
                    platform.length < limit,
                    "ステージ \(stage.number): 板張り \(platform.length) が上限 \(limit) 以上"
                )
            }
        }
        #expect(seen > 0, "崩れる足場が 1 つも置かれていない（この検証が空振りしている）")
        // 2 区画ぶんはどの面の速さでも上限を超える＝連続した `C` は置けない。
        let twoSegments = Self.segment * 2 - Self.bank * 2
        let fastest = RunnerStage.all.map(\.speed).max() ?? RunnerRules.baseSpeed
        #expect(twoSegments >= RunnerRules.crumbleMaxLength(at: fastest))
    }

    /// 上の上限が「机上の式」で終わらないことを、いちばん遅い面の速さで実際に走らせて確かめる。
    /// **跳びながら渡る**——空中の横速度は基準速で、接地中の乗り（1 以上）より遅いので、
    /// これが実際に出せるいちばん遅い渡り方になる。着地し直しても崩れは早まらない。
    @Test("いちばん遅い面でも、跳びながら渡って崩れ切る前に抜けられる")
    func slowestStageIsCrossedEvenWhileJumping() {
        let speed = Self.crumbleStageSpeeds.min() ?? RunnerRules.baseSpeed
        var (field, platform) = Self.boarded(pattern: "--C----", speed: speed)
        var fell = false
        var frames = 0
        while frames < 60 * 10, field.distance <= platform.end {
            frames += 1
            // 接地したら即座に跳ぶ（いちばん空中に居る時間が長い＝いちばん遅い渡り方）。
            if field.isGrounded { field.jump() }
            if field.step(dt: 1.0 / 60).contains(.fell) { fell = true; break }
        }
        #expect(!fell, "跳びながら渡ると落ちた")
        #expect(field.distance > platform.end, "渡り切れていない")
        #expect(field.crumbleElapsed[0] != nil, "乗ったのに崩れが始まっていない")
    }

    /// 逆に、**上限を超える長さの足場なら必ず落ちる**（仕組みが効いている）。
    /// 死因は穴と同じ `pit`（決裁「`AnalyticsEndCause` を増やさない」）。
    @Test("渡り切れない長さの足場では、崩れ切った跡へ落ちて死因は pit")
    func tooLongPlatformDropsTheRunnerIntoThePit() {
        let stage = RunnerStage(number: 1, pattern: "-CCC-", speed: 20)
        let platform = stage.crumblingPlatforms[0]
        #expect(platform.length > RunnerRules.crumbleMaxLength(at: stage.speed), "この検証の前提")
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: platform.start, altitude: RunnerRules.platformHeight, vy: 0)
        var fell = false
        var frames = 0
        while frames < 60 * 20, !fell {
            frames += 1
            fell = field.step(dt: 1.0 / 60).contains(.fell)
        }
        #expect(fell, "崩れ切っても落ちない")
        #expect(field.lastMissCause == .pit)
        #expect(field.hasCrumbled(0))
        #expect(field.isCrumbledGap(at: platform.start + 1))
        #expect(field.surfaceY(at: platform.start + 1) == RunnerField.Metrics.groundY, "接地面が残っている")
    }

    /// **崩れ始めてから崩れ切るまでは乗れる**（決裁「どちらにするか決めてコメントに書き、
    /// テストで固定」への回答）。抜けるのは左から順なので、右へ進む走者は踏み外さない。
    @Test("板が抜け始めてからも、崩れ切るまでは足場の上に立てる")
    func theDeckStillCarriesTheRunnerWhileItIsFalling() {
        let stage = RunnerStage(number: 1, pattern: "-CCC-", speed: 20)
        let platform = stage.crumblingPlatforms[0]
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: platform.start, altitude: RunnerRules.platformHeight, vy: 0)
        var groundedAfterWarning = false
        var frames = 0
        while frames < 60 * 20 {
            frames += 1
            if field.step(dt: 1.0 / 60).contains(.fell) { break }
            guard let elapsed = field.crumbleElapsed[0] else { continue }
            if elapsed > RunnerRules.crumbleWarnDuration, elapsed < RunnerRules.crumbleDuration {
                #expect(field.isGrounded, "抜け落ちが始まった途端に足場から落ちた")
                #expect(field.surfaceY(at: field.distance) > RunnerField.Metrics.groundY)
                groundedAfterWarning = true
            }
        }
        #expect(groundedAfterWarning, "抜け落ちの最中を 1 フレームも観測できていない")
    }

    // MARK: - 崩れの時計

    /// きっかけは**初めて乗った瞬間だけ**。跳んで着地し直しても巻き戻らず、二重にも進まない
    /// （決裁「着地で崩れのきっかけが二重に起きないことを確かめる」）。
    @Test("跳んで着地し直しても崩れの時計は巻き戻らず、実時間どおりにだけ進む")
    func landingAgainNeitherRestartsNorDoublesTheClock() {
        var (field, _) = Self.boarded(pattern: "-CCC-", speed: 20)
        var previous: Double?
        var landings = 0
        for _ in 0..<90 {
            // 接地したらすぐ跳ぶ＝板の上で何度も着地し直す、いちばん時計を乱しやすい操作。
            if field.isGrounded { field.jump(); landings += 1 }
            _ = field.step(dt: 1.0 / 60)
            guard let clock = field.crumbleElapsed[0] else { continue }
            // 動き出したあとは**毎フレームちょうど dt だけ**進む。巻き戻れば負、二重に進めば
            // 2 dt になるので、この 1 本で「巻き戻らない」「二重にならない」の両方を押さえる。
            if let previous {
                #expect(
                    abs(clock - previous - 1.0 / 60) < 1e-9,
                    "崩れの時計が 1 フレームで \(clock - previous) 進んだ（dt は \(1.0 / 60)）"
                )
            }
            previous = clock
        }
        #expect(landings >= 3, "跳び直していない（この検証が空振りしている）")
        #expect(previous != nil, "崩れが始まっていない")
    }

    /// **乗らなければ崩れない**。岸で踏み切って二段目を頂点で踏めば、板に足を着けずに越えられる
    /// （`RunnerRules.crumbleBankTiles` が板張りを二段ジャンプの飛距離の内側に収めている）。
    ///
    /// 速さは**本編で足場を置いてある面のいちばん遅い側**（`slowestStoryCrumbleSpeed`）。
    /// ショーケースの 34 では助走ぶん届かない——その理由は同プロパティの doc にある。
    @Test("乗らずに二段ジャンプで跳び越せば足場は崩れない")
    func jumpingOverTheDeckLeavesItIntact() {
        let speed = Self.slowestStoryCrumbleSpeed
        let stage = RunnerStage(number: 1, pattern: "--C----", speed: speed)
        let platform = stage.crumblingPlatforms[0]
        var field = RunnerField(stage: stage)
        var usedSecondJump = false
        var touchedDeck = false
        for _ in 0..<(60 * 10) {
            // 台座は**正面が壁**（`isHittingPlatformFace`）なので、体の前端が左端に届く前に
            // 上面より高く上がっていないとぶつかる。上がるのに要る距離
            // （`riseTime(to:) × speed`）＋半身ぶん手前で踏み切る。
            let lift = RunnerRules.riseTime(to: platform.top) * speed
                + RunnerField.Metrics.playerHalfWidth + RunnerRules.tileWidth
            if field.isGrounded, field.distance >= platform.start - lift,
               field.distance < platform.start {
                field.jump()
            } else if !field.isGrounded, !usedSecondJump, field.vy <= 0 {
                usedSecondJump = field.jump()
            }
            _ = field.step(dt: 1.0 / 60)
            if field.isGrounded, platform.start <= field.distance, field.distance < platform.end {
                touchedDeck = true
            }
            if field.distance > platform.end { break }
        }
        #expect(usedSecondJump, "二段目を踏めていない（この検証が成り立っていない）")
        #expect(field.distance > platform.end, "跳び越せていない")
        #expect(!touchedDeck, "板に足が着いた")
        #expect(field.crumbleElapsed.isEmpty, "乗っていないのに崩れ始めた")
    }

    /// ゆっくりモードは `dt` そのものを縮めるので、崩れる速さも同じ割合で遅くなる。
    @Test("ゆっくりモードでは崩れる速さも同じ割合で遅くなる")
    func slowModeSlowsTheCollapse() {
        func clock(slow: Bool) -> Double {
            var (field, _) = Self.boarded(pattern: "-CCC-", speed: 20)
            for _ in 0..<20 {
                _ = field.step(dt: 1.0 / 60 * (slow ? RunnerRules.slowFactor : 1))
            }
            return field.crumbleElapsed[0] ?? 0
        }
        let normal = clock(slow: false), slow = clock(slow: true)
        #expect(normal > 0)
        #expect(
            abs(slow - normal * RunnerRules.slowFactor) < 1e-9,
            "ゆっくりモードの崩れ \(slow) が通常 \(normal) の \(RunnerRules.slowFactor) 倍になっていない"
        )
    }

    /// 一時停止・バックグラウンド復帰で崩れがずれない・二重に進まない。
    /// 止まっているあいだ `tick` が来ないので時計も止まり、復帰時の巨大な `dt` は
    /// `RunnerRules.maxStep` で頭打ちになる。
    @Test("一時停止とバックグラウンド復帰で崩れが二重に進まない")
    @MainActor
    func pauseAndBackgroundDoNotAdvanceTheCollapse() {
        let number = RunnerStage.all.firstIndex { !$0.crumblingPlatforms.isEmpty }.map { $0 + 1 }
        guard let number else { Issue.record("本編に崩れる足場が無い"); return }
        let model = RunnerModel(startingAt: number, preference: makePreference("crumble-pause"))
        model.press()
        model.release()
        var frames = 0
        while frames < 60 * 90, model.field.crumbleElapsed.isEmpty {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        guard let index = model.field.crumbleElapsed.keys.first else {
            Issue.record("自動操縦が足場に乗らなかった")
            return
        }
        for _ in 0..<6 { model.tick(dt: 1.0 / 60) }
        let beforePause = model.field.crumbleElapsed[index] ?? 0
        #expect(beforePause > 0)

        model.pause()
        for _ in 0..<120 { model.tick(dt: 1.0 / 60) }
        #expect(model.field.crumbleElapsed[index] == beforePause, "一時停止中に崩れが進んだ")

        model.resume()
        model.tick(dt: 30)
        #expect(
            (model.field.crumbleElapsed[index] ?? 0) <= beforePause + RunnerRules.maxStep + 1e-9,
            "復帰の 1 フレームで崩れが一気に進んだ"
        )
    }

    /// 同じ面をやり直すと足場は元に戻る（決裁の受け入れ条件）。走行ごとに `RunnerField` を
    /// 作り直すので、崩れの時計も空から始まる。
    @Test("同じ面をやり直すと足場が元に戻る")
    @MainActor
    func retryingTheStageRestoresTheDeck() {
        let stage = RunnerStage(number: 1, pattern: "-CCC-", speed: 20)
        var field = RunnerField(stage: stage)
        field.placeForTesting(distance: stage.platforms[0].start, altitude: RunnerRules.platformHeight, vy: 0)
        for _ in 0..<(60 * 5) where !field.hasCrumbled(0) { _ = field.step(dt: 1.0 / 60) }
        #expect(field.hasCrumbled(0), "この検証の前提（崩れ切っていない）")

        let number = RunnerStage.all.firstIndex { !$0.crumblingPlatforms.isEmpty }.map { $0 + 1 }
        guard let number else { Issue.record("本編に崩れる足場が無い"); return }
        let model = RunnerModel(startingAt: number, preference: makePreference("crumble-retry"))
        model.press()
        model.release()
        var frames = 0
        while frames < 60 * 90, model.field.crumbleElapsed.isEmpty {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(!model.field.crumbleElapsed.isEmpty, "自動操縦が足場に乗らなかった")
        // 足場に乗ったところで操作をやめる。次の障害でミスになり、やり直しが押せる状態になる。
        var stop = 0
        while stop < 60 * 90, model.phase != .failed {
            stop += 1
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.phase == .failed, "ミスまで進まなかった")
        model.retryStage()
        #expect(model.field.crumbleElapsed.isEmpty, "やり直しても崩れが残っている")
    }

    // MARK: - 置き方（決裁の「入れない組み合わせ」）

    /// 崩れる足場は 19 面以降にだけ置き、里山・港町の両方にある。
    @Test("崩れる足場は 19 面以降にだけ置かれていて、里山・港町の両方にある")
    func crumblingPlatformsOnlyAppearInTheNewWorlds() {
        for stage in RunnerStage.all.prefix(18) {
            #expect(stage.crumblingPlatforms.isEmpty, "ステージ \(stage.number) に崩れる足場がある")
        }
        for world in [RunnerWorld.satoyama, .harbor] {
            let count = RunnerStage.all
                .filter { RunnerWorld.world(forStage: $0.number) == world }
                .flatMap(\.crumblingPlatforms).count
            #expect(count > 0, "\(world) に崩れる足場が無い")
        }
    }

    /// 決裁の「入れない組み合わせ」。**鳥の手前に置かない・足場の上に鳥を置かない**
    /// （鳥の下は走ったまま抜けるしかないのに、足場が崩れると逃げ場が無い）。
    /// **崩れる足場の上に沈む床を置かない**（区画記号は 1 文字なので同じ区画には作れないが、
    /// 隣り合わせても水の上で踏み切り直すことになるので弾く）。
    ///
    /// 「手前」は**直後の 1 区画**と読む（沈む床の `sinkFloorsAvoidBirdsPlatformsAndShoots` と
    /// 同じ距離）。台座の規則で足場の前後は必ず素の平地なので、鳥が居られるのは 2 区画以上
    /// 先——そこまで来れば足場は背後にあり、地面を走ったまま鳥の下を抜けられる。
    /// 併せて**鳥の等価な静止区間（`RunnerHazard.encounter`）が板張りに重なっていない**ことも
    /// 座標で見る（記号の隣接だけだと、飛び立つ鳥が手前へ伸びる分を見落とす）。
    @Test("崩れる足場の隣に鳥・沈む床を置かない")
    func crumblingPlatformsAvoidBirdsAndSinkFloors() {
        var stages = RunnerStage.all
        #if DEBUG
        stages.append(.debugShowcase)
        #endif
        for stage in stages {
            let symbols = Array(stage.pattern)
            for (index, symbol) in symbols.enumerated()
            where symbol == RunnerStage.crumblingPlatformSymbol {
                for neighbor in [index - 1, index + 1] where symbols.indices.contains(neighbor) {
                    let s = symbols[neighbor]
                    #expect(s != "b", "ステージ \(stage.number): 区画 \(index) の足場の隣が鳥")
                    #expect(
                        s != RunnerStage.sinkFloorSymbol,
                        "ステージ \(stage.number): 区画 \(index) の足場の隣が沈む床"
                    )
                }
            }
            // 鳥の「関わる区間」が板張りに重なっていないこと（座標で見る）。
            for platform in stage.crumblingPlatforms {
                for bird in stage.hazards where bird.kind == .bird {
                    let range = bird.activeRange
                    #expect(
                        !(range.lowerBound < platform.end && platform.start < range.upperBound),
                        "ステージ \(stage.number): 鳥の区間が崩れる足場に重なっている"
                    )
                }
            }
            // 足場の範囲に沈む床が重なっていないこと（記号の並びではなく展開後の座標で見る）。
            for platform in stage.crumblingPlatforms {
                for floor in stage.sinkFloors {
                    #expect(
                        !(floor.start < platform.end && platform.start < floor.end),
                        "ステージ \(stage.number): 崩れる足場と沈む床が重なっている"
                    )
                }
            }
        }
    }

    /// エンドレス（#1086）には置かない（決裁「生成器に教えるのは別の版」）。
    @Test("エンドレスのコースには崩れる足場が出ない")
    func endlessCourseHasNoCrumblingPlatforms() {
        for seed in [UInt64(1), 675, 4_096, 99_991] {
            var field = RunnerField(endlessSeed: seed)
            for _ in 0..<(60 * 60) {
                if RunnerAutoPilot.shouldJump(field: field) { field.jump() }
                if RunnerAutoPilot.shouldRelease(field: field) { field.endHold() }
                _ = field.step(dt: 1.0 / 60)
                #expect(field.crumbleElapsed.isEmpty, "種 \(seed) のエンドレスで崩れが始まった")
                #expect(!field.isCrumbledGap(at: field.distance))
            }
        }
    }

    #if DEBUG
    /// QA 用ショーケース（`-simulateRunner crumble` の撮影）で、足場を単体で見られること。
    @Test("QA用ショーケースに 1 区画ぶんの崩れる足場がある")
    func showcaseHasOneCrumblingPlatform() {
        let platforms = RunnerStage.debugShowcase.crumblingPlatforms
        #expect(platforms.count == 1)
        #expect(platforms.first?.length == RunnerRules.crumbleDeckLength)
        #expect(
            platforms.first.map { $0.length < RunnerRules.crumbleMaxLength(at: RunnerStage.debugShowcase.speed) } == true
        )
    }
    #endif

    // MARK: - 自動操縦

    /// **自動操縦が実際に板へ足を乗せて渡り切る**こと（決裁「自動操縦がこの仕組みを扱え、
    /// 置いた面を最後まで走り切れる」）。跳び越えてしまうと仕組みを 1 度も通らないので、
    /// 「乗ったか」まで見る。
    @Test("自動操縦は崩れる足場に乗って渡り切り、置いた面をクリアする")
    @MainActor
    func autoPilotBoardsEveryCrumblingPlatformAndFinishes() {
        let numbers = RunnerStage.all.filter { !$0.crumblingPlatforms.isEmpty }.map(\.number)
        #expect(!numbers.isEmpty, "本編に崩れる足場が無い（この検証が空振りしている）")
        for number in numbers {
            let model = RunnerModel(startingAt: number, preference: makePreference("crumble-auto-\(number)"))
            let placed = model.field.stage.crumblingPlatforms.count
            #expect(autoPlayCurrentStage(model), "ステージ \(number) が打ち切りに達した")
            let expected: RunnerPhase = number == RunnerRules.stageCount ? .allCleared : .cleared
            #expect(model.phase == expected, "ステージ \(number) をクリアできない（\(model.phase)）")
            #expect(
                model.field.crumbleElapsed.count == placed,
                "ステージ \(number): 乗った足場が \(model.field.crumbleElapsed.count) 基（置いたのは \(placed) 基）"
            )
        }
    }
}
