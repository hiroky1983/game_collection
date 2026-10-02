import Testing
import Foundation
import Core
import CoreEngine
import HomerunCore
@testable import GameHomerun
import GameKitTestSupport

@Suite("柵越えおじさんのモジュール")
@MainActor
struct HomerunModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        let module = HomerunModule()
        #expect(module.id == HomerunModel.gameID)
        #expect(module.title == "柵越えおじさん")
        #expect(!module.description.isEmpty)
        #expect(HowToPlayGuide.homerun.gameID == module.id)
        #expect(HowToPlayGuide.all.contains(.homerun))
        #expect(!module.resumesFromSnapshot, "1 挑戦は途中から戻せない")
    }

    @Test("打席前・結果のスクロール末尾にバナーとの間隔を確保する（#1749。誤タップ誘発の回避）")
    func scrollEndsKeepGapAboveBanner() throws {
        let view = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunView.swift"))
        let gap = ".padding(.bottom, HomerunBannerGap.belowContent)"
        let parts = view.components(separatedBy: gap)
        #expect(parts.count - 1 == 2, "打席前・結果の ScrollView に 1 つずつ")
        #expect(parts.dropLast().allSatisfy { $0.suffix(60).contains(".padding(Theme.pad)") }, "中身の余白の直後に足す")
        #expect(HomerunBannerGap.belowContent + Theme.pad > BannerSlot.height, "余白の合計はバナーの高さより大きい")
    }

    @Test("表示名・説明・ルールに他社の登録商標を思わせる語を含めない（README §4.1 の禁止語）")
    func noTrademarkedWords() {
        let module = HomerunModule()
        let texts = [module.title, module.description]
            + HowToPlayGuide.homerun.lines + [HowToPlayGuide.homerun.title, HowToPlayGuide.homerun.hint]
            + HomerunRuleSheet.rules.flatMap { [$0.0, $0.1] }
        for banned in ["ダービー", "Derby", "derby", "パワフル", "スラッガー", "公式", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠を 1 回だけ通り、バナーは打席前と結果だけで、時間は Model の締め切りを .task で待つだけ")
    func viewUsesSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameHomerun"))
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        // バナーは打席前・打席・結果の 3 か所（打席は #1696 で上部に足した。#1348 の無バナーは改めた）。
        #expect(code.components(separatedBy: "BannerSlot(").count - 1 == 3, "打席前・打席・結果に 1 つずつ")
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(atBat.components(separatedBy: "BannerSlot(").count - 1 == 1, "打席にも 1 つ置く（#1696）")
        // 打席のバナーは上端（HUD より先に積む）。押せる帯（下 1/3）の中には置かない。
        let banner = try #require(atBat.range(of: "BannerSlot(ads: ads)"))
        let hud = try #require(atBat.range(of: "topHUD\n"))
        #expect(banner.lowerBound < hud.lowerBound, "バナーは HUD の上")
        // バナーで下がった方向メーターより、輪・カーソル（ゾーン）を上の層に描く。結果のカードはゾーンより上の層。
        let zoneLayer = try #require(atBat.range(of: "HomerunZoneCanvas(\n"))
        let card = try #require(atBat.range(of: "HomerunBallResultCard(ball:"))
        #expect(hud.lowerBound < zoneLayer.lowerBound && zoneLayer.lowerBound < card.lowerBound,
                "HUD・メーター → ゾーン → 結果のカード の順に重ねる")
        let pad = try #require(atBat.range(of: "private func touchPad("))
        #expect(banner.lowerBound < pad.lowerBound && !atBat[pad.lowerBound...].contains("BannerSlot("),
                "押せる帯にバナーを重ねない")
        #expect(code.contains("HowToPlayHint(.homerun"))
        #expect(code.contains(".howToPlay(.homerun"))
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Timer.") && !code.contains("DispatchQueue"), "時間は Model の締め切りを .task で待つだけ")
        #expect(code.contains(".task(id: model.step)"))
        #expect(code.contains("model.step == step"), "番号が変わったら古い待ちは抜ける")
        #expect(code.contains("TimelineView("), "輪の大きさは時刻から描く")
        #expect(code.contains("accessibilityReduceMotion"), "Reduce Motion では輪を縮めず的の色で知らせる")
        #expect(code.contains(".onChange(of: scenePhase)") && code.contains("model.hold(.inactive"),
                "バックグラウンドでは投球を止める")
        #expect(code.contains("onPresent: { model.hold(.sheet, true"), "遊び方を読んでいるあいだは投球を止める")
        #expect(code.contains("hidesBackButton: model.phase == .pitching || model.phase == .ballResult"),
                "打席中は左上の戻るを出さない（#1550）")
        #expect(code.contains("hidesHowToPlay: model.phase == .pitching || model.phase == .ballResult"),
                "打席中は右上の「?」も出さない。一時停止の画面から開く（#1617）")
        #expect(!atBat.contains("GameControlMenu("), "打席の「⋯」は一時停止ボタンに置き換えた（#1550）")
        #expect(atBat.contains("model.pause(now:") && atBat.contains("model.quitChallenge()"),
                "一時停止ボタン・途中でやめる（確認つき）")
        #expect(atBat.contains(".confirmationDialog("), "途中でやめる前に確認を出す")
        #expect(atBat.contains("howToPlay.present()") && atBat.contains("\"遊び方\""),
                "一時停止の画面に遊び方ボタンを置き、ヘッダーと同じシートを開く（#1617）")
        #expect(atBat.contains("BoardGameControlMetrics.minTapTarget"),
                "一時停止ボタンの寸法は「⋯」（GameControlMenu）側の定数を参照する（コピーで別の数字を書かない・#1617）")
        #expect(!atBat.contains("pauseButtonSide"), "一時停止ボタン専用の寸法定数は持たない（#1617）")
        // 動作確認用の強制（`HomerunModel+Debug.swift`）だけは出荷ビルドから外すため #if DEBUG で囲む（v1.1.8・会長指示 2026-10-02）。
        let debugFile = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameHomerun/HomerunModel+Debug.swift")
        )
        #expect(!code.replacingOccurrences(of: debugFile, with: "").contains("#if DEBUG"), "ゲームの出し分けを DEBUG で分けない")
        #expect(!code.contains("Task.sleep(nanoseconds"))
    }

    @Test("押す・離すの時刻は Date() で渡し、ジェスチャーの value.time を Model に渡さない（#1594・会長 QA）")
    func gesturePassesWallClockToModel() throws {
        // value.time は起動からの経過を基準日に足した値で、Model の壁時計（pitchStart）と約 8 億秒ずれる。
        // 渡すと timingOffset が nil になり、離しても判定されず全球「見送り」になっていた。
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(!atBat.contains("value.time"), "ジェスチャーの時刻は Model の時計と基準が違う")
        #expect(atBat.contains("model.press(at: value.location, now: Date())"))
        #expect(atBat.contains("model.release(at: value.location, now: Date())"))
    }

    @Test("Model は時計を読まない（時刻はすべて引数で受ける）")
    func modelTakesTimeAsArgument() throws {
        let model = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunModel.swift"))
        // 既定引数の `now: Date = Date()`（初期化時の日付の読み込み）以外で現在時刻を読まない。
        let reads = SourceScan.matchCount(of: #"Date\(\)"#, in: model)
        #expect(reads == 1, "HomerunModel が Date() を \(reads) 回読んでいる（既定引数の 1 回だけのはず）")
        #expect(!model.contains("Task.sleep"))
        #expect(!model.contains("ContinuousClock"))
    }

    @Test("App の registry には企画倉庫としてコメントアウトで載っている（v1.1.8 では非公開・会長指示 2026-10-02）")
    func registryLineIsCommentedOut() throws {
        let source = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8
        )
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("// HomerunModule(),"))
        #expect(!lines.contains("HomerunModule(),"), "出荷を決める Issue まではハブに並べない")
        #expect(lines.contains("import GameHomerun"))
        #expect(source.contains("企画倉庫・#1348"))
        #expect(source.contains("v1.1.8 では非公開（会長指示 2026-10-02）"))
    }

    @Test("動作確認用の強制（回数無制限・月・ポール・空振りの演出）は出荷ビルドでは鍵が残っていても効かない")
    func debugOverridesAreIgnoredInReleaseBuild() throws {
        let defaults = UserDefaults(suiteName: "HomerunDebugOverrides.\(UUID())")!
        // 鍵（`debugUnlimitedKey` 等）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの宣言なので、
        // 参照するこのブロックも同じく #if DEBUG で囲む（出荷ビルドのテストが壊れないように・#1705）。
        #if DEBUG
        for key in [HomerunModel.debugUnlimitedKey, HomerunModel.debugForceMoonKey,
                    HomerunModel.debugForcePoleKey, HomerunModel.debugForceWhiffGagKey] {
            defaults.set(true, forKey: key)
        }
        // 出荷ビルドの経路（DEBUG でない）は鍵を読まない。
        #expect(HomerunDebugOverrides.current(defaults, isDebugBuild: false) == .none)
        // DEBUG ビルドの経路では鍵どおりに効く（会長 QA 用）。
        #expect(HomerunDebugOverrides.current(defaults, isDebugBuild: true)
                == HomerunDebugOverrides(unlimited: true, forcesMoon: true, forcesPole: true, forcesWhiffGag: true))
        // テストは DEBUG でビルドされる（`swift test` の既定）ので、既定引数は DEBUG の経路。
        #expect(HomerunDebugOverrides.isDebugBuild)
        #else
        // 出荷ビルドでは鍵自体が存在しない（宣言も #if DEBUG の中）。経路は常に .none・isDebugBuild も false。
        #expect(HomerunDebugOverrides.current(defaults) == .none)
        #expect(!HomerunDebugOverrides.isDebugBuild)
        #endif
    }

    @Test("動作確認用の鍵の宣言と読み取りは HomerunModel+Debug.swift の #if DEBUG の中だけにある")
    func debugKeysAreReadOnlyInsideDebugFile() throws {
        let debugFile = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameHomerun/HomerunModel+Debug.swift")
        )
        let rest = SourceScan.strippingComments(try SourceScan.moduleSources("GameHomerun"))
            .replacingOccurrences(of: debugFile, with: "")
        for key in ["debugUnlimitedKey", "debugForceMoonKey", "debugForcePoleKey", "debugForceWhiffGagKey",
                    "homerun_debug"] {
            #expect(!rest.contains(key), "\(key) を Debug ファイルの外で読んでいる（出荷ビルドで効いてしまう）")
        }
        // 宣言（extension）と読み取り（current の中）は両方 #if DEBUG の内側。
        let extensionStart = try #require(debugFile.range(of: "extension HomerunModel"))
        #expect(debugFile[..<extensionStart.lowerBound].hasSuffix("#if DEBUG\n"))
        let reads = SourceScan.functionSource(startingWith: "static func current(", in: debugFile)
        let guardIndex = try #require(reads.range(of: "#if DEBUG"))
        let readIndex = try #require(reads.range(of: "defaults.bool(forKey:"))
        #expect(guardIndex.lowerBound < readIndex.lowerBound)
    }
}

