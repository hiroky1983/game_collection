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
        // バナーは打席前と結果の 2 か所だけ。打席（と外野カメラ）は無バナー（受け入れ条件・#1348）。
        #expect(code.components(separatedBy: "BannerSlot(").count - 1 == 2, "打席前と結果にだけ出す")
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(!atBat.contains("BannerSlot("), "打席・外野は無バナー")
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
        #expect(!code.contains("#if DEBUG"), "ゲームの出し分けを DEBUG で分けない")
        #expect(!code.contains("Task.sleep(nanoseconds"))
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

    @Test("App の registry に登録されている（v1.1.8 で企画倉庫から出してハブに並べる）")
    func registryLineIsActive() throws {
        let source = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8
        )
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("HomerunModule(),"), "ハブに並べる（会長決裁 2026-09-29）")
        #expect(!lines.contains("// HomerunModule(),"), "コメントアウトの行が残っていない")
        #expect(lines.contains("import GameHomerun"))
        #expect(!source.contains("企画倉庫・#1348"), "企画倉庫の注記が残っていない")
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
        let homerLeft = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: -5, cursorDY: 22))
        let foul = HomerunJudge.judge(HomerunSwing(timingOffset: -100, cursorDX: -11, cursorDY: 22))
        let miss = HomerunJudge.judge(nil)
        let center = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 22))
        #expect(homerLeft.kind == .homer && homerLeft.direction < -7)
        #expect(foul.kind == .foul)
        #expect(HomerunText.place(homerLeft) == HomerunSector(direction: homerLeft.direction).label)
        #expect(HomerunText.place(foul) == "ファウル")
        #expect(HomerunText.place(miss) == "—")
        #expect(HomerunText.spraySummary([homerLeft, foul, miss, center, center])
                == "左 1 ／ 中 2 ／ 右 0 ／ ファウル 1 ／ 空振り 1")
        #expect(HomerunText.spoken(miss, number: 3) == "3球目、空振り")
        #expect(HomerunText.spoken(center, number: 1) == "1球目、柵越え、135メートル、センター、ジャスト")
    }

    @Test("スプレーチャートは本塁が原点で中堅が上。空振りは本塁、ファウルはラインの外")
    func spray() {
        let top = HomerunSprayGeometry.point(direction: 0, distance: HomerunSprayGeometry.maxMeters)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 1) < 1e-9)
        let left = HomerunSprayGeometry.point(direction: -45, distance: 100)
        #expect(left.x < 0 && left.y < 0)
        #expect(HomerunSprayGeometry.mark(for: HomerunJudge.judge(nil)) == .zero)
        let foul = HomerunJudge.judge(HomerunSwing(timingOffset: -100, cursorDX: -11, cursorDY: 22))
        let fp = HomerunSprayGeometry.mark(for: foul)
        #expect(fp.x < 0, "引っ張りのファウルは左側")
        #expect(abs(atan2(fp.x, -fp.y) * 180 / .pi) > 45, "ファウルラインの外")
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

    @Test("打席のカメラは既定で前。後ろに切り替えると保存され、次のモデルに引き継がれる")
    @MainActor func atBatCameraPreference() {
        let suite = "asobiba.homerun.camera.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let first = HomerunModel(defaults: defaults)
        #expect(first.atBatCamera == .front)
        first.atBatCamera = .back
        #expect(defaults.string(forKey: HomerunModel.atBatCameraKey) == "back")
        #expect(HomerunModel(defaults: defaults).atBatCamera == .back)
        first.atBatCamera = .front
        #expect(HomerunModel(defaults: defaults).atBatCamera == .front)
        // 知らない値（将来の案を消したときなど）は前に戻す。
        defaults.set("broadcastHigh", forKey: HomerunModel.atBatCameraKey)
        #expect(HomerunModel(defaults: defaults).atBatCamera == .front)
    }

    @Test("打席の「⋯」はカメラの前 / 後ろのチェック付き 2 択で、選んだ方にだけチェックが付く")
    @MainActor func atBatMenuHasCameraChoices() {
        let suite = "asobiba.homerun.menu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let model = HomerunModel(defaults: defaults)
        var items = HomerunAtBatView.menuItems(for: model)
        #expect(items.map(\.title) == ["カメラ: 前", "カメラ: 後ろ"])
        #expect(items.map(\.isChecked) == [true, false])
        items[1].action()
        #expect(model.atBatCamera == .back)
        items = HomerunAtBatView.menuItems(for: model)
        #expect(items.map(\.isChecked) == [false, true])
        items[0].action()
        #expect(model.atBatCamera == .front)
    }

    @Test("投球中にカメラを切り替えても、球・カーソル・進行は変わらない（見た目だけ）")
    @MainActor func switchingCameraMidPitchKeepsThePlay() {
        let suite = "asobiba.homerun.switch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let model = HomerunModel(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(model.start(now: now))
        model.press(at: CGPoint(x: 100, y: 100))
        model.drag(to: CGPoint(x: 120, y: 90))
        let before = (model.phase, model.step, model.cursor, model.ballPoint, model.pitchStart, model.pitchNumber, model.ledger)
        model.atBatCamera = .back
        #expect(model.phase == before.0 && model.step == before.1 && model.cursor == before.2)
        #expect(model.ballPoint == before.3 && model.pitchStart == before.4 && model.pitchNumber == before.5 && model.ledger == before.6)
        #expect(model.isHolding)
    }

    @Test("打席の画面は「⋯」を共通の部品（GameControlMenu）で出し、カメラはモデルの設定から読む")
    func atBatUsesSharedMenu() throws {
        let atBat = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(atBat.contains("GameControlMenu(items: Self.menuItems(for: model))"))
        #expect(atBat.contains("cameraPreset: model.atBatCamera"))
    }
}
