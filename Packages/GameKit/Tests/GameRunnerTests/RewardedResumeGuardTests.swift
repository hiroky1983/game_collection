import Foundation
import GameKitTestSupport
import Testing

/// ミス画面の「広告を見て途中から再開」を押したあと、広告のロード〜視聴中に並びのボタンが押せないこと（#1068）。
///
/// 押せると `retryStage()` で `runGeneration` が進み、見終えた広告が `resumeFromCheckpoint(forRun:)` の
/// 世代照合で弾かれて視聴が無駄になる。画面の状態はテストから操作できないので、書き方そのものを見る
/// （ナンプレ #911・マインスイーパー #816 と同じ趣旨）。チャリンコおじさんは共通の `RewardedContinueOverlay`
/// ではなく独自の幕を持つため、そちらの走査テストには掛からない。
@Suite("チャリンコおじさん 再開広告の視聴中ガード")
struct RunnerRewardedResumeGuardTests {
    private static let disabledWhileWatching = ".disabled(resumeRescue.isWatching)"

    @Test("視聴中はミス画面の「もう一度」を押せない")
    func retryButtonIsDisabledWhileWatching() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        let retry = try #require(SourceScan.declaration(of: "private var retryButton: some View", in: source),
                                 "「もう一度」ボタンの定義が見つからない（走査が空振りしている）")
        #expect(retry.contains("model.retryStage()"))
        let button = try #require(retry.range(of: "Button {"),
                                  "「もう一度」の Button が見つからない（走査が空振りしている）")
        #expect(retry[button.upperBound...].contains(Self.disabledWhileWatching),
                "広告のロード〜視聴中に「もう一度」が押せる")

        let resume = try #require(SourceScan.declaration(of: "private var resumeButton: some View", in: source),
                                  "再開ボタンの定義が見つからない（走査が空振りしている）")
        #expect(resume.contains(Self.disabledWhileWatching), "広告のロード〜視聴中に再開ボタンを連打できる")
    }

    /// 上のテストは「もう一度」しか見ないので、ミス画面に別のボタン（「マップへ」等）が足されたら
    /// ガード無しでも緑のまま通る。幕に並ぶボタンを 2 つに固定し、増やしたらここで気づけるようにする。
    @Test("ミス画面に並ぶボタンは再開と「もう一度」の 2 つだけ")
    func failedPanelHasOnlyGuardedButtons() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        let overlay = try #require(SourceScan.declaration(of: "private func overlay(faceScale: Int)", in: source),
                                   "オーバーレイの定義が見つからない（走査が空振りしている）")
        let start = try #require(overlay.range(of: "case .failed:"),
                                 "ミス画面の分岐が見つからない（走査が空振りしている）")
        let end = try #require(overlay.range(of: "case ", range: start.upperBound..<overlay.endIndex),
                               "ミス画面の分岐の終わりが見つからない")
        let failedPanel = String(overlay[start.upperBound..<end.lowerBound])

        let buttonNames = try NSRegularExpression(pattern: #"\b[a-z][A-Za-z]*Button\b"#)
            .matches(in: failedPanel, range: NSRange(failedPanel.startIndex..., in: failedPanel))
            .compactMap { Range($0.range, in: failedPanel).map { String(failedPanel[$0]) } }
        #expect(Set(buttonNames) == ["resumeButton", "retryButton"],
                "ミス画面のボタンが変わった。視聴中ガード（\(Self.disabledWhileWatching)）を付けてからこのテストを更新する")
        #expect(!failedPanel.contains("Button {") && !failedPanel.contains("Button("),
                "ミス画面にその場で書いたボタンがある。視聴中ガードを付けて名前付きのボタンに切り出す")
    }
}