@Suite("柵越えおじさんの打席の寸法と文言")
struct HomerunGeometryTests {
    @Test("ゾーンは帯の幅の 4 倍（88pt）で、9 分割のボールの位置は行優先")
    func zone() {
        #expect(HomerunZoneGeometry.zoneSize == 88)
        let c = HomerunZoneGeometry.cellSize
        #expect(HomerunZoneGeometry.ballPoint(zone: 4) == .zero)
        #expect(HomerunZoneGeometry.ballPoint(zone: 0) == CGPoint(x: -c, y: -c))
        #expect(HomerunZoneGeometry.ballPoint(zone: 2) == CGPoint(x: c, y: -c))
        #expect(HomerunZoneGeometry.ballPoint(zone: 6) == CGPoint(x: -c, y: c))
        #expect(HomerunZoneGeometry.ballPoint(zone: 8) == CGPoint(x: c, y: c))
    }

    @Test("縮む輪は 118 → 46pt を 1.2 秒で線形に縮み、半径は 0.03pt/ms（±100ms で半径差 3pt）")
    func ring() {
        #expect(HomerunZoneGeometry.ringDiameter(elapsed: 0) == 118)
        #expect(abs(HomerunZoneGeometry.ringDiameter(elapsed: 1.2) - 46) < 1e-9)
        #expect(abs(HomerunZoneGeometry.ringDiameter(elapsed: 0.6) - 82) < 1e-9)
        let before = (HomerunZoneGeometry.ringDiameter(elapsed: 1.1) - 46) / 2
        let after = (46 - HomerunZoneGeometry.ringDiameter(elapsed: 1.3)) / 2
        #expect(abs(before - 3) < 1e-9)
        #expect(abs(after - 3) < 1e-9, "的に重なった後も同じ速さで縮む")
        #expect(HomerunZoneGeometry.ringDiameter(elapsed: -0.5) == 118, "モーション中は縮まない")
        #expect(HomerunZoneGeometry.targetLineWidth < HomerunZoneGeometry.ringLineWidth, "的は細く・動く輪は太く")
    }

