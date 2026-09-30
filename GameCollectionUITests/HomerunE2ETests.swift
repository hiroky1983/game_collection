import ObjectiveC
import XCTest

/// 柵越えおじさん（#1594）の画面操作の E2E。シミュレータ上で実際に押せる帯を押し、照準をボールのマスへずらし、
/// 輪が的に重なる時刻の前後で離して、**見送り以外（当たり・空振り＋理由）で判定されること**と、当たりが実際に出ることを確かめる。
///
/// Model のテストだけでは、画面の DragGesture が渡す時刻が Model の時計とずれて全球「見送り」になる不具合
/// （PR #1609）を見落とした。ここは画面の入力から判定までを通しで見る。CI では回さない（シミュレータで手元実行）。
///
/// 実行例（UDID で端末を指定する）:
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/HomerunE2ETests
/// ```
/// 環境変数（`TEST_RUNNER_` を付けて xcodebuild に渡す）:
/// - `E2E_SHOT_DIR`: 結果のスクリーンショットを書き出すフォルダ（無ければ添付だけ）
/// - `E2E_LATENCY`: 投球の開始を読んでから離すまでの遅れの補正（秒・既定 `defaultLatency`）
/// - `E2E_SHIFT`: 全球の離す時刻のずれ（秒・`plan` の代わり）。負にすると全球で振る（Mac が重く離すのが遅れるときの確認用）
/// - `E2E_CAMERA`: 打席のカメラ（`front` / `back`・既定 `front`）
@MainActor
final class HomerunE2ETests: XCTestCase {
    /// 的が出るまで（投手のモーション・`HomerunModel.windup`）。
    static let windup: TimeInterval = 0.8
    /// 的が出てから輪が的に重なるまで（`HomerunPitch.travelMilliseconds`）。
    static let travel: TimeInterval = 1.2
    /// ゾーンの 1 マス（pt・`HomerunZoneGeometry.cellSize`）。
    static let cell: CGFloat = 88.0 / 3
    /// 投球の始まりを読む遅れ（約 0.2 秒）と、合成した指の動きがアプリに届く遅れ（約 0.2 秒）の見込み（秒・iPhone 17 Pro の
    /// シミュレータで判定の時刻をログに出して実測した値）。
    static let defaultLatency: TimeInterval = 0.4
    /// 押してからずらし始めるまで・ずらす速さ（pt/秒）。
    static let pressLead: TimeInterval = 0.1
    static let dragSpeed: CGFloat = 400

    /// 1 挑戦 10 球の離す時刻のずれ（秒・輪が的に重なる瞬間から。負が早い）と、照準をボールからどれだけ下へずらすか（pt）。
    /// 早い・ジャスト狙い・遅いに振り分ける。下へずらすのは柵越えの帯（フライ）を狙う球: 照準の吸い寄せ（押して 1 秒で
    /// ボールとの距離の半分）で半分戻るので、44pt ずらすと離す瞬間はボールの 22pt 下（フライの帯の中心）になる。
    static let plan: [(shift: TimeInterval, low: CGFloat)] = [
        (0, 44), (-0.06, 0), (0.06, 44), (0, 44), (-0.25, 0), (0, 44), (0.22, 0), (-0.03, 44), (0.03, 0), (0, 44),
    ]

