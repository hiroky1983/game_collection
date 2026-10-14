import Testing
import Core
import CoreEngine
@testable import GameAkariKeshi
import CoreTestSupport
import GameKitTestSupport

@Suite("明かり消しパズルのモジュール")
@MainActor
struct AkariKeshiModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じで、game_id は英字")
    func idsMatch() {
        #expect(AkariKeshiModule().id == "akarikeshi")
        #expect(AkariKeshiModule().id == AkariKeshiModel.gameID)
        #expect(HowToPlayGuide.akariKeshi.gameID == AkariKeshiModule().id)
        #expect(HowToPlayGuide.all.contains(.akariKeshi))
        #expect(AkariKeshiModule().resumesFromSnapshot)
        // 記録は最少手数（難易度ごと）なので順位表には送らない（15パズルと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: AkariKeshiModule().id, outcome: .win,
            score: GameScore(metric: .fewestMoves, seconds: 30, moves: 4, variant: "easy")
        ) == nil)
    }

    @Test("記録の区分名は共通の表から引け、保存する名前は日本語")
    func recordVariantLabels() {
        for difficulty in AkariKeshiDifficulty.allCases {
            let key = "akarikeshi#\(difficulty.rawValue)"
            #expect(RecordVariantLabels.label(recordKey: key, language: .japanese) == difficulty.label(language: .japanese))
            #expect(RecordVariantLabels.label(recordKey: key, language: .english) == difficulty.label(language: .english))
            #expect(difficulty.recordVariantLabel == difficulty.label(language: .japanese))
        }
        #expect(RecordVariantLabels.label(recordKey: "akarikeshi#unknown") == nil)
    }

    @Test("表示名・説明・ルールに他社の商標（ライツアウト / Lights Out）を使わない（Issue #1883 の権利チェック）")
    func noTrademarkedWords() {
        let module = AkariKeshiModule()
        #expect(module.title == "明かり消しパズル")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.akariKeshi
        let texts = [module.title, module.description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes
            + [GameAkariKeshi.tr("明かり消しパズル", language: .english),
               GameAkariKeshi.tr("押したマスと上下左右の明かりが入れ替わる。全部消せばクリア", language: .english)]
        // 「Lights Out」は 1995 年の Tiger Electronics の玩具名。日本の登録状況を確かめきれないので安全側で使わない。
        // 「Akari / 美術館」はニコリのパズル名なので、英語名・ID に「Akari」単独も使わない（ID はローマ字の akarikeshi）。
        for banned in ["ライツアウト", "ライツ・アウト", "Lights Out", "LIGHTS OUT", "lights out", "Lights-Out",
                       "Light Up", "美術館", "ニコリ", "公式", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・計時の止め方を使い、広告は共通のバナーだけ")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameAkariKeshi")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("GameControlArea("))
        #expect(code.contains("ladder: ladder") && code.contains("DifficultyLadderPrompt("), "難易度の階段を枠へ渡す")
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.akariKeshi"))
        #expect(code.contains("GameSetupSheet(") && code.contains("GameSetupChooser("), "難易度のシートは共通枠から組む")
        #expect(code.contains(".gameTimerLifecycle("), "背面・画面離脱で計時を止める")
        #expect(code.contains(".gameClearCard("), "クリアは共通のカードで示す")
        #expect(code.contains("RecordLabel("))
        #expect(!code.contains("RewardedRescue("), "広告の救済は持たない（Issue #1883 はヒントも広告も入れない）")
        #expect(!code.contains("showRewardedAd(") && !code.contains("showInterstitial"), "広告の追加は無い")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains("level: difficulty.analyticsLevel"), "難易度を持つので game_start に level を載せる")
        #expect(code.contains("gameDidRestart(") && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 プレイ 1 組 + 進行の 3 点で接続する")
        #expect(code.contains(".accessibilityAddTraits(.isButton)") && code.contains(".accessibilityAction"),
                "マスはボタンとして読み、VoiceOver から押せる")
        #expect(!code.contains("Image(\"") && !code.contains("UIImage(") && !code.contains("AsyncImage("),
                "絵はコード描画と SF Symbols だけ（外部の画像を使わない）")
    }

    @Test("ハブへの登録行はコメントアウトのまま（企画倉庫）")
    func registryLineIsCommentedOut() throws {
        let source = try String(contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"),
                                encoding: .utf8)
        #expect(source.contains("// AkariKeshiModule(),"))
        let code = SourceScan.strippingComments(source)
        #expect(!code.contains("AkariKeshiModule()"), "倉庫のゲームをハブに並べている")
        #expect(source.contains("企画倉庫・#1883"))
    }
}

@Suite("明かり消しパズルの読み上げ")
struct AkariKeshiAccessibilityTests {
    @Test("マスは行・列と点灯 / 消灯を語で読む（色だけで伝えない）")
    func cellLabels() {
        #expect(AkariKeshiAccessibility.cellLabel(index: 0, isLit: true) == "1行1列、点灯")
        #expect(AkariKeshiAccessibility.cellLabel(index: 7, isLit: false) == "2行3列、消灯")
        #expect(AkariKeshiAccessibility.cellLabel(index: 24, isLit: true) == "5行5列、点灯")
        #expect(AkariKeshiAccessibility.boardSummary(litCount: 0) == "明かりはすべて消えています")
        #expect(AkariKeshiAccessibility.boardSummary(litCount: 3) == "点灯しているマス、3個")
    }
}

@Suite("明かり消しパズル: 英語の文言")
struct AkariKeshiLocalizationTests {
    @Test("表示名・難易度・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameAkariKeshi.tr("明かり消しパズル", language: .english) == "Lamps Off Puzzle")
        #expect(AkariKeshiDifficulty.hard.label(language: .english) == "Hard")
        #expect(GameAkariKeshi.tr("最短%lld手", 1, language: .english) == "Best possible: 1 move")
        #expect(GameAkariKeshi.tr("最短%lld手", 7, language: .english) == "Best possible: 7 moves")
        #expect(GameAkariKeshi.tr("%1$lld行%2$lld列、点灯", 2, 3, language: .english) == "Row 2, column 3, lit")
    }
}