    @Test("Reduce Motion の的の色: 当たり窓の中はコーラル、手前 300ms は黄、それより前と後は白")
    func targetCue() {
        #expect(HomerunTargetCue(offsetMilliseconds: 0) == .now)
        #expect(HomerunTargetCue(offsetMilliseconds: -110) == .now)
        #expect(HomerunTargetCue(offsetMilliseconds: 110) == .now)
        #expect(HomerunTargetCue(offsetMilliseconds: -111) == .near)
        #expect(HomerunTargetCue(offsetMilliseconds: -410) == .near)
        #expect(HomerunTargetCue(offsetMilliseconds: -411) == .far)
        #expect(HomerunTargetCue(offsetMilliseconds: 111) == .far)
        #expect(HomerunTargetCue(offsetMilliseconds: -.infinity) == .far)
    }

    @Test("判定の語は 5 つ（ミリ秒・角度は見せない）")
    func words() {
        #expect(HomerunText.timing(.just) == "ジャスト")
        #expect(HomerunText.timing(.nice) == "ナイス")
        #expect(HomerunText.timing(.hit) == "当たり")
        #expect(HomerunText.kind(.foul) == "ファウル")
        #expect(HomerunText.kind(.miss) == "空振り")
        #expect(HomerunText.meters(134.6) == "135 m")
    }

