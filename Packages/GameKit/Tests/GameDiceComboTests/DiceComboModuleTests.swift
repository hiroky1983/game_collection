import Testing
import Foundation
import Core
import CoreEngine
@testable import GameDiceCombo
import GameKitTestSupport

@Suite("サイコロ役づくりのモジュール")
@MainActor
struct DiceComboModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(DiceComboModule().id == DiceComboModel.gameID)
        #expect(HowToPlayGuide.diceCombo.gameID == DiceComboModule().id)
        #expect(HowToPlayGuide.all.contains(.diceCombo))
        #expect(HowToPlayGuide.diceCombo.items.count == DiceComboHowToFigures.items.count)
    }

    @Test("表示名・説明・遊び方・役の名前に市販のダイスゲームの商品名を含めない（Issue #1752 の権利チェック）")
    func noTrademarkedWords() {
        let module = DiceComboModule()
        #expect(module.title == "サイコロ役づくり")
        let guide = HowToPlayGuide.diceCombo
        var texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes
            + DiceComboCategory.allCases.flatMap { [DiceComboText.name($0), DiceComboText.rule($0)] }
        // 英語の表示も同じく確かめる。
        texts += [
            GameDiceCombo.tr("サイコロ役づくり", language: .english),
            GameDiceCombo.tr("サイコロ5個を3回まで振って、12の役に点を入れていこう", language: .english),
            GameDiceCombo.tr("ファイブダイス", language: .english),
        ]
        for banned in ["ヨット", "ヤッツィー", "ヤッツイー", "Yacht", "yacht", "Yahtzee", "yahtzee", "Yatzy", "yatzy",
                       "ハズブロ", "Hasbro", "公式", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・図入りの遊び方を使い、広告の面を足していない")
    func viewUsesSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameDiceCombo"))
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationArea("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.diceCombo"))
        #expect(code.contains(".howToPlay(HowToPlayGuide.diceCombo.illustrated(DiceComboHowToFigures.items))"))
        #expect(!code.contains("showRewardedAd("), "リワード広告は使わない")
        #expect(!code.contains("RewardedRescue("), "救済の広告面は持たない（#1752 は広告を足さない）")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\""), "絵はコードで描く（外部の画像を使わない）")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 局 1 組 + 進行で接続する")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameDiceCombo/DiceComboModel.swift")
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
        #expect(release.contains("public func roll()"), "走査そのものが機能している")
    }

    @Test("読み上げ: 出目・キープ・役の点を言葉で伝える")
    func accessibilityLabels() {
        #expect(DiceComboAccessibility.dieLabel(index: 0, value: 4, isHeld: true) == "サイコロ1、4、キープ中")
        #expect(DiceComboAccessibility.dieLabel(index: 2, value: 6, isHeld: false) == "サイコロ3、6")
        #expect(DiceComboAccessibility.diceLabel(dice: [], held: []) == "サイコロはまだ振っていません")
        #expect(DiceComboAccessibility.diceLabel(dice: [4, 4, 2, 4, 6], held: [true, true, false, true, false])
                == "出目 4と4と2と4と6、キープ 4と4と4")
        #expect(DiceComboAccessibility.diceLabel(dice: [1, 2, 3, 4, 5], held: Array(repeating: false, count: 5))
                == "出目 1と2と3と4と5")
        #expect(DiceComboAccessibility.categoryLabel(.fullHouse, scored: 23, preview: nil) == "フルハウス、23点、記入済み")
        #expect(DiceComboAccessibility.categoryLabel(.bigStraight, scored: nil, preview: 30) == "Bストレート、いま入れると30点")
        #expect(DiceComboAccessibility.categoryLabel(.choice, scored: nil, preview: nil) == "チョイス、未記入")
        #expect(DiceComboAccessibility.rollLabel(remaining: 2) == "サイコロを振る、残り2回")
        #expect(DiceComboAccessibility.rollLabel(remaining: 0) == "サイコロを振る、もう振れません")
    }

    @Test("役の名前と説明は 12 役ぶん重ならない")
    func categoryTextsAreDistinct() {
        let names = DiceComboCategory.allCases.map(DiceComboText.name)
        let rules = DiceComboCategory.allCases.map(DiceComboText.rule)
        #expect(Set(names).count == 12)
        #expect(Set(rules).count == 12)
        #expect(DiceComboText.rule(.threes) == "3の目の合計")
    }
}