    func testSwingEveryPitchIsJudged() throws {
        let env = ProcessInfo.processInfo.environment
        let latency = env["E2E_LATENCY"].flatMap(Double.init) ?? Self.defaultLatency
        let shotDir = env["E2E_SHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let shotDir { try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true) }

        Self.skipQuiescenceWait()
        let app = XCUIApplication()
        // カメラは起動引数で固定する（保存された設定に左右されない。後ろは描画が重く、離す時刻の補正が変わる）。
        app.launchArguments = ["-startGame", "homerun", "-homerunUnlimited", "-screenshotMode",
                               "-homerun_atBatCamera_v1", env["E2E_CAMERA"] ?? "front"]
        app.launch()

        let start = app.buttons["打席に立つ"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "打席に立つ が出ない")
        start.tap()

        let results = playChallenge(app: app, latency: latency, shotDir: shotDir, prefix: "pitch")

        let summary = results.joined(separator: "\n")
        print("E2E-SUMMARY\n\(summary)")
        if let shotDir { try? summary.write(to: shotDir.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8) }
        let hits = results.filter { $0.contains("柵越え") || $0.contains("当たり、") || $0.contains("直撃") }
        XCTAssertFalse(hits.isEmpty, "当たりが 1 本も出ない:\n\(summary)")

        // 最後の結果（10 球の結果）の画面も残す。
        sleep(3)
        let final = XCUIScreen.main.screenshot()
        if let shotDir { try? final.pngRepresentation.write(to: shotDir.appendingPathComponent("final.png")) }

        // もう一回（会長 QA 2026-09-30）: 前の挑戦の振り終わりの姿勢・ミット直前の球が残り、1 球目が何もしないうちに
        // 終わっていた。始めた直後を細かく撮り、1 球目を打って見送り以外で判定されることを確かめる。
        let again = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'もう一回'")).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10), "もう一回 が出ない")
        again.tap()
        let tapped = Date()
        let restartCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES '^1球目、.*'")).firstMatch
        for k in 0..<8 {
            let shot = XCUIScreen.main.screenshot()
            if let shotDir {
                try? shot.pngRepresentation.write(to: shotDir.appendingPathComponent(String(format: "restart-t%02d.png", k)))
            }
            // 1 球目は投手のモーション（0.8 秒）+ 輪が縮む 1.2 秒より前には終わらない（前の挑戦の続きで即座に終わっていない）。
            // 10 球の結果の「1 球ずつ」のマスも同じ読み上げなので、結果の画面が消えてから見る。
            if !again.exists {
                XCTAssertFalse(restartCard.exists, "もう一回の直後に 1 球目の結果が出た（\(k)）")
            }
            Thread.sleep(until: tapped.addingTimeInterval(Double(k + 1) * 0.25))
        }
        let again1 = playChallenge(app: app, latency: latency, shotDir: shotDir, prefix: "restart", count: 1)
        print("E2E-RESTART\n\(again1.joined(separator: "\n"))")
        if let shotDir { try? again1.joined(separator: "\n").write(to: shotDir.appendingPathComponent("restart.txt"), atomically: true, encoding: .utf8) }
        XCTAssertEqual(again1.count, 1, "もう一回の 1 球目が判定されない")
    }

    /// 1 挑戦ぶん（`plan` の球数）を打つ。各球の結果の行を返す。`count` を渡すとその球数で止める。
    func playChallenge(app: XCUIApplication, latency: TimeInterval, shotDir: URL?, prefix: String,
                       count: Int = HomerunE2ETests.plan.count) -> [String] {
        let zone = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'ストライクゾーン。ボールは'")).firstMatch
        let pad = app.descendants(matching: .any)["打つ場所"]
        XCTAssertNotNil(Self.poll(timeout: 10, { pad.exists }), "押せる帯が無い")
        let cardQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES '^[0-9]+球目、.*'"))

        var results: [String] = []
        for (index, pitch) in Self.plan.prefix(count).enumerated() {
            let shift = ProcessInfo.processInfo.environment["E2E_SHIFT"].flatMap(Double.init) ?? pitch.shift
            let number = index + 1
            // `waitForExistence` は約 1 秒おきにしか見ないので、投球の始まり（0.8 秒のモーション）を読み逃す。細かく見る。
            guard let seen = Self.poll(timeout: 10, { zone.exists }) else {
                XCTFail("\(number) 球目の投球が始まらない"); break
            }
            let label = zone.label
            let (dx, dy) = Self.ballOffset(label: label)

            // 押す位置は帯の真ん中。そこからボールのマスへずらす（指 1pt = 照準 1pt）。
            let from = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = from.withOffset(CGVector(dx: dx, dy: dy + pitch.low))
            let dragTime = TimeInterval(hypot(dx, dy + pitch.low) / Self.dragSpeed)
            // 投球の開始（ゾーンにボールが出た = 投手のモーションの始まり）から輪が重なる瞬間 + ずれに離す。
            let releaseAt = seen.addingTimeInterval(Self.windup + Self.travel + shift - latency)
            let hold = max(releaseAt.timeIntervalSinceNow - Self.pressLead - dragTime, 0.05)
            from.press(forDuration: Self.pressLead, thenDragTo: to,
                       withVelocity: XCUIGestureVelocity(rawValue: Self.dragSpeed), thenHoldForDuration: hold)

            let card = cardQuery.firstMatch
            guard Self.poll(timeout: 6, { card.exists }) != nil else {
                XCTFail("\(number) 球目の結果のカードが出ない"); break
            }
            let result = card.label
            results.append("\(number)球目 ずれ\(Int(shift * 1000))ms 下へ\(Int(pitch.low))pt [\(label)] → \(result)")
            // カードは縮小から出てくるので、出きってから撮る。
            Thread.sleep(forTimeInterval: 0.3)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(prefix)-\(number)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let shotDir {
                try? shot.pngRepresentation.write(to: shotDir.appendingPathComponent(String(format: "%@-%02d.png", prefix, number)))
            }
            // 見送りではなく、振った判定（当たり・ファウル・空振り＋理由）になっていること。
            XCTAssertFalse(result.hasSuffix("見送り"), "\(number) 球目が見送り扱い: \(result)")
            if result.contains("空振り") {
                XCTAssertTrue(result.contains("振るのが早い") || result.contains("振るのが遅い") || result.contains("照準がずれた"),
                              "\(number) 球目の空振りに理由が無い: \(result)")
            }
            // 結果のカードが消えてから次の球へ。
            if number < count {
                XCTAssertNotNil(Self.poll(timeout: 6, { !card.exists }), "\(number) 球目の結果のカードが消えない")
            }
        }

        return results
    }

    /// XCUITest は操作の前に「アプリが落ち着く（アニメーションが止まる）まで」待つが、打席は投球中ずっと 3D と輪を
    /// 動かしているので、その待ちが 0.05〜0.8 秒ばらつき、離す時刻が当たり窓（±110ms）に収まらない。この E2E だけ
    /// 待ちを外す（XCTest の非公開メソッドの差し替え。見つからなければ何もしない = 待つだけで壊れはしない）。
    static func skipQuiescenceWait() {
        guard let cls = NSClassFromString("XCUIApplicationProcess") else { return }
        let one: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let two: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
        let targets: [(String, AnyObject)] = [
            ("waitForQuiescenceIncludingAnimationsIdle:", one as AnyObject),
            ("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", two as AnyObject),
        ]
        for (name, block) in targets {
            if let method = class_getInstanceMethod(cls, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
        }
    }

    /// 条件が成り立つまで細かく見て、成り立った時刻を返す（時間切れは nil）。
    static func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Date? {
        let limit = Date().addingTimeInterval(timeout)
        while Date() < limit {
            if condition() { return Date() }
        }
        return nil
    }

    /// 「ストライクゾーン。ボールは高めの左」→ ゾーン中心からのボールの位置（pt・右と下が正）。
    static func ballOffset(label: String) -> (CGFloat, CGFloat) {
        let row: CGFloat = label.contains("高め") ? -1 : label.contains("低め") ? 1 : 0
        let col: CGFloat = label.hasSuffix("の左") ? -1 : label.hasSuffix("の右") ? 1 : 0
        return (col * cell, row * cell)
    }
}
