import XCTest

/// おじさんの荷物運びパズルの開始シートから、選んでいるモードの図入りの遊び方を開けること（会長指示 2026-10-12
/// 「詳しいルール説明をモード選択のところで見れるようにしないと、荷運びモードが分からない」）。
///
/// 開始シート →「荷運びモードの遊び方を見る」→ 閉じる → 開始シートに戻り選択は荷運びのまま →
/// パズルモードを選ぶ →「パズルモードの遊び方を見る」→ 閉じる → パズルモードのまま、を通しで見る。
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
    func testSetupSheetOpensGuideForSelectedMode() throws {
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
        app.launchArguments = ["-startGame", "ojisanpuzzle", "-screenshotMode"]
        app.launch()

        // 1. 開始シート（初期は荷運びモード）に、そのモードの遊び方ボタンが出ている。
        let backpainGuide = app.buttons["荷運びモードの遊び方を見る"]
        XCTAssertTrue(backpainGuide.waitForExistence(timeout: 20), "開始シートに荷運びモードの遊び方ボタンが無い")
        shot("1-setup-backpain")

        // 2. 押すと荷運びモードの図入りの遊び方が開く。
        backpainGuide.tap()
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "遊び方シートが開かない")
        // 開始シートの説明（裏に残っている）と被らない、遊び方シートだけの文言で見分ける。
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "腰をいたわろう")).firstMatch.exists,
                      "荷運びモードの遊び方になっていない")
        shot("2-howto-backpain")

        // 3. 閉じると開始シートに戻り、選択は荷運びモードのまま。
        close.tap()
        XCTAssertTrue(backpainGuide.waitForExistence(timeout: 10), "閉じたあと開始シートに戻らない")

        // 4. パズルモードを選ぶと、ボタンがパズルモードの遊び方に替わる。
        app.buttons["パズルモード"].firstMatch.tap()
        let puzzleGuide = app.buttons["パズルモードの遊び方を見る"]
        XCTAssertTrue(puzzleGuide.waitForExistence(timeout: 10), "パズルモードの遊び方ボタンに替わらない")
        shot("3-setup-puzzle")

        // 5. パズルモードの遊び方が開く（荷運びモードの文言は出ない）。
        puzzleGuide.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "パズルモードの遊び方シートが開かない")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "得点をのばそう")).firstMatch.exists,
                      "パズルモードの遊び方になっていない")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "腰をいたわろう")).firstMatch.exists,
                       "パズルモードの遊び方に荷運びモードの説明が出ている")
        shot("4-howto-puzzle")

        // 6. 閉じてもパズルモードの選択が保たれている。
        close.tap()
        XCTAssertTrue(puzzleGuide.waitForExistence(timeout: 10), "閉じたあとパズルモードの選択が保たれていない")
        shot("5-setup-puzzle-after-close")
    }
}