    @Test("内訳の呼び名と結果の一言")
    func summary() {
        let homerLeft = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: -5, cursorDY: 4))
        let foul = HomerunJudge.judge(HomerunSwing(timingOffset: -100, cursorDX: -11, cursorDY: 9))
        let miss = HomerunJudge.judge(nil)
        let center = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 4))
        #expect(homerLeft.kind == .homer && homerLeft.direction < -7)
        #expect(foul.kind == .foul)
        // 左中間の 164m はスタンドの後端（約 145m）を越えるので「場外」（#1654）。スタンドに落ちる柵越えは方向の呼び名。
        #expect(homerLeft.isOutOfPark && HomerunText.place(homerLeft) == "場外")
        var inStands = homerLeft
        inStands.distance = 125
        #expect(HomerunText.place(inStands) == HomerunSector(direction: homerLeft.direction).label)
        #expect(HomerunText.place(foul) == "ファウル")
        #expect(HomerunText.place(miss) == "—")
        #expect(HomerunText.spraySummary([homerLeft, foul, miss, center, center])
                == "左 1 ／ 中 2 ／ 右 0 ／ ファウル 1 ／ 空振り 1")
        #expect(HomerunText.spoken(miss, number: 3) == "3球目、空振り")
        #expect(HomerunText.spoken(center, number: 1) == "1球目、場外、180メートル、センター、ジャスト")
    }

    @Test("スプレーチャートは本塁が原点で中堅が上。空振りは本塁、ファウルはラインの外")
    func spray() {
        let top = HomerunSprayGeometry.point(direction: 0, distance: HomerunSprayGeometry.maxMeters)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 1) < 1e-9)
        let left = HomerunSprayGeometry.point(direction: -45, distance: 100)
        #expect(left.x < 0 && left.y < 0)
        #expect(HomerunSprayGeometry.mark(for: HomerunJudge.judge(nil)) == .zero)
        let foul = HomerunJudge.judge(HomerunSwing(timingOffset: -100, cursorDX: -11, cursorDY: 9))
        let fp = HomerunSprayGeometry.mark(for: foul)
        #expect(fp.x < 0, "引っ張りのファウルは左側")
        #expect(abs(atan2(fp.x, -fp.y) * 180 / .pi) > 45, "ファウルラインの外")
    }

    @Test("スプレーチャートは最大飛距離（180m）まで枠の内側に描く。場外の線は柵の外・180m の内側（#1676）",
          arguments: [CGSize(width: 180, height: 130),   // 1 球の結果の小さな扇
                      CGSize(width: 287, height: 213),   // SE の結果カード（375 - 余白）
                      CGSize(width: 382, height: 283)])  // Pro Max の結果カード
    func sprayFitsMaxDistance(size: CGSize) {
        #expect(HomerunSprayGeometry.maxMeters >= HomerunJudge.bestDistance)
        for inset in [CGFloat(10), 16] {
            let layout = HomerunSprayGeometry.layout(in: size, inset: inset)
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: inset - 0.001, dy: inset - 0.001)
            for deg in stride(from: -45.0, through: 45.0, by: 1) {
                let far = layout.map(HomerunSprayGeometry.point(direction: deg, distance: HomerunJudge.bestDistance))
                #expect(frame.contains(far), "\(deg)° の 180m が余白の内側（\(size)・\(far)）")
                let fence = HomerunJudge.fence(atDirection: deg)
                let out = HomerunBallChase.outOfParkDistance(atDirection: deg)
                #expect(fence < out && out < HomerunJudge.bestDistance)
            }
            // 180m より遠い当たりも縁で止まる（外に出ない）。
            let beyond = layout.map(HomerunSprayGeometry.point(direction: 0, distance: 250))
            #expect(frame.contains(beyond))
            // 柵（中堅 122m）は扇の半分より外: 柵の中が小さくなりすぎない。
            #expect(HomerunJudge.fence(atDirection: 0) / HomerunSprayGeometry.maxMeters > 0.6)
        }
        // 以前の切れ方（中堅 150m 以上が扇の外）の再現: 場外の★が上端に収まる。
        var homer = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 0))
        homer.kind = .homer
        homer.distance = 172
        let layout = HomerunSprayGeometry.layout(in: CGSize(width: 287, height: 213), inset: 16)
        #expect(layout.map(HomerunSprayGeometry.mark(for: homer)).y >= 16)
    }

    @Test("番号の札は同じ所に落ちた球どうしでも重ならない（#1676）")
    func sprayLabelsDoNotOverlap() {
        let same = CGPoint(x: 140, y: 40)
        let marks = [same, same, CGPoint(x: 144, y: 42), CGPoint(x: 80, y: 120)]
        let labels = HomerunSprayGeometry.labelCenters(for: marks, in: CGRect(x: 0, y: 0, width: 287, height: 213))
        let size = HomerunSprayGeometry.labelSize
        for i in labels.indices {
            for j in labels.indices where j > i {
                let a = CGRect(x: labels[i].x - size.width / 2, y: labels[i].y - size.height / 2, width: size.width, height: size.height)
                let b = CGRect(x: labels[j].x - size.width / 2, y: labels[j].y - size.height / 2, width: size.width, height: size.height)
                #expect(!a.intersects(b), "札 \(i + 1) と \(j + 1)")
            }
        }
        #expect(labels[3] == CGPoint(x: 90, y: 111), "離れた球は今まで通り右上")
    }

    @Test("空振りが 2 球でも番号の札は描く枠の内側に収まる（#1676）")
    func sprayLabelsStayInsideFrame() {
        let frame = CGRect(x: 0, y: 0, width: 287, height: 213)
        let layout = HomerunSprayGeometry.layout(in: frame.size, inset: 16)
        let miss = CGPoint(x: layout.home.x, y: layout.home.y - 8)
        let labels = HomerunSprayGeometry.labelCenters(for: [miss, miss], in: frame)
        let size = HomerunSprayGeometry.labelSize
        for (i, c) in labels.enumerated() {
            let rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
            #expect(frame.contains(rect), "札 \(i + 1)")
        }
        // 枠を十分広く取ると、2 枚目が下にはみ出す（テストが効いている対照）。
        let loose = HomerunSprayGeometry.labelCenters(for: [miss, miss], in: CGRect(x: -500, y: -500, width: 2000, height: 2000))
        #expect(loose[1].y + size.height / 2 > frame.maxY)
    }

    @Test("合計飛距離（m）は順位表 homerunDistance へ送る")
    @MainActor func leaderboardMapping() {
        let mapped = GameCenterLeaderboard.score(
            gameID: HomerunModel.gameID, outcome: .loss, score: GameScore(metric: .points, points: 812)
        )
        #expect(mapped == GameCenterScore(leaderboardID: GameCenterLeaderboard.homerunDistance, value: 812))
        #expect(GameCenterLeaderboard.allIDs.contains(GameCenterLeaderboard.homerunDistance))
    }

    @Test("方向メーターは既定でオン。切り替えは保存され、次のモデルに引き継がれる")
    @MainActor func directionMeterPreference() {
        let suite = "asobiba.homerun.meter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let pref = FeedbackPreference(key: "homerunDirectionMeter_v1", defaults: defaults)
        let first = HomerunModel(defaults: defaults, directionMeter: pref)
        #expect(first.showsDirectionMeter)
        first.showsDirectionMeter = false
        #expect(!pref.isEnabled)
        let second = HomerunModel(defaults: defaults, directionMeter: pref)
        #expect(!second.showsDirectionMeter)
        first.showsDirectionMeter = true
        let third = HomerunModel(defaults: defaults, directionMeter: pref)
        #expect(third.showsDirectionMeter)
    }

    @Test("方向メーターの表示は設定に従い、消しても判定（previewSwing）の呼び出しは別経路")
    func atBatGatesMeterOnSetting() throws {
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(atBat.contains("model.showsDirectionMeter"))
    }

    // #1770 会長決裁（2026-10-02）: 後ろのカメラを廃止して前のカメラだけにする。後ろを保存していた人も前で始まる。
    @Test("打席のカメラは 1 つだけ: 旧設定（homerun_atBatCamera_v1 = back）はどこからも読まず、一時停止の画面にカメラの切り替えは無い")
    func atBatCameraIsFixedToFront() throws {
        for path in ["Sources/GameHomerun/HomerunModel.swift", "Sources/GameHomerun/HomerunAtBatView.swift",
                     "Sources/GameHomerun/HomerunView.swift", "Sources/GameHomerun/Toon3D/HomerunAtBatScene3D.swift"] {
            let source = SourceScan.strippingComments(try SourceScan.packageSource(path))
            #expect(!source.contains("homerun_atBatCamera_v1"), "\(path) が旧設定のキーを参照している")
            #expect(!source.contains("atBatCamera"), "\(path) にカメラの設定が残っている")
            #expect(!source.contains("CameraPreset"), "\(path) にカメラの選択肢が残っている")
        }
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(!atBat.contains("カメラ:"), "一時停止の画面にカメラの切り替えが残っている")
        // 3D の球の通り道と 3D の描画は、どちらも打席のカメラ（`HomerunAtBatLayout.camera`）から決める。
        #expect(atBat.contains("plan.ballPosition(at: shown, camera: HomerunAtBatLayout.camera,"))
        let scene = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/Toon3D/HomerunAtBatScene3D.swift"))
        #expect(scene.contains("camera: cameraOverride ?? HomerunAtBatLayout.camera,"))
        #expect(scene.contains("HomerunAtBatSceneView.prepared(camera: HomerunAtBatLayout.camera,"))
    }
}

