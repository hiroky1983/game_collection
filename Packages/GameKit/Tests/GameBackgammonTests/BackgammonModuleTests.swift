import Testing
import CoreGraphics
import Core
import CoreEngine
@testable import GameBackgammon
import CoreTestSupport
import GameKitTestSupport

@Suite("バックギャモンのモジュール")
@MainActor
struct BackgammonModuleTests {
    @Test("登録口の ID と Model の gameID・遊び方ガイドは同じ")
    func idsMatch() {
        #expect(BackgammonModule().id == BackgammonModel.gameID)
        #expect(HowToPlayGuide.backgammon.gameID == BackgammonModule().id)
        #expect(HowToPlayGuide.all.contains(.backgammon))
        // 勝敗しか残らないので順位表は持たない（オセロと同じ）。
        #expect(GameCenterLeaderboard.score(
            gameID: BackgammonModule().id, outcome: .win, score: GameScore(metric: .winLoss)
        ) == nil)
    }

    @Test("表示名は「バックギャモン」。商標マークや他社名を含めない（Issue #1322 の権利チェック）")
    func displayName() {
        let module = BackgammonModule()
        #expect(module.title == "バックギャモン")
        #expect(!module.description.isEmpty)
        let texts = [module.title, module.description] + HowToPlayGuide.backgammon.lines
            + [HowToPlayGuide.backgammon.title, HowToPlayGuide.backgammon.hint]
        for banned in ["®", "™", "公式", "ライセンス"] {
            #expect(texts.allSatisfy { !$0.contains(banned) }, "「\(banned)」を含む文言がある")
        }
    }

    @Test("中断データがあるあいだだけ「続きから」になる")
    func resumableSnapshot() async {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let module = BackgammonModule()
        #expect(!module.hasResumableSnapshot(in: store))
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ（オープニングロールだけ）の局は保存しない（#240）")
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        #expect(!module.hasResumableSnapshot(in: store), "局面を差し替えただけでは保存しない")
        model.tap(7); model.tap(4)
        #expect(module.hasResumableSnapshot(in: store), "盤が動いたら保存する")
        model.resign()
        #expect(!module.hasResumableSnapshot(in: store), "決着したら消す")
    }

    @Test("画面は共通の枠・操作エリア・Core の待ったボタンを使い、素のアニメーションを書いていない")
    func viewUsesSharedParts() throws {
        let source = try SourceScan.moduleSources("GameBackgammon")
        let code = SourceScan.strippingComments(source)
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("GameControlArea("))
        #expect(code.contains("BannerSlot("))
        #expect(code.contains("HowToPlayHint(.backgammon"))
        #expect(code.contains("BoardUndoButton(model: model"), "待ったは Core の共通ボタン（広告救済込み・#828）")
        #expect(code.contains("BoardResignButton("))
        #expect(code.contains("boardResignConfirmation("))
        #expect(!code.contains("Rescue.request("), "救済の入口は Core の待ったボタンだけ")
        #expect(!code.contains("showRewardedAd("), "広告は RewardedRescue 経由でしか出さない")
        #expect(!code.contains("withAnimation("), "アニメーションは gameAnimation 経由")
        #expect(code.contains(".task(id: model.aiTurnKey)"), "CPU は aiTurnKey で起動する（#140）")
        #expect(code.contains("onChange(of: model.mustPass, initial: true)"), "パス案内は復元後も出る（#414）")
        #expect(code.contains("gameDidStart(") && code.contains("gameDidRestart(") && code.contains("gameDidProgress(")
                && code.contains("gameDidFinish("), "解析は 1 ゲーム 1 組 + 進行の 3 点で接続する")
        #expect(code.contains("CPUStrength.analyticsLevel(forLevel:"), "選んだ強さを game_start に載せる（#500）")
    }

    @Test("撮影用の経路は Release に残っていない")
    func debugScenarioIsDebugOnly() throws {
        let source = try SourceScan.packageSource("Sources/GameBackgammon/BackgammonModel.swift")
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
        let source = try SourceScan.packageSource("Sources/GameBackgammon/BackgammonView.swift")
        let picker = SourceScan.declaration(of: "CPUStrengthPicker(level: $level, details: [", in: source) ?? ""
        _ = picker
        let start = try #require(source.range(of: "CPUStrengthPicker(level: $level, details: ["))
        let rest = source[start.upperBound...]
        let end = try #require(rest.range(of: "])"))
        let entries = rest[..<end.lowerBound].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        #expect(entries.count == CPUStrength.allCases.count)
    }
}

