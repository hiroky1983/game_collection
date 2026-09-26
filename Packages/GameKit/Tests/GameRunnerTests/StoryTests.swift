import Core
import CoreGraphics
import Foundation
import GameKitTestSupport
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GameRunner
import CoreTestSupport

/// ストーリー（始まり・世界の締め 5 回）の流れと絵（#1092 の受け入れ条件 A・B）。
///
/// 決裁の要点は 4 つで、テストもその順に並べる:
/// 1. **始まりは初めて開いたときに 1 回だけ**、**締めはその面を初めてクリアしたときだけ**
/// 2. 締めは毎面のゴール演出（`.chasing`）の**代わり**に流れ、**記録はその手前で確定している**
/// 3. 撮影・QA（`-screenshotMode` / `-simulateRunner`）では自動で流さない
/// 4. 絵は 1 枚に焼き込まれ、格子が揃っていてパレットに無い文字が無い
@Suite("チャリンコおじさん: ストーリー（#1092）")
@MainActor
struct RunnerStoryTests {
    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.story.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// ゴールまで走らせ、決着の演出（`.chasing` / `.story`）に入ったところで止める。
    @discardableResult
    private func runToGoal(_ model: RunnerModel, maxFrames: Int = 60 * 300) -> Bool {
        if model.phase == .ready { model.press(); model.release() }
        var frames = 0
        while model.phase.isRunning, frames < maxFrames {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        model.release()
        return frames < maxFrames
    }

    /// 到達点を最終面まで開け、`stage` 面から始めるモデル。
    private func makeModel(startingAt stage: Int, log: PlayLog, suite: String) throws -> RunnerModel {
        let store = MemorySnapshotStore()
        try store.save(
            RunnerSnapshot(stage: stage, reachedStage: RunnerRules.stageCount), for: RunnerModel.gameID
        )
        return RunnerModel(
            services: makeServices(store: store, log: log), startingAt: stage,
            preference: makePreference(suite)
        )
    }

    // MARK: 1. 場面の定義

    @Test("場面は始まり 1 つと世界の数だけの締めで、見た印の鍵は全部別")
    func scenesCoverEveryWorld() {
        #expect(RunnerStoryScene.all.count == RunnerWorld.allCases.count + 1)
        #expect(RunnerStoryScene.all.first == .intro)
        let keys = RunnerStoryScene.all.map(\.seenKey)
        #expect(Set(keys).count == keys.count, "見た印の鍵が重複している: \(keys)")
        // 初回ガイド（#988）の鍵とも別（同じ枠に入れるので、ぶつかると片方が出なくなる）。
        #expect(!keys.contains(RunnerTutorial.seenKey))
    }

    @Test("締めのきっかけは 6・12・18・24・30 面で、それ以外の面では流れない")
    func endingsFireOnlyAtTheEndOfAWorld() {
        let triggers = RunnerStoryScene.all.compactMap(\.triggerStage)
        #expect(triggers == [6, 12, 18, 24, 30])
        #expect(RunnerStoryScene.intro.triggerStage == nil)
        for stage in 1...RunnerRules.stageCount {
            let scene = RunnerStory.ending(forClearedStage: stage)
            #expect((scene != nil) == triggers.contains(stage), "\(stage) 面: \(String(describing: scene))")
            if let scene { #expect(scene.triggerStage == stage) }
        }
        // 範囲外（撮影用のショーケースの 0 面・面を足したときの 31 面）で落ちない。
        #expect(RunnerStory.ending(forClearedStage: 0) == nil)
        #expect(RunnerStory.ending(forClearedStage: RunnerRules.stageCount + 1) == nil)
    }

    @Test("どの場面もコマが 1 枚以上あり、尺は 7 秒以内、台詞は SE の幅に収まる長さ")
    func panelsAreShortEnough() {
        // 上限は元は 5 秒だったが、`panelDuration` を 1.2→1.6 秒に伸ばしたことで
        // いちばん長い港町（4コマ）が 6.4 秒になった（会長指摘・2026-09-22）。
        for scene in RunnerStoryScene.all {
            let panels = scene.panels
            #expect(!panels.isEmpty, "\(scene): コマが無い")
            let seconds = Double(panels.count) * RunnerStory.panelDuration
            #expect(seconds <= 7.0, "\(scene): \(seconds) 秒（1 場面は長くても 7 秒程度）")
            #expect(!scene.title.isEmpty)
            for panel in panels {
                #expect(!panel.line.isEmpty, "\(scene): 台詞が空のコマがある")
                #expect(
                    panel.line.count <= RunnerStory.lineLimit,
                    "\(scene): 「\(panel.line)」が \(panel.line.count) 文字（上限 \(RunnerStory.lineLimit)）"
                )
            }
        }
    }

    // MARK: 2. 出す・出さないの判定

    @Test("始まりは見せ終えるまで流れ続け、見せ終えたら二度と流れない")
    func introPlaysOnlyOnce() {
        let log = makePlayLog("intro-once")
        #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []))
        RunnerStory.markIntroShown(playLog: log)
        #expect(!RunnerStory.shouldShowIntro(playLog: log, arguments: []), "2 回目にも流れている")
        // `PlayLog` が無い環境（テスト用の入口など）では流さない。
        #expect(!RunnerStory.shouldShowIntro(playLog: nil, arguments: []))
    }

    /// 始まり（最長 4.8 秒）のあいだにナビバーの「戻る」で離れると、`onFinish` が呼ばれない
    /// ＝ `markIntroShown` を通らない。判定そのものでは印を付けない（#1144）。
    @Test("始まりを最後まで見ずに離れたら、次に開いたときもう一度流れる（#1144）")
    func introSurvivesLeavingMidway() {
        let log = makePlayLog("intro-midway")
        #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []))
        // 「開いた」だけでは印が付かない——ここが false になると、始まりも初回の操作ガイドも
        // 二度と出ない（#1144 の現象）。
        #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []), "判定だけで印が付いている")
        #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []))
        // 見せ終えて初めて付く。
        RunnerStory.markIntroShown(playLog: log)
        #expect(!RunnerStory.shouldShowIntro(playLog: log, arguments: []))
    }

    /// `-simulateRunner story-intro` は判定（`shouldShowIntro`）を通さずオーバーレイを直接立てるので、
    /// 見終わると `markIntroShown` に届く。ここで印が付くと、QA でストーリーを流したシミュレータでは
    /// 以後ふつうに起動しても始まりが出なくなる（`captureModesSuppressTheStory` と同じ趣旨）。
    @Test("撮影・QA で始まりを最後まで流しても「見せた」印は付かない（#1144）")
    func captureModesDoNotSpendTheIntroMark() {
        for argument in ["-screenshotMode", "-simulateRunner"] {
            let log = makePlayLog("capture-mark-\(argument)")
            RunnerStory.markIntroShown(playLog: log, arguments: [argument])
            #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []), "\(argument) で印が付いている")
        }
    }

    @Test("締めはその面を初めてクリアしたときだけ流れる")
    func endingPlaysOnlyOnTheFirstClear() {
        let log = makePlayLog("ending-once")
        #expect(RunnerStory.endingToPlay(clearedStage: 6, playLog: log, arguments: []) == .ending(.morning))
        #expect(
            RunnerStory.endingToPlay(clearedStage: 6, playLog: log, arguments: []) == nil,
            "2 回目のクリアでも流れている"
        )
        // 別の世界の締めは独立している。
        #expect(RunnerStory.endingToPlay(clearedStage: 12, playLog: log, arguments: []) == .ending(.evening))
        #expect(RunnerStory.endingToPlay(clearedStage: 7, playLog: log, arguments: []) == nil)
    }

