import XCTest

/// おじさんの荷物運びパズルの開始シートに、選んでいるモードの遊び方の要点が図つきでそのまま並ぶこと
/// （会長指示 2026-10-12「遊び方の概要を難易度（モード選択）のところで見せろ。遷移リンクを貼るだけでは駄目」）。
///
/// 開始シート（荷運びモード）に要点が出ている → 操作・れんさの説明を開く → パズルモードを選ぶと
/// その場で中身が替わる（荷運びモードの説明は消える）、を通しで見る。別画面へは遷移しない。
/// CI では回さない（シミュレータで手元実行）。
///
/// 実行例（UDID で端末を指定する）:
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/OjisanPuzzleSetupHowToE2ETests
/// ```
/// 環境変数 `TEST_RUNNER_E2E_SHOT_DIR` を渡すと、各段のスクリーンショットをそのフォルダへ書き出す。
@MainActor
final class OjisanPuzzleSetupHowToE2ETests: XCTestCase {
    func testSetupSheetShowsGuideForSelectedModeInline() throws {
        let shotDir = ProcessInfo.processInfo.environment["E2E_SHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let shotDir { try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true) }
        func shot(_ name: String) {
            sleep(1)
            let image = XCUIScreen.main.screenshot()
            if let shotDir { try? image.pngRepresentation.write(to: shotDir.appendingPathComponent("\(name).png")) }
            let attachment = XCTAttachment(screenshot: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        HomerunE2ETests.skipQuiescenceWait()
        let app = XCUIApplication()
        func text(_ fragment: String) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
        }
        app.launchArguments = ["-startGame", "ojisanpuzzle", "-screenshotMode"]
        app.launch()

        // 1. 開始シート（初期は荷運びモード）に、そのモードの要点がそのまま並んでいる。
        XCTAssertTrue(text("荷運びモードのルール").waitForExistence(timeout: 20), "開始シートに荷運びモードのルールが無い")
        XCTAssertTrue(text("腰をいたわろう").exists, "荷運びモードの目的が開始シートに出ていない")
        XCTAssertFalse(app.buttons["荷運びモードの遊び方を見る"].exists, "別画面へ遷移するボタンが残っている")
        XCTAssertTrue(app.buttons["スタート"].isHittable, "スタートボタンが下端に見えていない")
        shot("1-backpain-top")
        app.swipeUp()
        XCTAssertTrue(text("腰痛ゲージがあり").exists, "腰痛ゲージの説明が開始シートに出ていない")
        shot("2-backpain-scrolled")

        // 2. 操作・れんさの説明はその場で開く（別画面に移らない）。
        let details = app.buttons["操作・れんさのくわしい説明"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(text("スワイプとタップ").waitForExistence(timeout: 5), "操作の説明が開かない")
        XCTAssertFalse(app.buttons["閉じる"].exists, "別画面の遊び方シートが開いている")
        app.swipeUp()
        shot("3-backpain-details")

        // 3. パズルモードを選ぶと、その場で中身がパズルモードに替わる。
        // 上端で下へスワイプするとシートごと閉じるので、選択肢が押せる位置に来たら止める。
        let puzzleChooser = app.buttons["パズルモード"].firstMatch
        for _ in 0..<6 where !puzzleChooser.isHittable { app.swipeDown(velocity: .slow) }
        // スクロールの惰性が残っていると最初のタップは止める操作として吸われるので、落ち着いてから押す。
        sleep(1)
        puzzleChooser.tap()
        if !text("パズルモードのルール").waitForExistence(timeout: 2) { puzzleChooser.tap() }
        XCTAssertTrue(text("パズルモードのルール").waitForExistence(timeout: 5), "パズルモードのルールに替わらない")
        XCTAssertTrue(text("得点をのばそう").exists, "パズルモードの目的が出ていない")
        XCTAssertFalse(text("腰をいたわろう").exists, "パズルモードに荷運びモードの説明が残っている")
        XCTAssertFalse(text("腰痛ゲージがあり").exists, "パズルモードに腰痛ゲージの説明が出ている")
        shot("4-puzzle-top")
        app.swipeUp()
        shot("5-puzzle-scrolled")
    }
}
