import XCTest

/// 柵越えおじさんの空振りの演出（#1681）を画面で出す E2E。`-homerunForceWhiffGag` で振った空振りに必ず演出を出し、
/// 1 球目を早すぎる空振りにして、回って倒れて座る（ぐるぐる目・星）まで待つ。見た目の確認は外で録画して見る
/// （`xcrun simctl io <UDID> recordVideo`）。CI では回さない（シミュレータで手元実行）。
///
/// 実行例（UDID で端末を指定する）:
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/HomerunWhiffGagE2ETests
/// ```
/// 環境変数（`TEST_RUNNER_` を付けて xcodebuild に渡す）:
/// - `E2E_SHOT_DIR`: 結果のスクリーンショット（演出の後）を書き出すフォルダ
@MainActor
final class HomerunWhiffGagE2ETests: XCTestCase {
    func testWhiffGagPlaysAndNextPitchWaits() throws {
        let env = ProcessInfo.processInfo.environment
        HomerunE2ETests.skipQuiescenceWait()
        let app = XCUIApplication()
        app.launchArguments = ["-startGame", "homerun", "-homerun_tutorialSeen_v1", "YES", "-homerunUnlimited", "-screenshotMode", "-homerunForceWhiffGag"]
        app.launch()
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打席に立つ")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "打席に立つ が出ない")
        start.tap()

        let zone = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'ストライクゾーン。ボールは'")).firstMatch
        let pad = app.descendants(matching: .any)["打つ場所"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10), "押せる帯が無い")
        XCTAssertNotNil(HomerunE2ETests.poll(timeout: 10) { zone.exists }, "1 球目が始まらない")
        // 的が出た後（マシンが込める 1.2 秒の後）、輪が重なるずっと前に離す = 早すぎる空振り。
        let from = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 1.6)

        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '^1球目、.*'")).firstMatch
        XCTAssertNotNil(HomerunE2ETests.poll(timeout: 6) { card.exists }, "1 球目の結果のカードが出ない")
        XCTAssertTrue(card.label.contains("空振り"), "1 球目が空振りにならない: \(card.label)")
        // 演出の間（離してから約 4.2 秒）は次の球を投げない: カード（座り込んでから・約 2.4 秒）の 1 秒後もまだ 2 球目は始まらない。
        let pitch2 = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'ストライクゾーン。ボールは'")).firstMatch
        let shownAt = Date()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(pitch2.exists, "演出の途中で次の球が始まった")
        // 演出の後は次の球（構えに戻ってマシンが込める）。
        XCTAssertNotNil(HomerunE2ETests.poll(timeout: 6) { pitch2.exists }, "演出の後に次の球が始まらない")
        print("E2E-WHIFFGAG next pitch after \(Date().timeIntervalSince(shownAt) + 0) s from card")
        if let dir = env["E2E_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("after.png"))
        }
    }
}
