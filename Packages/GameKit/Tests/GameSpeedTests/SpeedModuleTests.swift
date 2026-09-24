import Testing
import Core
import CoreEngine
@testable import GameSpeed
import CoreTestSupport
import GameKitTestSupport

private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
    SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

@Suite("スピードのモジュール")
@MainActor
struct SpeedModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(SpeedModule().id == SpeedModel.gameID)
        #expect(HowToPlayGuide.speed.gameID == SpeedModule().id)
        #expect(HowToPlayGuide.all.contains(.speed))
        // 記録は勝敗・連勝・最速（速さの区分あり）なので順位表は持たない（ぱっと暗算・いろリレーと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: SpeedModule().id, outcome: .win,
            score: GameScore(metric: .winLoss, seconds: 30, variant: "normal")
        ) == nil)
        #expect(!SpeedModule().resumesFromSnapshot, "中断データは速さの控えで、ゲームは復元しない")
    }

    @Test("表示名・説明・ルールに他社の登録商標や公式を思わせる語を含めない（Issue #1323 の権利チェック）")
    func noTrademarkedWords() {
        let module = SpeedModule()
        #expect(module.title == "スピード")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description]
            + HowToPlayGuide.speed.lines + [HowToPlayGuide.speed.title, HowToPlayGuide.speed.hint]
            + SpeedRuleSheet.rules.flatMap { [$0.0, $0.1] }
        // 「スピード」自体は伝統的トランプゲームの一般名称（文字商標 0 件・2026-09-24 patent-i.com）。
        // 他社製品名や公式を思わせる語だけを禁じる。
        for banned in ["公式", "ライセンス", "®", "™", "Online", "オンライン"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("画面は共通の枠・レコメンド枠・局ガード付きの救済を使い、時間は Model が返す待ちを .task で待つだけ")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameSpeed")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("RecommendationSlot("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.speed"))
        #expect(code.contains("GameSetupSheet(") && code.contains("GameSetupChooser("), "速さのシートは共通枠から組む")
        #expect(code.components(separatedBy: "Rescue.request(").count - 1 == 1, "救済の入口はタイムの 1 面だけ")
        #expect(code.contains("guardedBy: .checkedByGrant"))
        #expect(code.contains("model.grantTimeoutAfterAd(forGame:"))
        #expect(code.contains("unavailable: RewardUnavailableAlert("))
        #expect(code.contains(".rewardOffer(timeoutRescue, for: .revival, isPresented: model.canUseTimeout"))
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains("level: settings.level.analyticsLevel"), "速さを持つので game_start に level を載せる")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(")
                && code.contains("gameDidProgress(") && code.contains("gameDidFinish("),
                "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("gameWillNotResume("), "中断データは速さの控えなので休憩扱いを打ち消す")
        #expect(!code.contains("Timer.") && !code.contains("DispatchQueue"), "時間は Model が返す待ちを .task で待つだけ")
        #expect(!code.contains("AITurnGuarded"), "手番が無いので順番制の定石は使わない（Issue #1323）")
        #expect(code.contains(".task(id: model.cpuRun)"), "CPU の待ちは cpuRun を鍵に組み直す")
        #expect(code.contains("Task.sleep(for: wait)"))
        #expect(code.contains("model.cpuRun == run"), "番号が変わったら古いループは抜ける（同じ場で 2 度動かない）")
        #expect(code.contains("PlayingCardSurface(") && code.contains("PlayingCardFace("), "札はトランプ共通基盤（#397）で描く")
        #expect(code.contains(".actionSlowMode"), "設定の「ゆっくりモード」（アクション枠共通）を CPU の反応に掛ける")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameSpeed/SpeedModel.swift")
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
        #expect(release.contains("public func nextCPUWait()"), "走査そのものが機能している")
    }

    @Test("手札 4 枚と山札は iPhone SE の幅に収まり、札は 44pt 以上の押し幅を持つ")
    func handFits() {
        #expect(SpeedHandLayout.fits(screenWidth: 375))
        #expect(PlayingCardMetrics.standard.width >= 44)
        #expect(PlayingCardMetrics.standard.height >= 44)
    }
}

@Suite("スピードの読み上げ")
struct SpeedAccessibilityTests {
    @Test("札の呼び名はマーク + 数字で、記号のまま読ませない")
    func cardNames() {
        #expect(SpeedAccessibility.cardName(card(.hearts, 5)) == "ハートの5")
        // 絵札は共通基盤（`PlayingCardFigure.spokenLabel`）の読み（K / A）に揃える（大富豪・ポーカーと同じ）。
        #expect(SpeedAccessibility.cardName(card(.spades, 13)) == "スペードのK")
        #expect(SpeedAccessibility.cardName(card(.diamonds, 1)) == "ダイヤのA")
        for c in SpeedCard.makeDeck() {
            #expect(SpeedAccessibility.cardName(c).rangeOfCharacter(from: .symbols) == nil, "\(c)")
        }
    }

    @Test("手札の読み上げは選択中と出せる / 出せないを文字で足す")
    func handLabels() {
        let c = card(.hearts, 5)
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: false, isPlayable: true) == "ハートの5、出せます")
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: true, isPlayable: true) == "ハートの5、選択中、出せます")
        #expect(SpeedAccessibility.handCardLabel(c, isSelected: false, isPlayable: false) == "ハートの5、いまは出せません")
    }

    @Test("台札・山札・CPU の手札の読み上げ")
    func tableLabels() {
        #expect(SpeedAccessibility.pileLabel(index: 0, top: card(.spades, 7)) == "左の台札、スペードの7")
        #expect(SpeedAccessibility.pileLabel(index: 1, top: nil) == "右の台札、まだ札はありません")
        #expect(SpeedAccessibility.stockLabel(of: .human, count: 12) == "あなたの山札、残り12枚")
        #expect(SpeedAccessibility.stockLabel(of: .cpu, count: 0) == "CPUの山札、なし")
        #expect(SpeedAccessibility.cpuHandLabel([card(.spades, 3), card(.clubs, 9)], stockCount: 4)
                == "CPUの手札、スペードの3、クラブの9。CPUの山札、残り4枚")
    }

    @Test("進行の 1 行は局面ごとに変わる")
    func statusLabels() {
        #expect(SpeedAccessibility.statusLabel(phase: .idle, isStuck: false, hasSelection: false, winner: nil, isDraw: false)
                == "速さを選んで始めましょう")
        #expect(SpeedAccessibility.statusLabel(phase: .playing, isStuck: true, hasSelection: false, winner: nil, isDraw: false)
                == "どちらも出せません。めくってください")
        #expect(SpeedAccessibility.statusLabel(phase: .playing, isStuck: false, hasSelection: true, winner: nil, isDraw: false)
                == "どちらの台札に置くか選んでください")
        #expect(SpeedAccessibility.statusLabel(phase: .result, isStuck: false, hasSelection: false, winner: .human, isDraw: false)
                == "あなたの勝ち")
        #expect(SpeedAccessibility.statusLabel(phase: .result, isStuck: false, hasSelection: false, winner: nil, isDraw: true)
                == "引き分け")
    }
}
