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

    @Test("QA・撮影用の起動（-simulateRunner）でも出さず、印も消費しない")
    func hiddenForDebugScenarios() {
        let (defaults, name) = makeDefaults("simulate")
        let log = PlayLog(defaults: defaults)

        // `-screenshotMode` を付けずに `showcase` を初回起動すると、見たい画にガイドが被っていた（#1063）。
        #expect(!RunnerTutorial.shouldShow(playLog: log, arguments: ["app", "-simulateRunner", "showcase"]))
        #expect(!log.hasShownGuide(for: RunnerTutorial.seenKey), "QA の起動で印を消費してはいけない")
        #expect(RunnerTutorial.shouldShow(playLog: log, arguments: []), "普通に開けば初回として出る")

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

    @Test("ガイドはモーダルで出す（プレイ画面の中に置かない）")
    func tutorialIsPresentedAsASheet() throws {
        let source = try Self.source()
        // 会長指摘（2026-09-16）: コースの上のカードで出すと、その「はじめる」が
        // ステージ制で走り出すため初回だけモードを選べない。モーダルに出し、
        // 閉じたら開始シート（モード選択）へ送る。
        let body = try #require(SourceScan.declaration(of: "public var body", in: source))
        #expect(body.contains("sheet(isPresented: $showsTutorial"))
        #expect(body.contains("RunnerTutorialSheet"))
        #expect(body.contains("onDismiss: { presentStartSheetIfNeeded() }"))
        // プレイ画面側（スタート画面）には置かない。
        let startScreen = try #require(SourceScan.declaration(of: "private var startScreen", in: source))
        #expect(!startScreen.contains("showsTutorial"))
        #expect(!source.contains("private var tutorialCard"))
    }

    @Test("「はじめる」は閉じるだけで、モードはそのあと開始シートで選ぶ")
    func startButtonOnlyCloses() throws {
        let source = try Self.source()
        let sheet = try #require(SourceScan.declaration(of: "struct RunnerTutorialSheet", in: source))
        #expect(sheet.contains("onClose"))
        #expect(sheet.contains(#"Text("はじめる")"#))
        // ガイドからモードを焼き込まない（ここで .stages に倒すと初回だけエンドレスを選べない）。
        #expect(!sheet.contains("model.start"))
        #expect(!sheet.contains(".stages"))
    }

    @Test("出すかどうかは RunnerTutorial.shouldShow が決める（撮影モードの除外を迂回しない）")
    func gateGoesThroughShouldShow() throws {
        let source = try Self.source()
        // 判定は 1 か所・1 回だけ。`shouldShow` は「見せた」の記録も兼ねるので、
        // 2 回呼ぶと 2 つめが必ず false になる。
        #expect(SourceScan.matchCount(of: #"RunnerTutorial\.shouldShow\("#, in: source) == 1)
        #expect(source.contains("RunnerTutorial.shouldShow(playLog: services.playLog)"))
        // 判定の結果は `init` で 1 か所に焼く。#1092 でストーリーの始まりが前に入ったので、
        // 焼く先は提示のフラグ（`showsTutorial`）ではなく控え（`pendingTutorial`）のほう
        // ——`init` から直接提示を立てると、始まりのオーバーレイの上にモーダルが被る。
        #expect(SourceScan.matchCount(of: #"_pendingTutorial\s*=\s*State"#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"_showsTutorial\s*=\s*State"#, in: source) == 0)
        #expect(source.contains("@State private var showsTutorial = false"))
    }

    /// 出す順は 始まり（#1092）→ 操作ガイド → 開始シート（#1092 の受け入れ条件 A）。
    ///
    /// SwiftUI の提示順は `swift test` からは観測できない（ホストした View のアクセシビリティ
    /// ツリーが読めない）ので、ここは**結線の形**で固定する。
    @Test("操作ガイドはストーリーの始まりが明けてから出す")
    func tutorialFollowsTheStoryIntro() throws {
        let source = try Self.source()
        let after = try #require(SourceScan.declaration(of: "private func beginAfterIntro", in: source))
        #expect(after.contains("pendingTutorial"))
        #expect(after.contains("showsTutorial = true"))
        #expect(after.contains("presentStartSheetIfNeeded()"))
        // 始まりを出す回は、明けるまで先へ進めない（`onAppear` で分岐する）。
        #expect(source.contains("introScene = .intro"))
    }

    /// 1 行ヒント（`HowToPlayHint(.runner)`）は**走行中ずっと出す**。
    ///
    /// 会長指摘（2026-09-16）「タップしてジャンプはゲーム中に常時出てほしいセクションなのに
    /// なんでゲーム中に消えんの」。共通部品の既定は「初回だけ」で、印を消費した次の再描画で
    /// 消えるため、遊んでいる最中に行ごと消えて画面が動いていた。
    @Test("1 行ヒントは常時出す（印を消費して消える既定を使わない）")
    func hintIsAlwaysVisible() throws {
        let source = try Self.source()
        let secondary = try #require(SourceScan.declaration(of: "private var secondaryInfo", in: source))
        #expect(secondary.contains("HowToPlayHint(.runner, isVisible: true)"))
        // 「初回だけ」の既定（playLog を渡す初期化子）は使わない。
        #expect(!secondary.contains("playLog:"))
        #expect(!secondary.contains("tutorialShownOnOpen"))
    }

    @Test("`?` の「くわしいルール」から開き直せる")
    func reopenableFromHowToPlay() throws {
        let source = try Self.source()
        #expect(source.contains("RunnerTutorialPage()"))
        #expect(source.contains("howToPlay(.runner)"))
    }
}