// #1770 会長決裁（2026-10-02）: 方向メーターは右上（打者の頭・バットに重なる）から左上へ。HUD・バナー・ゾーン・的・輪・カーソル・
// 一時停止ボタンと重ならないこと（SE で特に）。座標は打席の画面の安全域の内側（`HomerunAtBatView` の `GeometryReader`）。
@Suite("柵越えおじさんの打席の方向メーターの置き場所")
@MainActor
struct HomerunDirectionMeterPlacementTests {
    typealias Layout = HomerunAtBatHUDLayout
    typealias Zone = HomerunZoneGeometry

    /// 画面の大きさ（pt）と安全域の上・下。上はステータスバー + ナビゲーションバー（44pt・打席中もタイトルを出す）。
    struct Screen: CustomTestStringConvertible, Sendable {
        let name: String
        let size: CGSize
        let top: CGFloat
        let bottom: CGFloat
        var testDescription: String { name }
        /// 安全域の内側の高さ。
        var height: CGFloat { size.height - top - bottom }
        /// ゾーンの中心（`HomerunAtBatView.body` と同じ式: 全画面の高さの `zoneScreenFraction` を安全域の内側の座標へ）。
        var zoneCenter: CGPoint { CGPoint(x: size.width / 2, y: size.height * HomerunAtBatLayout.zoneScreenFraction - top) }
    }