    @Test("撮影・QA（-screenshotMode / -simulateRunner）では始まりも締めも自動では流れない")
    func captureModesSuppressTheStory() {
        for argument in ["-screenshotMode", "-simulateRunner"] {
            let log = makePlayLog("capture-\(argument)")
            #expect(!RunnerStory.shouldShowIntro(playLog: log, arguments: [argument]), "\(argument)")
            #expect(
                RunnerStory.endingToPlay(clearedStage: 6, playLog: log, arguments: [argument]) == nil,
                "\(argument)"
            )
            // **印も付いていない**こと（撮影で消費されると、遊ぶ人が二度と見られなくなる）。
            #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []), "\(argument)")
            #expect(RunnerStory.endingToPlay(clearedStage: 6, playLog: log, arguments: []) != nil, "\(argument)")
        }
    }

    /// 見返しの一覧は**到達点ではなく「見た」印**で決める（CodeRabbit 指摘・#1092）。
    /// 到達点は「クリアした面の次の面」まで進むので、29 面をクリアしただけで 30 になり、
    /// まだ見ていない最後の締めが一覧に出てしまう（これから見る話のネタバレ）。
    @Test("見返せるのはもう見た世界の締めだけ。始まりはいつでも見返せる")
    func replayListFollowsWhatHasBeenSeen() {
        let log = makePlayLog("replay")
        #expect(RunnerStory.replayableScenes(playLog: log) == [.intro])
        #expect(RunnerStory.replayableScenes(playLog: nil) == [.intro], "記録が無くても始まりは出す")

        // 6 面クリア（＝締めを見た）で世界 1 が並ぶ。
        _ = RunnerStory.endingToPlay(clearedStage: 6, playLog: log, arguments: [])
        #expect(RunnerStory.replayableScenes(playLog: log) == [.intro, .ending(.morning)])

        // 29 面クリアでは到達点が 30 になるが、港町の締めはまだ見ていないので並ばない。
        _ = RunnerStory.endingToPlay(clearedStage: 29, playLog: log, arguments: [])
        #expect(
            RunnerStory.replayableScenes(playLog: log) == [.intro, .ending(.morning)],
            "まだ見ていない最後の締めが一覧に出ている（ネタバレ）"
        )

        // 30 面をクリアして初めて並ぶ。
        _ = RunnerStory.endingToPlay(clearedStage: 30, playLog: log, arguments: [])
        #expect(RunnerStory.replayableScenes(playLog: log) == [.intro, .ending(.morning), .ending(.harbor)])
    }

    // MARK: 3. 走行との結び付き

    @Test("世界の最終面をクリアすると、ゴールの演出の代わりに締めが流れる")
    func clearingAWorldPlaysTheEnding() throws {
        let log = makePlayLog("model-ending")
        let model = try makeModel(startingAt: 6, log: log, suite: "story-ending")
        #expect(runToGoal(model), "6 面をゴールできていない（テストが空振り）")
        #expect(model.phase == .story, "締めではなくゴールの演出（\(model.phase)）に入った")
        #expect(model.storyScene == .ending(.morning))
        // **記録は締めの手前で確定している**（#1092 A0 と同じ契約）。
        #expect(model.recordResult != nil, "記録が締めの明けに先送りされている")
        #expect(model.reachedStage == 7)

        model.finishStory()
        #expect(model.phase == .cleared, "締めが明けてもリザルトに移らない")
        #expect(model.storyScene == nil)
        #expect(model.didFinishGoalChase, "リザルトの背後の絵が、毎面の演出を見た回とずれる")
    }

    @Test("同じ面をもう一度クリアすると、締めではなく毎面のゴール演出が流れる")
    func secondClearFallsBackToTheGoalCutscene() throws {
        let log = makePlayLog("model-second")
        let first = try makeModel(startingAt: 6, log: log, suite: "story-second-1")
        #expect(runToGoal(first))
        #expect(first.phase == .story)
        first.finishStory()

        let second = try makeModel(startingAt: 6, log: log, suite: "story-second-2")
        #expect(runToGoal(second))
        #expect(second.phase == .chasing, "2 回目のクリアでも締めが流れている（\(second.phase)）")
        #expect(second.storyScene == nil)
    }

    @Test("締めの面でない面をクリアしたときは、これまでどおり毎面のゴール演出が流れる")
    func ordinaryStageKeepsTheGoalCutscene() throws {
        let log = makePlayLog("model-ordinary")
        let model = try makeModel(startingAt: 1, log: log, suite: "story-ordinary")
        #expect(runToGoal(model))
        #expect(model.phase == .chasing)
    }

    @Test("締めの最中は時間が進んでも局面が変わらない（コマ送りは View が持つ）")
    func storyDoesNotAdvanceWithTime() throws {
        let log = makePlayLog("model-frozen")
        let model = try makeModel(startingAt: 6, log: log, suite: "story-frozen")
        #expect(runToGoal(model))
        #expect(model.phase == .story)
        for _ in 0..<600 { model.tick(dt: 1.0 / 60) }   // 10 秒ぶん
        #expect(model.phase == .story, "時間で勝手にリザルトへ移った")
        #expect(model.storyScene == .ending(.morning))
    }

    /// `RunnerStoryView` はコースを覆うが、ツールバーの「はじめから」はその外側にあるので、
    /// 締めの最中でも新しい走行を始められる（CodeRabbit 指摘・#1092）。
    @Test("締めの最中に新しい走行を始めると、締めも一緒に閉じる")
    func startingANewRunClosesTheEnding() throws {
        let log = makePlayLog("model-newgame")
        let model = try makeModel(startingAt: 6, log: log, suite: "story-newgame")
        #expect(runToGoal(model))
        #expect(model.phase == .story)

        model.newGame(startingAtStage: 1)
        #expect(model.phase == .ready)
        #expect(model.storyScene == nil, "新しい走行の上に締めが被ったまま消せない")
    }

    @Test("締めの最中はジャンプ・一時停止が効かない")
    func storyIgnoresInput() throws {
        let log = makePlayLog("model-input")
        let model = try makeModel(startingAt: 6, log: log, suite: "story-input")
        #expect(runToGoal(model))
        #expect(model.phase == .story)
        model.press()
        model.release()
        #expect(model.phase == .story, "タップが局面を動かした")
        model.pause()
        #expect(model.phase == .story, "一時停止が効いてしまった")
    }

    @Test("締めの最中はコースのヒントが「ジャンプ」を名乗らない")
    func theCourseHintChangesDuringTheEnding() {
        // ここでのダブルタップはジャンプにならない（飛ばすのはオーバーレイの「とばす」）。
        #expect(RunnerAccessibility.courseHint(phase: .story) == "おはなしを表示中です")
        // 他の局面の文言は変えていない（#1121 の約束）。
        #expect(RunnerAccessibility.courseHint(phase: .chasing) == "ダブルタップで演出をスキップ")
        #expect(RunnerAccessibility.courseHint(phase: .running) == "ダブルタップでジャンプ")
    }

    /// VoiceOver・提示順の結線（#1092・CodeRabbit 指摘）。
    ///
    /// SwiftUI の提示順と読み上げは `swift test` から観測できない（ホストした View の
    /// アクセシビリティツリーが読めない）ので、ここは**結線の形**で固定する。
    /// `SourceScan.strippingComments` を通しているので、コメントでの言及には当たらない。
    @Test("VoiceOver 中は自動で送らず、自分で進める操作を出す")
    func voiceOverStopsTheAutoAdvance() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        let view = try #require(SourceScan.declaration(of: "struct RunnerStoryView", in: source))
        #expect(view.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        // 自動送り（`Task.sleep`）へ入る前に抜ける。
        #expect(view.contains("guard !voiceOverEnabled else { return }"))
        #expect(view.contains("if voiceOverEnabled {"), "自分で送る操作が出ていない")
        #expect(view.contains("つぎへ") && view.contains("おわり") && view.contains("スキップ"))
        // 背後のコースへ回り込ませない。
        #expect(view.contains(".accessibilityAddTraits(.isModal)"))
    }

    /// 「見せた」印を付ける場所をソースの形で固定する（#1144）。View の提示は `swift test` から
    /// 観測できないので、`init` で消費していないことと、`onFinish` の側で付けていることを見る。
    @Test("始まりの「見せた」印は、見せ終えた時点でだけ付ける（#1144）")
    func theIntroMarkIsSpentWhenItIsActuallySeen() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        let initializer = try #require(SourceScan.declaration(of: "public init(services", in: source))
        #expect(!initializer.contains("markIntroShown"), "`init` で印を消費している")
        #expect(initializer.contains("RunnerStory.shouldShowIntro(playLog: services.playLog)"))
        // 付けるのはオーバーレイの `onFinish`（最後のコマ／「とばす」／画面タップ）の側だけ。
        #expect(SourceScan.matchCount(of: #"RunnerStory\.markIntroShown\("#, in: source) == 1)
        let body = try #require(SourceScan.declaration(of: "public var body", in: source))
        #expect(body.contains("RunnerStory.markIntroShown(playLog: services.playLog)"))
    }

    @Test("ストーリーが出ているあいだ「はじめから」は押せず、中断しても操作ガイドが消えない")
    func theStoryKeepsThePresentationOrder() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        // ナビバーはオーバーレイの外にあるので、押せると 始まり → ガイド → 開始シートの順が崩れる。
        #expect(source.contains("GameChromeNewGame(.restart, isDisabled: presentedStory != nil)"))
        // それでも中断された経路（撮影用の `-showRunnerStartSheet` など）で取り残さない。
        let open = try #require(SourceScan.declaration(of: "private func openStartSheet", in: source))
        #expect(open.contains("introScene = nil"))
        // 出していない操作ガイドは開始シートの `onDismiss` が引き取る（#1144 で印の消費を
        // 提示の直前へ寄せたので、ここで拾っても二重表示にはならない）。
        #expect(source.contains("isPresented: $showStartSheet, onDismiss:"))
    }

    /// 幕はバナー広告まで覆うので、そのままだと**見えないバナーのインプレッションが計上されうる**
    /// （AdMob の「広告を他の要素で覆わない」・#1147）。判定は純関数で、結線はソースの形で固定する
    /// （View の描画は `swift test` から観測できない）。
    @Test("ストーリーが出ているあいだはバナーを出さず、明けたら戻る（#1147）")
    func theStoryHidesTheBanner() throws {
        #expect(!RunnerView.showsBanner(isStoryPresented: true), "幕の裏に見えないバナーが残る")
        #expect(RunnerView.showsBanner(isStoryPresented: false), "幕が明けてもバナーが戻らない")
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        // 枠は 1 か所だけ。判定を素通りする 2 個目が増えたらここで落ちる。
        #expect(SourceScan.matchCount(of: #"BannerSlot\(ads:"#, in: source) == 1)
        // 判定に渡すのは「幕が出ているか」そのもの（`overlay` が幕を出す条件と同じ式）。
        // ここを見ないと、引数を `false` や逆条件に書き換えても走査が緑のまま通る（verifier 指摘）。
        #expect(
            SourceScan.matchCount(
                of: #"showsBanner\(\s*isStoryPresented:\s*presentedStory != nil\s*\)"#, in: source
            ) == 1,
            "バナーの判定が、幕を出す条件（`presentedStory != nil`）以外を見ている"
        )
        // 判定の**内側**に置く。見るのは `if` のブロックの中身なので、改行や途中に別の部品が
        // 増えることには依らない（CodeRabbit 指摘・PR #1165）。
        let guarded = try #require(
            SourceScan.declaration(of: "if Self.showsBanner(", in: source),
            "バナーの判定（`showsBanner`）を通っていない"
        )
        #expect(guarded.contains("BannerSlot(ads:"), "バナーがストーリーの判定の外に置かれている")
        // 幕のあいだも枠の高さは空の帯で残す（縦幅の分配が変わるとコースの高さまで動く）。
        #expect(source.contains("Color.clear.frame(height: BannerSlot.height)"))
    }

    /// コマ替えを静止画のパッ切り替えからクロスフェードにする（#1170・会長QA「静止画のパッ切り替えで淡々」）。
    ///
    /// `Image`/`Text` は中身の差し替え自体がアニメーション対象にならないため、`.contentTransition`
    /// で補間対象にする必要がある。`.contentTransition` は「有効なアニメーションが張られている
    /// ときだけ」補間する SwiftUI の仕様なので、`.gameAnimation` が Reduce Motion で
    /// `.animation(nil, value:)` に落ちれば、専用の分岐を書かなくてもクロスフェードごと止まる。
    /// この結線が崩れていないかは `swift test` からは見えない（View の描画は観測できない）ので、
    /// 絵・台詞の両方に付いていて `.gameAnimation` の外に出ていないことをソースの形で固定する。
    @Test("絵と台詞のコマ替えはクロスフェードで、Reduce Motion に追従するアニメーションの中にある（#1170）")
    func panelSwitchCrossFadesInsideGameAnimation() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        let view = try #require(SourceScan.declaration(of: "struct RunnerStoryView", in: source))
        #expect(
            SourceScan.matchCount(of: #"\.contentTransition\(\.opacity\)"#, in: view) == 2,
            "絵・台詞のどちらかに .contentTransition が付いていない"
        )
        #expect(
            view.contains(".gameAnimation(.easeInOut(duration: 0.28), value: index)"),
            "素の .animation を使っている、または gameAnimation の外に出ている"
        )
    }

    // MARK: 4. 絵

    @Test("どのコマも 1 枚の格子に焼き込まれ、寸法が揃っていてパレットに無い文字が無い")
    func panelsAreWellFormed() {
        for panel in RunnerStoryArt.Panel.allCases {
            let s = RunnerStoryArt.sprite(panel)
            #expect(
                s.width == RunnerStoryArt.panelWidth && s.height == RunnerStoryArt.panelHeight,
                "\(panel): \(s.width)×\(s.height)"
            )
            #expect(s.undefinedKeys.isEmpty, "\(panel): パレットに無い文字 \(s.undefinedKeys)")
            // 土台を敷いてあるので、透明なドットは 1 つも残らない（背景の抜けは絵の欠けに見える）。
            #expect(!s.rows.contains { $0.contains(".") }, "\(panel): 透明なドットが残っている")
        }
    }

    @Test("描き起こした部品は格子が揃い、パレットに無い文字が無い")
    func newPartsAreWellFormed() {
        let parts: [(String, PixelSprite)] = [
            ("ガラガラ", RunnerStoryArt.lotteryDrum()),
            ("カラス", RunnerStoryArt.crow()),
            ("配達トラック", RunnerStoryArt.deliveryTruck()),
            ("貨物船", RunnerStoryArt.cargoShip()),
        ]
        for (name, s) in parts {
            #expect(s.undefinedKeys.isEmpty, "\(name): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil, "\(name): 何も描かれていない")
            // 1 コマ（240×136）に収まる（はみ出す部品は置いた瞬間に切り落とされ、絵が欠ける）。
            // 部品はコマの半分の細かさで描くので、置くときの 2 倍でも収まることまで見る。
            #expect(
                s.width * 2 <= RunnerStoryArt.panelWidth && s.height * 2 <= RunnerStoryArt.panelHeight,
                "\(name): \(s.width)×\(s.height)"
            )
        }
    }

    @Test("胸像は高解像度の正面顔（32×30）を 3 倍にしたもので、コマの下端に接地する")
    func bustUsesHighResFace() {
        for face in OjisanPixel.Face.allCases {
            let bust = RunnerStoryArt.bust(face)
            let head = OjisanPixel.face(face).scaled(3)
            #expect(bust.width == head.width, "\(face): 幅 \(bust.width)")
            #expect(bust.height == RunnerStoryArt.bustHeight, "\(face): 高さ \(bust.height)")
            // 肩が乗り始める手前までは顔そのもの。合成でパレットの文字は振り直されるので、
            // 「どこが透明か」の型で見る（粗い版・別の倍率に戻したらここで落ちる）。
            func mask(_ rows: [String]) -> [String] {
                rows.map { String($0.map { $0 == "." ? "." : "#" }) }
            }
            let sharedRows = head.height - 12
            #expect(
                mask(Array(bust.rows.prefix(sharedRows))) == mask(Array(head.rows.prefix(sharedRows))),
                "\(face): 顔の形がコマの胸像と合っていない"
            )
            // 顔と肩の間に透けた行を作らない（`bust` の「隙間を空けると首が切れて見える」の担保。
            // 重ねる量を取り違えて肩が下にずれると、顎の下に地の色が帯で出るのでここで落ちる）。
            #expect(
                !bust.rows.contains { !$0.contains { $0 != "." } },
                "\(face): 顔と肩の間、または下端に透けた行がある"
            )
        }
        // 下端がコマの下端にちょうど接する。
        #expect(RunnerStoryArt.bustY + RunnerStoryArt.bustHeight == RunnerStoryArt.panelHeight)
    }

    @Test("場面ごとに絵が違う（同じ絵を使い回して話が進まない、を防ぐ）")
    func everySceneHasItsOwnArt() {
        let used = RunnerStoryScene.all.flatMap { $0.panels.map(\.art) }
        #expect(Set(used).count == used.count, "同じ絵を 2 回使っている: \(used)")
        #expect(Set(used) == Set(RunnerStoryArt.Panel.allCases), "使われていない絵、または定義の無い絵がある")
    }

    @Test("締めの背景はその世界の空の色で描く（世界の配色を使い回す）")
    func endingsUseTheirWorldColors() {
        for world in RunnerWorld.allCases {
            let scene = RunnerStoryScene.ending(world)
            let first = RunnerStoryArt.sprite(scene.panels[0].art)
            // 1 行目は空だけ。世界の `palette.sky` がそのまま出ているはず。
            let topRow = Array(first.rows[0])
            let colors = Set(topRow.map { first.palette[$0] })
            #expect(colors == [world.palette.sky], "\(world): 空が \(colors)")
        }
    }

    /// レビュー用: `RUNNER_STORY_OUT` にディレクトリを渡すと、全 16 コマを並べた PNG を書き出す。
    /// 絵の良し悪しは機械では測れないので、**人が 1 枚で見比べられる形**を用意する
    /// （`PixelArtTests` のおじさんシートと同じ作法）。
    @Test("レビュー用のシートを書き出す（環境変数があるときだけ）")
    func writeReviewSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["RUNNER_STORY_OUT"] else { return }
        let panels = RunnerStoryArt.Panel.allCases
        // #1349 でコマの格子を倍にしたので、1 ドット = 1px で撮る（シートの大きさは従来どおり）。
        let scale = 1, columns = 4, gap = 8
        let cell = (w: RunnerStoryArt.panelWidth * scale, h: RunnerStoryArt.panelHeight * scale)
        let rows = (panels.count + columns - 1) / columns
        let width = columns * cell.w + (columns + 1) * gap
        let height = rows * cell.h + (rows + 1) * gap
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .none
        for (i, panel) in panels.enumerated() {
            let img = try #require(RunnerStoryArt.sprite(panel).cgImage(scale: scale), "\(panel)")
            let col = i % columns, row = i / columns
            ctx.draw(img, in: CGRect(
                x: gap + col * (cell.w + gap),
                // CGContext の y は下が 0。並びを見たまま（左上から）にするため上下を返す。
                y: height - gap - (row + 1) * cell.h - row * gap,
                width: cell.w, height: cell.h
            ))
        }
        let image = try #require(ctx.makeImage())
        let url = URL(fileURLWithPath: out).appendingPathComponent("runner-story-sheet.png")
        let dest = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    // MARK: 5. 撮影・QA の入口

    @Test("起動引数から場面を引ける（-simulateRunner story-intro / story-world1〜5）")
    func debugScenesMapToLaunchArguments() {
        #expect(RunnerStory.debugScene(for: "story-intro") == .intro)
        for world in RunnerWorld.allCases {
            #expect(RunnerStory.debugScene(for: "story-world\(world.number)") == .ending(world), "\(world)")
        }
        #expect(RunnerStory.debugScene(for: "story-world0") == nil)
        #expect(RunnerStory.debugScene(for: "story-world9") == nil)
        #expect(RunnerStory.debugScene(for: "cleared") == nil, "他のシナリオを横取りしている")
        #expect(RunnerStory.debugScene(for: "chasing") == nil)
    }

    @Test("`:N` を付けると N コマ目で止まる（撮影で次のコマに進んでしまわないように）")
    func debugPanelIndexFreezesOneFrame() {
        #expect(RunnerStory.debugPanelIndex(for: "story-intro") == nil, "指定が無ければふつうにコマ送りする")
        #expect(RunnerStory.debugScene(for: "story-intro:3") == .intro, "場面の読み取りが `:N` で壊れている")
        #expect(RunnerStory.debugPanelIndex(for: "story-intro:1") == 0)
        #expect(RunnerStory.debugPanelIndex(for: "story-intro:3") == 2)
        // コマ数を超えた指定は最後のコマに丸める（撮り直しのたびに落ちない）。
        let last = RunnerStoryScene.intro.panels.count - 1
        #expect(RunnerStory.debugPanelIndex(for: "story-intro:99") == last)
        #expect(RunnerStory.debugPanelIndex(for: "story-intro:0") == nil, "0 以下は指定なし扱い")
        #expect(RunnerStory.debugPanelIndex(for: "story-intro:abc") == nil)
        #expect(RunnerStory.debugPanelIndex(for: "cleared:2") == nil, "他のシナリオを横取りしている")
        #expect(RunnerStory.debugScene(for: "story-world5:2") == .ending(.harbor))
        #expect(RunnerStory.debugPanelIndex(for: "story-world5:4") == 3)
    }
}
