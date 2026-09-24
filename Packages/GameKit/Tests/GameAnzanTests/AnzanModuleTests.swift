import Testing
import Core
import CoreEngine
@testable import GameAnzan
import CoreTestSupport
import GameKitTestSupport

@Suite("ぱっと暗算のモジュール")
@MainActor
struct AnzanModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(AnzanModule().id == AnzanModel.gameID)
        #expect(HowToPlayGuide.anzan.gameID == AnzanModule().id)
        #expect(HowToPlayGuide.all.contains(.anzan))
        // 記録は正誤と連続正解（区分あり）なので順位表は持たない（いろリレー・大富豪と同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: AnzanModule().id, outcome: .win,
            score: GameScore(metric: .winLoss, seconds: 3, variant: "d1-n5-slow")
        ) == nil)
    }

    @Test("表示名・説明・ルールに他社の登録商標を含めない（Issue #1321 の権利チェック）")
    func noTrademarkedWords() {
        let module = AnzanModule()
        #expect(module.title == "ぱっと暗算")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description]
            + HowToPlayGuide.anzan.lines + [HowToPlayGuide.anzan.title, HowToPlayGuide.anzan.hint]
        // 「フラッシュ暗算」は登録第4801121号（株式会社グリーン・フィールド・第9類/第41類）。
        // 「フラッシュ」だけでも同社の「ダブル/カケ/ワリフラッシュ暗算」と紛れるので使わない。
        for banned in ["フラッシュ", "Flash", "flash", "FLASH", "グリーン・フィールド", "公式", "®", "™"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・局ガード付きの救済を使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameAnzan")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.anzan"))
        #expect(code.contains("GameSetupSheet(") && code.contains("GameSetupChooser("), "難易度のシートは共通枠から組む")
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1, "救済の入口は見直しの 1 面だけ")
        #expect(code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains("model.replayAfterAd(forGame:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(code.contains(".rewardOffer(replayRescue, for: .hint, isPresented: model.canReplay"))
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains("level: settings.analyticsLevel"), "難易度を持つので game_start に level を載せる")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 問 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("gameWillNotResume("), "中断データは難易度の控えなので休憩扱いを打ち消す")
        #expect(!code.contains("Timer.") && !code.contains("DispatchQueue"), "時間は Model が返す待ち時間を .task で待つだけ")
        #expect(code.contains(".task(id: model.displayRun)"), "表示の並びは displayRun を鍵に回し直す")
        #expect(code.contains("Task.sleep(for: wait)"))
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameAnzan/AnzanModel.swift")
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
        #expect(!release.contains("isFrozenForCapture"))
        #expect(release.contains("public func submit()"), "走査そのものが機能している")
    }

    @Test("テンキーは 0〜9・消す・決定の 12 キーで、決定は入力があるときだけ押せる")
    func keypadKeys() {
        let model = AnzanModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: 1)
        model.start(.standard)
        while model.advanceDisplay() != nil {}
        #expect(!model.canSubmit)
        model.tapDigit(4)
        #expect(model.canSubmit)
        let keys: [AnzanKey] = (0...9).map { .digit($0) } + [.backspace, .submit]
        #expect(Set(keys).count == 12)
        #expect(Set(keys.map(AnzanAccessibility.keyLabel)).count == 12, "読み上げが重複しない")
    }
}
