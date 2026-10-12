import XCTest

/// ディープリンク `asobiba://game/homerun`（#2141）で柵越えおじさんが開くことの E2E。
/// アプリが終了している状態（コールドスタート）と、起動してハブを出している状態の両方を、
/// システムに URL を開かせる経路（メモ帳のリンクのタップと同じ。「"あそびば"で開きますか?」の確認を押す）で確かめる。
/// URL → 遷移先の規則そのものは `DeepLinkTests`（GameKit）で固定している。CI では回さない（シミュレータで手元実行）。
///
/// 実行例（UDID で端末を指定する）:
/// ```
/// xcodebuild test -project GameCollection.xcodeproj -scheme GameCollectionUITests \
///   -destination "id=<UDID>" -only-testing:GameCollectionUITests/DeepLinkE2ETests
/// ```
/// 環境変数 `TEST_RUNNER_E2E_SHOT_DIR` を渡すと、開いた直後の画面をそのフォルダへ書き出す。
@MainActor
final class DeepLinkE2ETests: XCTestCase {
    private static let url = URL(string: "asobiba://game/homerun")!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testColdStartOpensHomerun() throws {
        let app = XCUIApplication()
        app.terminate()
        openViaSystem()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "アプリが前面に来ない")
        assertHomerunOpened(app, shot: "deeplink-coldstart.png")
    }

    func testWhileRunningOpensHomerun() throws {
        let app = XCUIApplication()
        app.launch()
        // ハブが出ていること（柵越えおじさんの特別枠が見える）を確かめてから開く。
        sleep(3)
        save(XCUIScreen.main.screenshot(), as: "deeplink-running-before.png")
        openViaSystem()
        assertHomerunOpened(app, shot: "deeplink-running.png")
    }

    /// システムに URL を開かせ、出てきた確認の「開く」を押す。
    private func openViaSystem() {
        XCUIDevice.shared.system.open(Self.url)
        let open = springboard.buttons["開く"]
        if open.waitForExistence(timeout: 5) { open.tap() }
    }

    private func assertHomerunOpened(_ app: XCUIApplication, shot: String) {
        // 柵越えおじさんの開始画面の「打席に立つ」が出ればゲーム画面に入っている。
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打席に立つ")).firstMatch
        let opened = start.waitForExistence(timeout: 15)
        sleep(1)
        save(XCUIScreen.main.screenshot(), as: shot)
        XCTAssertTrue(opened, "柵越えおじさんが開かない")
    }

    private func save(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["E2E_SHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name))
    }
}
