import Testing
import Core
import CoreEngine
@testable import GameHearts
import CoreTestSupport
import GameKitTestSupport

@Suite("ハーツのモジュール")
@MainActor
struct HeartsModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(HeartsModule().id == HeartsModel.gameID)
        #expect(HowToPlayGuide.hearts.gameID == HeartsModule().id)
        #expect(HowToPlayGuide.all.contains(.hearts))
        // 勝敗しか残らないので順位表は持たない（大富豪・いろリレーと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: HeartsModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("遊び方は図入り（項目ごとに図がある）")
    func howToPlayIsIllustrated() {
        let guide = HowToPlayGuide.hearts.illustrated(HeartsHowToFigures.items)
        #expect(guide.items.count == HeartsHowToFigures.items.count)
        #expect(guide.items.allSatisfy { $0.figure != nil })
        #expect(!guide.notes.isEmpty)
    }

    @Test("表示名・説明・ルールに他社の商標や製品名を含めない（Issue #1884 の権利チェック）")
    func noTrademarkedWords() {
        let module = HeartsModule()
        #expect(module.title == "ハーツ")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.hearts
        let texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes
            + HeartsRuleSheet.rules.flatMap { [$0.0, $0.1] }
        for banned in ["Windows", "Microsoft", "マイクロソフト", "ウィンドウズ", "公式", "ライセンス", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = HeartsModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: 7)
        model.startMatch()
        #expect(!module.hasResumableSnapshot(in: store), "配ったばかりの局は保存しない（#240）")
        for card in model.playerHand.prefix(3) { model.togglePass(card) }
        model.confirmPass()
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("画面は共通の枠・レコメンド枠・開始シート・トランプ共通描画を使い、リワード広告は渡す場面のヒントだけ")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameHearts")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot("))
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "レイアウトパターン A（全画面の枠がバナーを最下部に置く・#2531）")
        #expect(!code.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(code.contains("HowToPlayHint(.hearts"))
        #expect(code.contains("HowToPlayGuide.hearts.illustrated(HeartsHowToFigures.items)"))
        #expect(code.contains("GameSetupSheet(") && code.contains("CPUStrengthPicker(level: $level"))
        #expect(code.contains("PlayingCardSurface(") && code.contains("PlayingCardFace("), "札の絵はトランプ共通描画で描く")
        #expect(code.contains("RecordLabel("))
        // リワード広告は渡す場面のヒント（無料 3 回を使い切った後・#3003）の 1 面だけ。
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1 && !code.contains("showRewardedAd(") && !code.contains(".rewardOffer("),
                "リワード広告はヒントの 1 面だけ（ほかは共通のバナー枠だけ）")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\"") && !code.contains("UIImage(") && !code.contains("AsyncImage("), "外部の画像を使わない")
        #expect(code.contains("level: CPUStrength.analyticsLevel"), "CPU の強さを game_start に載せる")
        #expect(code.contains("gameDidRestart(") && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 対局 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("withAITurnRunner(") && code.contains("pauseCPUTurn("), "CPU の手番は AITurnGuard の定石で回す")
        #expect(code.contains(".onDisappear { cpuTask?.cancel() }"), "ボタンから起こした CPU のタスクは画面を離れたら止める")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameHearts/HeartsModel.swift")
        #expect(source.contains("func applyDebugScenario("))
        var depth = 0
        var releaseLines: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1; continue }
            if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1); continue }
            if depth == 0, !trimmed.hasPrefix("//") { releaseLines.append(String(line)) }
        }
        let release = releaseLines.joined(separator: "\n")
        #expect(!release.contains("applyDebugScenario"))
        #expect(release.contains("public func startMatch("), "走査そのものが機能している")
    }

    @Test("撮影用の局面はどれも 52 枚がそろい、手の結果・決着まで進む")
    func debugScenarios() {
        for (name, phase) in [("queen", HeartsPhase.playing), ("handResult", .handResult), ("result", .result)] {
            let model = HeartsModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
                                    cpuDelay: .zero, trickPause: .zero, seed: 1)
            model.startMatch()
            model.applyDebugScenario(name)
            #expect(model.phase == phase, "\(name)")
            let ids = model.hands.flatMap { $0.map(\.id) } + model.currentTrick.map(\.card.id) + model.playedIDs
            #expect(ids.count == 52 && Set(ids).count == 52, "\(name)")
        }
    }

    @Test("手札のタップ判定は iPhone SE の幅でも 44pt 以上・13 枚が 2 段に収まる")
    func handTapTarget() {
        #expect(HeartsHandLayout.tapWidth(screenWidth: 375) >= HeartsHandLayout.minimumTapTarget)
        #expect(HeartsHandLayout.columns * 2 >= HeartsRules.handSize)
    }
}

@Suite("ハーツの読み上げ")
struct HeartsAccessibilityTests {
    @Test("札の呼び名はスート + 数字。記号のまま読ませない")
    func cardNames() {
        #expect(HeartsAccessibility.cardName(c(.spade, 12)) == "スペードのQ")
        #expect(HeartsAccessibility.cardName(c(.heart, 14)) == "ハートのA")
        #expect(HeartsAccessibility.cardName(c(.club, 2)) == "クラブの2")
        for card in HeartsCard.makeDeck() {
            #expect(HeartsAccessibility.cardName(card).rangeOfCharacter(from: .symbols) == nil, "\(card)")
        }
    }

    @Test("手札の読み上げは点・受け取った札・選択中・出せる / 出せないを文字で足す")
    func handLabels() {
        #expect(HeartsAccessibility.handCardLabel(c(.club, 5), isSelected: false) == "クラブの5")
        #expect(HeartsAccessibility.handCardLabel(c(.spade, 12), isSelected: true, hint: .playable)
                == "スペードのQ、13点、選択中、出せます")
        #expect(HeartsAccessibility.handCardLabel(c(.heart, 9), isSelected: false, isReceived: true, hint: .unplayable)
                == "ハートの9、1点、受け取った札、いまは出せません")
    }

    @Test("場の読み上げは出た順に誰が何を出したかと、取りそうな人")
    func trickLabel() {
        #expect(HeartsAccessibility.trickLabel([]) == "場に札はありません")
        #expect(HeartsAccessibility.trickLabel([p(1, c(.diamond, 9)), p(2, c(.diamond, 13))])
                == "場の札、CPU1がダイヤの9、CPU2がダイヤのK。いまはCPU2がいちばん強い")
        #expect(HeartsAccessibility.trickLabel([p(1, c(.diamond, 9)), p(2, c(.diamond, 13)), p(3, c(.spade, 12)), p(0, c(.diamond, 14))])
                == "場の札、CPU1がダイヤの9、CPU2がダイヤのK、CPU3がスペードのQ、あなたがダイヤのA。あなたが取ります")
    }

    @Test("得点の読み上げはこの手と合計")
    func scoreLabel() {
        #expect(HeartsAccessibility.scoreLabel(name: "CPU1", handPoints: 3, total: 12) == "CPU1、この手3点、合計12点")
    }
}
