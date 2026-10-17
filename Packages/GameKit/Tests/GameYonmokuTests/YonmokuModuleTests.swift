import Testing
import SwiftUI
@testable import Core
import CoreEngine
@testable import GameYonmoku
import CoreTestSupport
import GameKitTestSupport

@Suite("四目並べのモジュール")
@MainActor
struct YonmokuModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(YonmokuModule().id == YonmokuModel.gameID)
        #expect(HowToPlayGuide.yonmoku.gameID == YonmokuModule().id)
        #expect(HowToPlayGuide.all.contains(.yonmoku))
        // 勝敗しか残らないので順位表は持たない（五目並べ・オセロと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: YonmokuModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("表示名は一般名称の「四目並べ」、英語はローマ字。他社の商品名・商標マークを含めない（#1738 の権利チェック）")
    func displayName() {
        let module = YonmokuModule()
        #expect(module.title == "四目並べ")
        #expect(GameYonmoku.tr("四目並べ", language: .english) == "Yonmoku Narabe")
        #expect(!module.description.isEmpty)
        let guide = HowToPlayGuide.yonmoku
        let japanese = [module.title, module.description, guide.title, guide.hint] + guide.lines
            + guide.items.map(\.text) + guide.notes + YonmokuRuleSheet.rules.flatMap { [$0.0, $0.1] }
        let english = japanese.map { GameYonmoku.tr($0, language: .english) }
            + [Core.tr(guide.title, language: .english), Core.tr(guide.hint, language: .english)]
            + (guide.lines + guide.items.map(\.text) + guide.notes).map { Core.tr($0, language: .english) }
        for banned in ["®", "™", "公式", "ライセンス", "コネクト", "Connect", "connect", "CONNECT"] {
            #expect((japanese + english).allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = YonmokuModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(!module.hasResumableSnapshot(in: store), "開いただけの局は保存しない（#240）")
        model.tap(column: 3)
        #expect(module.hasResumableSnapshot(in: store), "盤が動いたら保存する")
        model.resign()
        #expect(!module.hasResumableSnapshot(in: store), "決着したら消す")
    }

    @Test("遊び方は図入りで、項目ごとに図が 1 つずつある（#2044）")
    func illustratedGuide() {
        let guide = HowToPlayGuide.yonmoku
        #expect(!guide.items.isEmpty)
        #expect(YonmokuHowToFigures.items.count == guide.items.count)
        let illustrated = guide.illustrated(YonmokuHowToFigures.items)
        #expect(illustrated.items.allSatisfy { $0.figure != nil })
    }

    @Test("くわしいルールに英語の訳がある")
    func englishRules() {
        for (title, body) in YonmokuRuleSheet.rules {
            #expect(GameYonmoku.tr(title, language: .english) != title)
            #expect(GameYonmoku.tr(body, language: .english) != body)
        }
    }

    @Test("画面は盤ゲームの共通部品（枠・操作列・結果カード・強さ選択・もう一回）を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameYonmoku")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("GameControlArea("))
        #expect(code.contains("GameReplayBar("), "「もう一回」は共通部品")
        #expect(code.contains("BoardGameResultCard("), "結果カードは盤ゲーム共通（#1753）")
        #expect(code.contains("CPUStrengthPicker("))
        #expect(code.contains("GameSetupSheet("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.yonmoku"))
        #expect(code.contains(".howToPlay(HowToPlayGuide.yonmoku.illustrated(YonmokuHowToFigures.items))"))
        #expect(code.contains("RuleListSheet("), "くわしいルールは共通部品")
        #expect(code.contains("BoardGameControlBar(model: model"), "待った・投了は Core の共通の操作列（広告救済込み・#828）")
        #expect(!code.contains("Rescue.request("), "救済の入口は Core の待ったボタンだけ")
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない（全画面の割り込み広告なし）")
        #expect(!code.contains("Interstitial") && !code.contains("interstitial"))
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(!code.contains("Image(\""), "絵はコードで描く（外部の画像を使わない）")
        #expect(code.contains(".task(id: model.aiTurnKey)"), "CPU は aiTurnKey で起動する（#140）")
        #expect(code.contains("withAITurnGuard("), "手番の照合は共通の定石（#531）")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(") && code.contains("gameDidProgress(")
                && code.contains("gameDidFinish("), "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("CPUStrength.analyticsLevel(forLevel:"), "選んだ強さを game_start に載せる（#500）")
        #expect(code.contains("RecordLabel(model.recordResult)"), "記録を出す")
        #expect(!code.contains("#if DEBUG\n        YonmokuModule"), "倉庫の出し分けにビルド条件を使わない")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameYonmoku/YonmokuModel.swift")
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
        let source = try SourceScan.packageSource("Sources/GameYonmoku/YonmokuView.swift")
        let start = try #require(source.range(of: "CPUStrengthPicker(level: $level, details: ["))
        let rest = source[start.upperBound...]
        let end = try #require(rest.range(of: "])"))
        let entries = rest[..<end.lowerBound].split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        #expect(entries.count == CPUStrength.allCases.count)
    }

    @Test("撮影用の局面は狙いどおり（中盤はあなたの番・3 つ並びは次で勝てる）")
    func debugScenarios() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.applyDebugScenario("midgame")
        #expect(!model.isAITurn && !model.gameOver && model.moveCount == 8)
        model.applyDebugScenario("threat")
        model.tap(column: 0)
        #expect(model.winner == .black)
    }
}

@Suite("四目並べの盤の寸法")
struct YonmokuLayoutTests {
    @Test("1 列のタップ領域は iPhone SE の幅でも 44pt 以上、横長の盤")
    func tapTargets() {
        // SE（幅 320 の旧機種でも）: 画面の左右の余白を引いた幅。盤は余白の半分まで広げている。
        let layout = YonmokuBoardLayout(width: 320 - 16)
        #expect(layout.cell >= 40)
        #expect(YonmokuBoardLayout(width: 375 - 16).cell >= 44)
        #expect(YonmokuBoardLayout.aspectRatio > 1)
        #expect(YonmokuBoardLayout(width: 0).cell == 0, "GeometryReader の最初の 0 幅でも落ちない")
    }

    @Test("マスの中心は下の段ほど下にあり、列は左から並ぶ")
    func centers() {
        let layout = YonmokuBoardLayout(width: 350)
        #expect(layout.center(col: 0, row: 0).y > layout.center(col: 0, row: 5).y)
        #expect(layout.center(col: 6, row: 0).x > layout.center(col: 0, row: 0).x)
        #expect(layout.dropDistance(row: 0) > layout.dropDistance(row: 5))
    }
}

@Suite("四目並べの読み上げ")
struct YonmokuAccessibilityTests {
    @Test("列は番号・下からの石・あと何個入るか・直前の手を読む")
    func columnLabels() {
        #expect(YonmokuAccessibility.columnLabel(col: 2, discs: [], isLastMove: false) == "3列目、空、あと6個入る")
        #expect(YonmokuAccessibility.columnLabel(col: 0, discs: [.black, .white], isLastMove: true)
                == "1列目、下から 黒・白、あと4個入る、直前の手")
        #expect(YonmokuAccessibility.columnLabel(col: 6, discs: Array(repeating: .black, count: 6), isLastMove: false)
                == "7列目、下から 黒・黒・黒・黒・黒・黒、満杯")
    }

    @Test("CPU の手は列と段を読む")
    func cpuAnnouncement() {
        #expect(YonmokuAccessibility.cpuMoveAnnouncement(col: 3, row: 0) == "CPUは4列目の下から1段目に入れました")
    }
}