@Suite("バックギャモンの盤の寸法")
struct BackgammonLayoutTests {
    @Test("タップ位置 → ポイントの対応: 下段は右から 1〜12、上段は左から 13〜24、中央がバー、右端があがり")
    func hitTesting() {
        let layout = BackgammonBoardLayout(width: 340)
        let u = layout.unit
        #expect(layout.point(at: CGPoint(x: u * 0.5, y: layout.height - 1)) == 11)   // 左下 = 12 ポイント
        #expect(layout.point(at: CGPoint(x: u * 0.5, y: 1)) == 12)                   // 左上 = 13 ポイント
        #expect(layout.point(at: CGPoint(x: layout.trayMinX - 1, y: layout.height - 1)) == 0)  // 右下 = 1 ポイント
        #expect(layout.point(at: CGPoint(x: layout.trayMinX - 1, y: 1)) == 23)                 // 右上 = 24 ポイント
        #expect(layout.point(at: CGPoint(x: (layout.barMinX + layout.barMaxX) / 2, y: layout.height / 2)) == BackgammonBoard.bar)
        #expect(layout.point(at: CGPoint(x: layout.width - 1, y: layout.height / 2)) == BackgammonBoard.off)
        #expect(layout.point(at: CGPoint(x: -1, y: 1)) == nil)
        // 描画位置と逆写像が一致する。
        for index in 0..<24 {
            let (_, isTop) = layout.position(of: index)
            let p = CGPoint(x: layout.centerX(of: index), y: isTop ? 5 : layout.height - 5)
            #expect(layout.point(at: p) == index, "index \(index)")
        }
    }

    @Test("駒 5 個を積んでも上下の列が重ならない")
    func stacksDoNotOverlap() {
        let layout = BackgammonBoardLayout(width: 340)
        let top = layout.checkerCenterY(k: 4, isTop: true) + layout.checkerDiameter / 2
        let bottom = layout.checkerCenterY(k: 4, isTop: false) - layout.checkerDiameter / 2
        #expect(bottom - top > layout.unit * 0.5)
    }

    @Test("使った目の印: ゾロ目は先頭から、2 個の目は値で照合する")
    func usedFlags() {
        #expect(BackgammonDiceLayout.usedFlags(dice: [5, 3], remaining: [3]) == [true, false])
        #expect(BackgammonDiceLayout.usedFlags(dice: [5, 3], remaining: [5, 3]) == [false, false])
        #expect(BackgammonDiceLayout.usedFlags(dice: [4, 4, 4, 4], remaining: [4, 4]) == [true, true, false, false])
        #expect(BackgammonDiceLayout.usedFlags(dice: [4, 4, 4, 4], remaining: []) == [true, true, true, true])
        for v in 1...6 { #expect(BackgammonDiceLayout.pips(v).count == v) }
    }
}

@Suite("バックギャモンの読み上げ")
struct BackgammonAccessibilityTests {
    @Test("ポイントの読み上げは番号・持ち主と数・選択と行き先")
    func pointLabels() {
        #expect(BackgammonAccessibility.pointLabel(index: 5, owner: .white, count: 5, isMovable: true, isSelected: false, isDestination: false)
                == "6ポイント、あなたの駒5個、動かせます")
        #expect(BackgammonAccessibility.pointLabel(index: 0, owner: .black, count: 2, isMovable: false, isSelected: false, isDestination: false)
                == "1ポイント、CPUの駒2個")
        #expect(BackgammonAccessibility.pointLabel(index: 4, owner: nil, count: 0, isMovable: false, isSelected: false, isDestination: true)
                == "5ポイント、空、ここへ動かせます")
        #expect(BackgammonAccessibility.pointLabel(index: 7, owner: .white, count: 3, isMovable: true, isSelected: true, isDestination: false)
                == "8ポイント、あなたの駒3個、選択中")
    }

    @Test("バー・あがり・サイコロの読み上げ")
    func otherLabels() {
        #expect(BackgammonAccessibility.barLabel(humanCount: 0, cpuCount: 0, isMovable: false, isSelected: false) == "バー、空")
        #expect(BackgammonAccessibility.barLabel(humanCount: 1, cpuCount: 2, isMovable: true, isSelected: false) == "バー、あなたの駒1個、CPUの駒2個、動かせます")
        #expect(BackgammonAccessibility.offLabel(humanCount: 3, cpuCount: 0, isDestination: true) == "あがり、あなた3個、CPU0個、ここへあがれます")
        #expect(BackgammonAccessibility.diceLabel(dice: [5, 3], remaining: [3]) == "サイコロ 5と3、残り 3")
        #expect(BackgammonAccessibility.diceLabel(dice: [4, 4, 4, 4], remaining: []) == "サイコロ 4のゾロ目、使い切りました")
        #expect(BackgammonAccessibility.diceLabel(dice: [], remaining: []) == "サイコロはまだ振っていません")
    }
}
