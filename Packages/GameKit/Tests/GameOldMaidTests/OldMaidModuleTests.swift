import Testing
import SwiftUI
import Core
import CoreEngine
@testable import GameOldMaid
import GameKitTestSupport

@Suite("ババ抜きのモジュール")
@MainActor
struct OldMaidModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(OldMaidModule().id == OldMaidModel.gameID)
        #expect(OldMaidModule().id == "oldmaid")
        #expect(HowToPlayGuide.oldMaid.gameID == OldMaidModule().id)
        #expect(HowToPlayGuide.all.contains(.oldMaid))
        // 勝敗しか残らないので順位表は持たない（大富豪・いろリレーと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: OldMaidModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
        #expect(OldMaidModule().resumesFromSnapshot, "途中の局面から続けられる")
    }

    @Test("表示名・説明・ルールに他社の商標や公式を思わせる語を含めない（Issue #1577 の権利チェック）")
    func noTrademarkedWords() {
        let module = OldMaidModule()
        #expect(module.title == "ババ抜き")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.oldMaid
        let texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes
            + [GameOldMaid.tr("ババ抜き", language: .english), GameOldMaid.tr(
                "CPUの顔を読んで、ジョーカーをよけよう。CPU3人と対戦", language: .english)]
        for banned in ["公式", "ライセンス", "®", "™", "Online", "オンライン"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・難易度の階段・開始シートを使い、広告は既存のバナー枠だけ")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameOldMaid")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot(") && code.contains("ladder: ladder"))
        #expect(code.contains("DifficultyLadderPrompt("))
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "レイアウトパターン A（全画面の枠がバナーを最下部に置く・#2531）")
        #expect(!code.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(code.contains("HowToPlayHint(.oldMaid"))
        #expect(code.contains(".howToPlay(HowToPlayGuide.oldMaid.illustrated(OldMaidHowToFigures.items)"))  // 後ろに .onboarding(...)（#2824）が続く
        #expect(code.contains("GameSetupSheet(") && code.contains("CPUStrengthPicker("))
        #expect(!code.contains("Rescue.request(") && !code.contains("showRewardedAd("), "リワード広告の入口は持たない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\"") && !code.contains("UIImage("), "絵はコード描画と共通部品だけ（外部の画像を使わない）")
        #expect(code.contains("PlayingCardFace(") && code.contains("PlayingCardBack("), "札はトランプ共通基盤で描く")
        #expect(code.contains("gameDidRestart(gameID: gameID, level:") && code.contains("gameDidProgress(")
                && code.contains("gameDidFinish("), "解析は 1 ゲーム 1 組（強さ付き）+ 進行の 3 点で接続する")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameOldMaid/OldMaidModel.swift")
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
        #expect(release.contains("public func startGame("), "走査そのものが機能している")
    }

    @Test("伏せ札のタップ判定は iPhone SE の幅でも 44pt 以上")
    func tapTarget() {
        #expect(OldMaidHandLayout.tapWidth(screenWidth: 375) >= OldMaidHandLayout.minimumTapTarget)
        #expect(OldMaidHandLayout.columns == 7)
    }

    @Test("遊び方は項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func illustratedGuide() {
        let guide = HowToPlayGuide.oldMaid
        #expect(guide.lines.count <= 3)
        #expect(!guide.items.isEmpty)
        #expect(OldMaidHowToFigures.items.count == guide.items.count)
        let illustrated = guide.illustrated(OldMaidHowToFigures.items)
        #expect(illustrated.items.allSatisfy { $0.figure != nil })
        #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
        #expect(illustrated.notes == guide.notes)
    }
}

@Suite("ババ抜きの読み上げと文言")
struct OldMaidAccessibilityTests {
    @Test("札の呼び名は共通基盤の読み。ジョーカーはジョーカー")
    func cardNames() {
        #expect(OldMaidAccessibility.cardName(OldMaidCard(id: 17, suit: .hearts, rank: 5)) == "ハートの5")
        #expect(OldMaidAccessibility.cardName(.joker) == "ジョーカー")
        for card in OldMaidCard.makeDeck() {
            #expect(OldMaidAccessibility.cardName(card).rangeOfCharacter(from: .symbols) == nil, "\(card.label)")
        }
    }

    @Test("伏せ札は左から何枚目かと選択中を読む")
    func targetLabels() {
        #expect(OldMaidAccessibility.targetCardLabel(position: 0, count: 5, isSelected: false) == "伏せた札、左から1枚目（全5枚）")
        #expect(OldMaidAccessibility.targetCardLabel(position: 2, count: 5, isSelected: true) == "伏せた札、左から3枚目（全5枚）、選択中")
    }

    @Test("直近の動きの文")
    func actions() {
        #expect(OldMaidAccessibility.actionText(.none) == "")
        #expect(OldMaidAccessibility.actionText(.dealtPairs(0)) == "ペアなし")
        #expect(OldMaidAccessibility.actionText(.dealtPairs(3)) == "3組捨てた")
        #expect(OldMaidAccessibility.actionText(.drewPair(rank: 12)) == "Qのペアを捨てた")
        #expect(OldMaidAccessibility.actionText(.drewKept) == "1枚引いた")
        #expect(OldMaidAccessibility.faceName(.smile) == "にやりとした顔")
    }

    @Test("英語の文言がある（多言語 #2109）")
    func english() {
        #expect(GameOldMaid.tr("ババ抜き", language: .english) == "Old Maid")
        #expect(GameOldMaid.tr("%@の番", "CPU2", language: .english) == "CPU2's turn")
        #expect(GameOldMaid.tr("残り%lld枚", 1, language: .english) == "1 card")
        #expect(GameOldMaid.tr("残り%lld枚", 7, language: .english) == "7 cards")
        #expect(GameOldMaid.tr("%lld組捨てた", 2, language: .english) == "Discarded 2 pairs")
    }
}
