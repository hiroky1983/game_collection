import Core
import Foundation
import GameKitTestSupport
import Testing
@testable import GameRunner

/// 初回プレイの操作ガイド（#988）。
@MainActor
@Suite("チャリンコおじさん 初回の操作ガイド")
struct RunnerTutorialTests {
    private func makeDefaults(_ suite: String) -> (UserDefaults, String) {
        let name = "asobiba.runner.tutorial.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test("覚えてほしい 3 つが番号順に並び、どれも短い（1 画面に収める）")
    func stepsAreThreeShortLines() {
        #expect(RunnerTutorial.steps.count == 3)
        #expect(RunnerTutorial.steps.map(\.id) == [1, 2, 3])
        for step in RunnerTutorial.steps {
            #expect(!step.text.isEmpty)
            // iPhone SE の本文の幅（約 190pt・13pt の字で 14 字）に 1 行で収まる長さ。
            #expect(step.text.count <= 14, "「\(step.text)」が長い（SE で折り返す）")
            #expect((step.note?.count ?? 0) <= 14, "「\(step.note ?? "")」が長い")
            #expect(!step.symbol.isEmpty)
        }
        // 会長指示の 3 つ（タップ / 長押しで高く / 二段ジャンプ）が漏れていないこと。
        #expect(RunnerTutorial.steps[0].text.contains("タップ"))
        #expect(RunnerTutorial.steps[1].text.contains("長く押す"))
        #expect(RunnerTutorial.steps[2].text.contains("空中"))
        #expect(RunnerTutorial.steps[2].note?.contains("二段ジャンプ") == true)
    }

    @Test("初回だけ出て、2 回目以降は出ない")
    func showsOnlyOnFirstPlay() {
        let (defaults, name) = makeDefaults("first-play")
        let log = PlayLog(defaults: defaults)

        #expect(RunnerTutorial.shouldShow(playLog: log, arguments: []))
        #expect(!RunnerTutorial.shouldShow(playLog: log, arguments: []), "2 回目は出さない")

        // 再起動相当（同じ保存先から作り直す）でも戻らない。
        #expect(!RunnerTutorial.shouldShow(playLog: PlayLog(defaults: defaults), arguments: []))

        defaults.removePersistentDomain(forName: name)
    }

    @Test("盤の下の 1 行ヒント（gameID = runner）とは印を共有しない")
    func doesNotShareTheHintFlag() {
        let (defaults, name) = makeDefaults("hint-flag")
        let log = PlayLog(defaults: defaults)

        // 画面を開くと `HowToPlayHint` が先に "runner" を消費する。それでもガイドは初回として出る。
        #expect(log.markGuideShown(for: HowToPlayGuide.runner.gameID))
        #expect(RunnerTutorial.seenKey != HowToPlayGuide.runner.gameID)
        #expect(RunnerTutorial.shouldShow(playLog: log, arguments: []))

        defaults.removePersistentDomain(forName: name)
    }

    @Test("撮影モードでは出さず、印も消費しない")
    func hiddenInScreenshotMode() {
        let (defaults, name) = makeDefaults("screenshot")
        let log = PlayLog(defaults: defaults)

        #expect(!RunnerTutorial.shouldShow(playLog: log, arguments: ["app", "-screenshotMode"]))
        #expect(!log.hasShownGuide(for: RunnerTutorial.seenKey), "撮影モードで印を消費してはいけない")
        // 撮影のあとに実機で遊べば初回として出る。
        #expect(RunnerTutorial.shouldShow(playLog: log, arguments: []))

        defaults.removePersistentDomain(forName: name)
    }

    @Test("PlayLog を持たない構成（プレビュー・テスト）では出さない")
    func hiddenWithoutPlayLog() {
        #expect(!RunnerTutorial.shouldShow(playLog: nil, arguments: []))
    }
}

/// ガイドの置き場と導線をソースの形で固定する（見た目・結線は実行では確かめられない）。
@Suite("チャリンコおじさん 操作ガイドの結線")
struct RunnerTutorialWiringTests {
    private static func source() throws -> String {
        SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
    }

    @Test("ガイドはスタート画面のカードの中に出す（コースの外に行を足さない）")
    func tutorialLivesInTheStartScreen() throws {
        let source = try Self.source()
        let startScreen = try #require(SourceScan.declaration(of: "private var startScreen", in: source))
        #expect(startScreen.contains("if showsTutorial"))
        #expect(startScreen.contains("tutorialCard"))
        // コースの外（`body` の VStack）には足さない。
        let body = try #require(SourceScan.declaration(of: "public var body", in: source))
        #expect(!body.contains("tutorialCard"))
    }

    @Test("「はじめる」で閉じてそのまま走り出す")
    func startButtonClosesAndRuns() throws {
        let source = try Self.source()
        let card = try #require(SourceScan.declaration(of: "private var tutorialCard", in: source))
        #expect(card.contains("showsTutorial = false"))
        #expect(card.contains("model.start(.stages)"))
        #expect(card.contains(#"Label("はじめる""#))
    }

    @Test("出すかどうかは RunnerTutorial.shouldShow が決める（撮影モードの除外を迂回しない）")
    func gateGoesThroughShouldShow() throws {
        let source = try Self.source()
        // 判定は 1 か所・1 回だけ。`shouldShow` は「見せた」の記録も兼ねるので、
        // 2 回呼ぶと 2 つめが必ず false になる。
        #expect(SourceScan.matchCount(of: #"RunnerTutorial\.shouldShow\("#, in: source) == 1)
        #expect(source.contains("RunnerTutorial.shouldShow(playLog: services.playLog)"))
        #expect(SourceScan.matchCount(of: #"_showsTutorial\s*=\s*State"#, in: source) == 1)
    }

    /// 1 行ヒント（`HowToPlayHint(.runner)`）はガイドを出した回には出さない。
    ///
    /// `showsTutorial`（いま出しているか）で分岐すると、「はじめる」で閉じた直後の再描画で
    /// ヒントが組み立てられ、同じプレイの中で「タップでジャンプ」を二度言うことになる。
    @Test("ガイドを出した回は 1 行ヒントを出さない（閉じた直後も）")
    func hintIsSuppressedForTheWholeFirstPlay() throws {
        let source = try Self.source()
        let secondary = try #require(SourceScan.declaration(of: "private var secondaryInfo", in: source))
        #expect(secondary.contains("if !tutorialShownOnOpen"))
        #expect(!secondary.contains("if !showsTutorial"))
        #expect(secondary.contains("HowToPlayHint(.runner"))
        // 「閉じた」で false になるのは `showsTutorial` だけ（ヒントの判断は動かさない）。
        #expect(SourceScan.matchCount(of: #"tutorialShownOnOpen\s*=\s*false"#, in: source) == 0)
    }

    @Test("`?` の「くわしいルール」から開き直せる")
    func reopenableFromHowToPlay() throws {
        let source = try Self.source()
        #expect(source.contains("RunnerTutorialPage()"))
        #expect(source.contains("howToPlay(.runner)"))
    }
}
