import Core
import CoreGraphics
import Foundation
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

    @Test("どの場面もコマが 1 枚以上あり、尺は 5 秒以内、台詞は SE の幅に収まる長さ")
    func panelsAreShortEnough() {
        for scene in RunnerStoryScene.all {
            let panels = scene.panels
            #expect(!panels.isEmpty, "\(scene): コマが無い")
            let seconds = Double(panels.count) * RunnerStory.panelDuration
            #expect(seconds <= 5.0, "\(scene): \(seconds) 秒（1 場面は長くても 5 秒程度）")
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

    @Test("始まりは初めて開いたときだけ流れる")
    func introPlaysOnlyOnce() {
        let log = makePlayLog("intro-once")
        #expect(RunnerStory.shouldShowIntro(playLog: log, arguments: []))
        #expect(!RunnerStory.shouldShowIntro(playLog: log, arguments: []), "2 回目にも流れている")
        // `PlayLog` が無い環境（テスト用の入口など）では流さない。
        #expect(!RunnerStory.shouldShowIntro(playLog: nil, arguments: []))
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
            // 1 コマ（120×68）に収まる（はみ出す部品は置いた瞬間に切り落とされ、絵が欠ける）。
            #expect(
                s.width <= RunnerStoryArt.panelWidth && s.height <= RunnerStoryArt.panelHeight,
                "\(name): \(s.width)×\(s.height)"
            )
        }
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
        let scale = 2, columns = 4, gap = 8
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