    nonisolated static let screens = [
        Screen(name: "iPhone SE", size: CGSize(width: 375, height: 667), top: 20 + 44, bottom: 0),
        Screen(name: "iPhone 17", size: CGSize(width: 402, height: 874), top: 62 + 44, bottom: 34),
        Screen(name: "iPhone 17 Pro Max", size: CGSize(width: 440, height: 956), top: 62 + 44, bottom: 34),
    ]

    /// 円（中心・半径）と長方形が重なるか。
    static func overlaps(_ rect: CGRect, circle center: CGPoint, radius: CGFloat) -> Bool {
        let nx = min(max(center.x, rect.minX), rect.maxX), ny = min(max(center.y, rect.minY), rect.maxY)
        return hypot(center.x - nx, center.y - ny) < radius
    }

    /// カーソル（中心がゾーンの中心から ±`reach` の正方形の中を動く）の描画（外の輪 = 当たり判定の半径 + 線の半分、
    /// 十字の目盛り = 半径 + 4pt + 線の半分）が長方形に掛かりうるか。
    static func cursorCanOverlap(_ rect: CGRect, zoneCenter c: CGPoint, reach: CGFloat) -> Bool {
        let ring = HomerunJudge.contactRadius + 1.5, tick = HomerunJudge.contactRadius + 4 + 1
        let square = CGRect(x: c.x - reach, y: c.y - reach, width: reach * 2, height: reach * 2)
        // 輪の通り道 = 正方形を半径 `ring` で角を丸めて膨らませた形。目盛りの通り道 = 正方形を縦・横に伸ばした帯。
        let ringHit = overlapsRounded(rect, square: square, radius: ring)
        let tickHit = square.insetBy(dx: -tick, dy: -1).intersects(rect) || square.insetBy(dx: -1, dy: -tick).intersects(rect)
        return ringHit || tickHit
    }

