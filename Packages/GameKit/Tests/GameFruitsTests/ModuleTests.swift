import Testing
import Core
import CoreEngine
@testable import GameFruits
import CoreTestSupport
import GameKitTestSupport

@Suite("くっつきフルーツのモジュール")
@MainActor
struct ModuleTests {
    @Test("登録口の ID と Model の gameID は同じ")
    func idsMatch() {
        #expect(FruitsModule().id == FruitsModel.gameID)
        #expect(HowToPlayGuide.fruits.gameID == FruitsModule().id)
        let mapped = GameCenterLeaderboard.score(
            gameID: FruitsModule().id, outcome: .loss, score: GameScore(metric: .points, points: 1)
        )
        #expect(mapped?.leaderboardID == GameCenterLeaderboard.fruitsScore)
        #expect(GameCenterLeaderboard.score(
            gameID: FruitsModule().id, outcome: .loss,
            score: GameScore(metric: .points, points: 1, isLeaderboardEligible: false)
        ) == nil, "コンティニューを使った回は順位表に載せない")
    }

    @Test("表示名・説明・アイコンがある")
    func hasMetadata() {
        let module = FruitsModule()
        #expect(module.title == "くっつきフルーツ")
        #expect(!module.description.isEmpty)
        // 商標登録済みの名称（Issue #1319 の権利面の注意）を表示名にも説明にも含めない。
        for banned in ["スイカゲーム", "Suika"] {
            #expect(!module.title.contains(banned))
            #expect(!module.description.contains(banned))
            #expect(!HowToPlayGuide.fruits.lines.joined().contains(banned))
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = FruitsModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = FruitsModel(services: services, seed: 1)
        #expect(!module.hasResumableSnapshot(in: store), "落とす前は続きが無い")
        model.drop()
        #expect(module.hasResumableSnapshot(in: store))
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store))
    }

    @Test("画面は共通の枠・レコメンド枠・広告コンティニューの幕を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameFruits")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationArea("))
        #expect(code.contains("RewardedContinueOverlay("))
        #expect(code.contains("model.continueAfterAd(forGame:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(!code.contains("SKPhysicsBody"), "物理エンジンは使わない（アクション枠の基盤規約）")
        #expect(!code.contains("withAnimation("), "アニメーションは withGameAnimation 経由")
        #expect(!code.contains("level: "), "難易度は持たないので game_start に level を載せない")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameFruits/FruitsModel.swift")
        #expect(source.contains("func applyDebugScenario("))
        // `#if DEBUG` の中だけにある = 行を評価して Release 側に残る行を取り出すと消える。
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
        #expect(!release.contains("placeFruitForTesting"))
        #expect(release.contains("public func tick(dt: Double)"), "走査そのものが機能している")
    }
}
