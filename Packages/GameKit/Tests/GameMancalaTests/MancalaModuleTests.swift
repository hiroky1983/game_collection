import Testing
import SwiftUI
import Core
import CoreEngine
@testable import GameMancala
import CoreTestSupport
import GameKitTestSupport

@Suite("マンカラのモジュール")
@MainActor
struct MancalaModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(MancalaModule().id == MancalaModel.gameID)
        #expect(HowToPlayGuide.mancala.gameID == MancalaModule().id)
        #expect(HowToPlayGuide.all.contains(.mancala))
        // 勝敗しか残らないので順位表は持たない（オセロ・バックギャモンと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: MancalaModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("表示名は一般名の「マンカラ」。商品名・商標マーク・他社名を含めない（Issue #1626 の権利チェック）")
    func displayName() {
        let module = MancalaModule()
        #expect(module.title == "マンカラ")
        #expect(GameMancala.tr("マンカラ", language: .english) == "Mancala")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.mancala
        let texts = [module.title, module.description, guide.title, guide.hint] + guide.lines
            + guide.items.map(\.text) + guide.notes + MancalaRuleSheet.rules.flatMap { [$0.0, $0.1] }
        for banned in ["®", "™", "公式", "ライセンス", "カラハ", "Kalah", "Kalaha"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = MancalaModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(!module.hasResumableSnapshot(in: store), "開いただけの局は保存しない（#240）")
        model.tap(pit: 0)
        #expect(module.hasResumableSnapshot(in: store), "盤が動いたら保存する")
        model.resign()
        #expect(!module.hasResumableSnapshot(in: store), "決着したら消す")
    }

    @Test("遊び方は図入りで、項目ごとに図が 1 つずつある（#2044）")
    func illustratedGuide() {
        let guide = HowToPlayGuide.mancala
        #expect(!guide.items.isEmpty)
        #expect(MancalaHowToFigures.items.count == guide.items.count)
        let illustrated = guide.illustrated(MancalaHowToFigures.items)
        #expect(illustrated.items.allSatisfy { $0.figure != nil })
        #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
    }

    /// 遊び方（Core の表）の英語は `HowToPlayLocalizationTests` が `all` の全部について見る。
    @Test("くわしいルールに英語の訳がある")
    func englishRules() {
        for (title, body) in MancalaRuleSheet.rules {
            #expect(GameMancala.tr(title, language: .english) != title)
            #expect(GameMancala.tr(body, language: .english) != body)
        }
    }

    @Test("画面は共通の枠・操作エリア・Core の待った・図入りの「？」を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameMancala")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("GameControlArea("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.mancala"))
        #expect(code.contains(".howToPlay(HowToPlayGuide.mancala.illustrated(MancalaHowToFigures.items))"))
        #expect(code.contains("RuleListSheet("), "くわしいルールは共通部品")
        #expect(code.contains("BoardGameControlBar(model: model"), "待った・投了は Core の共通の操作列（広告救済込み・#828）")
        #expect(!code.contains("Rescue.request("), "救済の入口は Core の待ったボタンだけ")
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\""), "絵はコードで描く（外部の画像を使わない）")
        #expect(code.contains(".task(id: model.aiTurnKey)"), "CPU は aiTurnKey で起動する（#140）")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(") && code.contains("gameDidProgress(")
                && code.contains("gameDidFinish("), "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("CPUStrength.analyticsLevel(forLevel:"), "選んだ強さを game_start に載せる（#500）")
        #expect(code.contains("BoardGameResultCard(") && code.contains("record: model.recordResult"), "決着のカードに記録を出す（共通の結果カード・#3059）")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameMancala/MancalaModel.swift")
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
        #expect(!release.contains("applyDebugScenario") && !release.contains("configureForTesting"))
        #expect(release.contains("public func newGame("), "走査そのものが機能している")
    }

    @Test("開始シートの説明は CPU の段階数と同じ 4 つ")
    func strengthDetails() throws {
        let source = try SourceScan.packageSource("Sources/GameMancala/MancalaView.swift")
        let start = try #require(source.range(of: "CPUStrengthPicker(level: $level, details: ["))
        let rest = source[start.upperBound...]
        let end = try #require(rest.range(of: "])"))
        let entries = rest[..<end.lowerBound].split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        #expect(entries.count == CPUStrength.allCases.count)
    }

    @Test("撮影用の局面は種が 48 個で、狙った手が打てる")
    func debugScenarios() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        model.applyDebugScenario("capture")
        #expect(MancalaRules.isConsistent(model.board))
        model.tap(pit: 0)
        #expect(model.lastEvent?.captured == 6)
        model.applyDebugScenario("endgame")
        #expect(MancalaRules.isConsistent(model.board) && !model.gameOver)
    }
}

@Suite("マンカラの盤の寸法")
struct MancalaLayoutTests {
    @Test("幅は穴 8 つぶん + 隙間 9 つで割り切れ、縦横比は横長")
    func layout() {
        let layout = MancalaBoardLayout(width: 360)
        #expect(abs(layout.pit * 8 + layout.gap * 9 - 360) < 0.001)
        #expect(MancalaBoardLayout.aspectRatio > 2)
    }
}

@Suite("マンカラの読み上げ")
struct MancalaAccessibilityTests {
    @Test("穴は持ち主・画面の左からの番号・種の数・まけるか・直前の手を読む")
    func pitLabels() {
        #expect(MancalaAccessibility.pitLabel(side: .south, column: 2, seeds: 4, isPlayable: true, isLastMove: false)
                == "あなたの穴 3、種 4個、まけます")
        #expect(MancalaAccessibility.pitLabel(side: .north, column: 0, seeds: 0, isPlayable: false, isLastMove: true)
                == "CPUの穴 1、種 0個、直前にまいた穴")
    }

    @Test("ストアは持ち主と種の数を読む")
    func storeLabels() {
        #expect(MancalaAccessibility.storeLabel(side: .south, seeds: 12) == "あなたのストア、種 12個")
        #expect(MancalaAccessibility.storeLabel(side: .north, seeds: 3) == "CPUのストア、種 3個")
    }
}
