import Testing
import Core
import CoreEngine
@testable import GameColorRelay
import CoreTestSupport
import GameKitTestSupport

@Suite("いろリレーのモジュール")
@MainActor
struct ColorRelayModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(ColorRelayModule().id == ColorRelayModel.gameID)
        #expect(HowToPlayGuide.colorRelay.gameID == ColorRelayModule().id)
        #expect(HowToPlayGuide.all.contains(.colorRelay))
        // 勝敗しか残らないので順位表は持たない（大富豪と同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: ColorRelayModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("表示名・説明・ルールに他社の商標を含めない（Issue #1320 の権利面の注意）")
    func noTrademarkedWords() {
        let module = ColorRelayModule()
        #expect(module.title == "いろリレー")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description]
            + HowToPlayGuide.colorRelay.lines + [HowToPlayGuide.colorRelay.title, HowToPlayGuide.colorRelay.hint]
            + ColorRelayRuleSheet.rules.flatMap { [$0.0, $0.1] }
        for banned in ["UNO", "uno", "Uno", "ウノ", "公式", "ライセンス", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = ColorRelayModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = ColorRelayModel(services: services, cpuDelay: .zero, seed: 7)
        model.startGame()
        #expect(!module.hasResumableSnapshot(in: store), "配ったばかりの局は保存しない（#240）")
        model.configureForTesting(hands: [[card(.red, .number(3)), card(.green, .number(5))], [card(.green, .number(1))], [card(.green, .number(2))], [card(.green, .number(4))]],
                                  top: card(.red, .number(7)), drawPile: [card(.purple, .number(9))])
        #expect(module.hasResumableSnapshot(in: store))
        model.toggleSelection(card(.red, .number(3)))
        model.playSelected()
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("画面は共通の枠・レコメンド枠・局ガード付きの救済を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameColorRelay")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.colorRelay"))
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1, "救済の入口は引き札の免除 1 面だけ")
        #expect(code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains("model.waivePenaltyAfterAd(forTurn:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("level: "), "難易度は持たないので game_start に level を載せない")
        #expect(code.contains("gameDidRestart(") && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameColorRelay/ColorRelayModel.swift")
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
        #expect(release.contains("public func startGame()"), "走査そのものが機能している")
    }

    @Test("手札のタップ判定は iPhone SE の幅でも 44pt 以上")
    func handTapTarget() {
        #expect(ColorRelayHandLayout.tapWidth(screenWidth: 375) >= ColorRelayHandLayout.minimumTapTarget)
        #expect(ColorRelayHandLayout.columns == 7)
    }
}

@Suite("いろリレーの読み上げ")
struct ColorRelayAccessibilityTests {
    @Test("札の呼び名は色 + 種類。万能札は種類だけ")
    func cardNames() {
        #expect(ColorRelayAccessibility.cardName(card(.red, .number(5))) == "あかの5")
        #expect(ColorRelayAccessibility.cardName(card(.green, .skip)) == "みどりのとばし")
        #expect(ColorRelayAccessibility.cardName(card(.purple, .reverse)) == "むらさきのぎゃく")
        #expect(ColorRelayAccessibility.cardName(card(.yellow, .drawTwo)) == "きいろのプラス2")
        #expect(ColorRelayAccessibility.cardName(card(nil, .wild)) == "いろがえ")
        #expect(ColorRelayAccessibility.cardName(card(nil, .wildDrawFour)) == "いろがえプラス4")
        // 記号のまま読ませない。
        for c in RelayCard.makeDeck() {
            #expect(ColorRelayAccessibility.cardName(c).rangeOfCharacter(from: .symbols) == nil, "\(c)")
        }
    }

    @Test("手札の読み上げは選択中と出せる / 出せないを文字で足す")
    func handLabels() {
        let c = card(.red, .number(5))
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: false) == "あかの5")
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: true, hint: .playable) == "あかの5、選択中、出せます")
        #expect(ColorRelayAccessibility.handCardLabel(c, isSelected: false, hint: .unplayable) == "あかの5、いまは出せません")
    }

    @Test("場の読み上げはいまの札・いろがえならいまの色・山の残り")
    func fieldLabel() {
        #expect(ColorRelayAccessibility.fieldLabel(top: card(.red, .number(5)), activeColor: .red, drawPileCount: 30)
                == "場の札、あかの5。山は残り30枚")
        #expect(ColorRelayAccessibility.fieldLabel(top: card(nil, .wild), activeColor: .yellow, drawPileCount: 3)
                == "場の札、いろがえ。いまの色はきいろ。山は残り3枚")
        #expect(ColorRelayAccessibility.fieldLabel(top: nil, activeColor: .red, drawPileCount: 0) == "場に札はありません")
    }
}
