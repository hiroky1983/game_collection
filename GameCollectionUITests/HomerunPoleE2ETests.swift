import XCTest

/// 柵越えおじさんのファウルポール直撃（#1686）の画面確認。DEBUG の起動引数 `-homerunForcePole` で振れば必ずポールに当たるので、
/// 1 球目は左（引っ張り = カーソルを左へ）、2 球目は右（流し）へ振り、当たる直前・跳ね返り・結果のカードを撮る。
/// CI では回さない（シミュレータで手元実行）。
///
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/HomerunPoleE2ETests
/// ```
/// 環境変数 `TEST_RUNNER_E2E_SHOT_DIR` に書き出すフォルダを渡す（無ければ添付だけ）。
@MainActor
final class HomerunPoleE2ETests: XCTestCase {
    func testPoleHitOnBothSides() throws {
        let shotDir = ProcessInfo.processInfo.environment["E2E_SHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let shotDir { try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true) }
        func save(_ shot: XCUIScreenshot, _ name: String) {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let shotDir { try? shot.pngRepresentation.write(to: shotDir.appendingPathComponent("\(name).png")) }
        }

        HomerunE2ETests.skipQuiescenceWait()
        let app = XCUIApplication()
        app.launchArguments = ["-startGame", "homerun", "-homerunUnlimited", "-homerunForcePole", "-screenshotMode"]
        app.launch()
        let start = app.buttons["打席に立つ"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "打席に立つ が出ない")
        start.tap()

        let zone = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'ストライクゾーン。ボールは'")).firstMatch
        let pad = app.descendants(matching: .any)["打つ場所"]
        let cardQuery = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '^[0-9]+球目、.*'"))
        var labels: [String] = []
        // 負荷が高いと離す時刻がずれて見送り（空振り）になることがあるので、左右それぞれポール直撃が出るまで数球まで振り直す。
        var pitch = 0
        for side in ["left", "right"] {
            var done = false
            for attempt in 0..<4 where !done {
                pitch += 1
                let card = cardQuery.firstMatch
                guard let seen = HomerunE2ETests.poll(timeout: 15, { zone.exists }) else {
                    XCTFail("\(pitch) 球目の投球が始まらない"); return
                }
                // 強制では振れば必ずポールに当たる。向きはカーソルの左右（照準の横のずれが方向を決める）で選ぶ。
                let releaseAt = seen.addingTimeInterval(HomerunE2ETests.windup + HomerunE2ETests.travel - HomerunE2ETests.defaultLatency)
                let from = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let dx: CGFloat = side == "left" ? -40 : 40
                from.press(forDuration: max(releaseAt.timeIntervalSinceNow, 0.1), thenDragTo: from.withOffset(CGVector(dx: dx, dy: 4)))
                let released = Date()
                var k = 0
                while !card.exists, Date().timeIntervalSince(released) < 9 {
                    save(XCUIScreen.main.screenshot(), String(format: "pole-%@-%d-%02d", side, attempt, k))
                    k += 1
                    Thread.sleep(forTimeInterval: 0.15)
                }
                guard HomerunE2ETests.poll(timeout: 8, { card.exists }) != nil else { continue }
                let label = card.label
                labels.append(label)
                if label.contains("ポール直撃") {
                    save(XCUIScreen.main.screenshot(), "pole-\(side)-card")
                    XCTAssertTrue(label.contains(side == "left" ? "レフト" : "ライト"), label)
                    done = true
                }
                _ = HomerunE2ETests.poll(timeout: 8, { !card.exists })
            }
            XCTAssertTrue(done, "\(side) のポール直撃が出ない: \(labels)")
        }
        print("POLE-E2E\n\(labels.joined(separator: "\n"))")
    }
}