    /// 正方形を半径 `radius` で角を丸めて膨らませた形（= 正方形の中を動く円の通り道）が長方形に掛かるか。
    static func overlapsRounded(_ rect: CGRect, square: CGRect, radius: CGFloat) -> Bool {
        // 2 つの長方形の間の距離（重なれば 0）が半径より小さいか。
        let dx = max(square.minX - rect.maxX, rect.minX - square.maxX, 0)
        let dy = max(square.minY - rect.maxY, rect.minY - square.maxY, 0)
        return hypot(dx, dy) < radius
    }

    /// ゾーン（線の半分まで）・9 マスの的と縮み始めの輪（線の半分まで）が長方形に掛かるか。
    static func zoneAndRingsOverlap(_ rect: CGRect, zoneCenter c: CGPoint) -> Bool {
        let half = Zone.zoneSize / 2 + 0.75
        if CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2).intersects(rect) { return true }
        let ring = Zone.ringStartDiameter / 2 + Zone.ringLineWidth / 2
        return (0..<9).contains { zone in
            let b = Zone.ballPoint(zone: zone)
            return overlaps(rect, circle: CGPoint(x: c.x + b.x, y: c.y + b.y), radius: ring)
        }
    }

    @Test("方向メーターは左上・HUD の下に置き、ゾーン・9 マスの的と縮み始めの輪・ゾーンの中のカーソルに重ならない", arguments: screens)
    func meterClearsThePlayArea(screen: Screen) {
        let meter = Layout.meterFrame
        #expect(meter.minX == Theme.pad && meter.maxX < screen.size.width / 2, "左寄せ \(meter)")
        // 上端のバナーと HUD の段の下。
        #expect(meter.minY >= BannerSlot.height + Layout.spacing + Layout.hudHeight + Layout.spacing)
        #expect(!Self.zoneAndRingsOverlap(meter, zoneCenter: screen.zoneCenter), "\(screen.name): メーター \(meter)・ゾーンの中心 \(screen.zoneCenter)")
        #expect(!Self.cursorCanOverlap(meter, zoneCenter: screen.zoneCenter, reach: Zone.zoneSize / 2),
                "\(screen.name): ゾーンの中のカーソルがメーターに掛かる")
        // 一時停止ボタン（押せる帯のすぐ上の右端）と押せる帯（下 1/3）より上。
        let padTop = screen.height * 2 / 3
        #expect(meter.maxY < padTop - 8 - BoardGameControlMetrics.minTapTarget, "\(screen.name): 押せる帯・一時停止ボタンに近い")
    }

    @Test("iPhone 17・Pro Max ではカーソルを端（ゾーンの外 1.5 帯）まで寄せてもメーターに掛からない。SE は外の左上の隅だけ掛かりうる（カーソルが上の層）")
    func cursorReachVersusMeter() {
        let meter = Layout.meterFrame
        for screen in Self.screens {
            let canOverlap = Self.cursorCanOverlap(meter, zoneCenter: screen.zoneCenter, reach: Zone.cursorLimit)
            #expect(canOverlap == (screen.name == "iPhone SE"), "\(screen.name): \(canOverlap)")
        }
        // SE で掛かるのは、カーソルをゾーンの外へ 12pt を超えてはみ出させたとき（左上の外の隅）だけ。
        let se = Self.screens[0]
        #expect(!Self.cursorCanOverlap(meter, zoneCenter: se.zoneCenter, reach: Zone.zoneSize / 2 + 12))
    }

    @Test("上端の HUD の段（球数・今回・柵越え）もゾーン・輪・カーソルの届く所に掛からない", arguments: screens)
    func hudClearsThePlayArea(screen: Screen) {
        let hud = CGRect(x: Theme.pad, y: BannerSlot.height + Layout.spacing,
                         width: screen.size.width - Theme.pad * 2, height: Layout.hudHeight)
        #expect(!Self.zoneAndRingsOverlap(hud, zoneCenter: screen.zoneCenter), "\(screen.name)")
        #expect(!Self.cursorCanOverlap(hud, zoneCenter: screen.zoneCenter, reach: Zone.cursorLimit), "\(screen.name)")
        // メーターは HUD の段の下（重ならない）。
        #expect(!hud.intersects(Layout.meterFrame))
    }

    @Test("打席の画面は HUD の段の高さを揃え、方向メーターを HUD の下の左端に固定の大きさで置く")
    func atBatViewUsesTheLayout() throws {
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(atBat.contains(".frame(minHeight: HomerunAtBatHUDLayout.hudHeight)"))
        #expect(atBat.contains("VStack(alignment: .leading, spacing: HomerunAtBatHUDLayout.spacing)"))
        #expect(atBat.contains(".frame(width: HomerunAtBatHUDLayout.meterSize.width, height: HomerunAtBatHUDLayout.meterSize.height)"))
        // 右寄せの Spacer を前に置かない（以前は右上）。
        #expect(!atBat.contains("Spacer()\n                                if model.phase == .pitching, model.showsDirectionMeter"))
    }
}
