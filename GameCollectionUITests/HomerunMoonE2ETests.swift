import XCTest

/// 柵越えおじさんの月まで飛ぶ隠し演出（#1680）の画面確認。DEBUG の起動引数 `-homerunForceMoon` で振れば必ず月まで飛ぶので、
/// 2 球続けて振り、1 回目（真上へ見上げる・夜空・ヒビ・384,400 km）と 2 回目（割れる・挑戦の終わり・+2）を撮る。
/// CI では回さない（シミュレータで手元実行）。
///
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/HomerunMoonE2ETests
/// ```
/// 環境変数 `TEST_RUNNER_E2E_SHOT_DIR` に書き出すフォルダを渡す（無ければ添付だけ）。
@MainActor
final class HomerunMoonE2ETests: XCTestCase {
    func testMoonShotTwiceBreaksTheMoon() throws {
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
        app.launchArguments = ["-startGame", "homerun", "-homerunUnlimited", "-homerunForceMoon", "-screenshotMode"]
        app.launch()
        let start = app.buttons["打席に立つ"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "打席に立つ が出ない")
        start.tap()

        let zone = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'ストライクゾーン。ボールは'")).firstMatch
        let pad = app.descendants(matching: .any)["打つ場所"]
        let cardQuery = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '^[0-9]+球目、.*'"))
        var labels: [String] = []
        for number in 1...2 {
            // 球ごとに引き直す（firstMatch は最初に見つけた要素（1 球目のカード）に結び付くため）。
            let card = cardQuery.firstMatch
            guard let seen = HomerunE2ETests.poll(timeout: 15, { zone.exists }) else {
                XCTFail("\(number) 球目の投球が始まらない"); return
            }
            // 強制では振れば必ず月になるので、輪が重なる少し前に離せばよい（見送りの締め切りより前）。
            let releaseAt = seen.addingTimeInterval(HomerunE2ETests.windup + HomerunE2ETests.travel - HomerunE2ETests.defaultLatency)
            let from = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: max(releaseAt.timeIntervalSinceNow, 0.1), thenDragTo: from.withOffset(CGVector(dx: 0, dy: 4)))
            let released = Date()
            var k = 0
            while !card.exists, Date().timeIntervalSince(released) < 9 {
                save(XCUIScreen.main.screenshot(), String(format: "moon%d-%02d", number, k))
                k += 1
                Thread.sleep(forTimeInterval: 0.25)
            }
            XCTAssertNotNil(HomerunE2ETests.poll(timeout: 8, { card.exists }), "\(number) 球目の結果のカードが出ない")
            Thread.sleep(forTimeInterval: 0.4)
            labels.append(card.label)
            save(XCUIScreen.main.screenshot(), "moon\(number)-card")
            if number == 1 {
                XCTAssertTrue(card.label.contains("月まで飛んだ"), card.label)
                XCTAssertNotNil(HomerunE2ETests.poll(timeout: 8, { !card.exists }), "1 球目のカードが消えない")
            } else {
                XCTAssertTrue(card.label.contains("月が割れた"), card.label)
            }
        }
        // 2 回目で挑戦が終わる（10 球の結果の画面）。
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '球で終了'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 12), "挑戦が終わらない: \(labels)")
        Thread.sleep(forTimeInterval: 0.8)
        save(XCUIScreen.main.screenshot(), "moon-result")
        print("MOON-E2E\n\(labels.joined(separator: "\n"))")
    }
}
