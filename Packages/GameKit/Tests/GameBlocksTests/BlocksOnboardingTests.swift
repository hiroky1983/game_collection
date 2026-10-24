import Core
import Foundation
import Testing
@testable import GameBlocks
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("ブロック崩し: はじめての遊び方")
struct BlocksOnboardingTests {
    private func field(_ rows: [String], speed: Double = 70) -> BlocksField {
        BlocksField(stage: BlocksStage(number: 1, rows: rows, ballSpeed: speed), speed: speed)
    }

    private func makePreference(_ suite: String) -> FeedbackPreference {
        let name = "asobiba.blocks.onboarding.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
    }

    /// 1 列目の真ん中のブロックへ下から当てる。
    private func hitCenter(_ f: inout BlocksField) -> [BlocksEvent] {
        let rect = BlocksField.blockRect(row: 0, column: 4)
        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        return f.step(dt: 0.02)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(BlocksOnboarding.guide.isWellFormed)
        #expect(BlocksOnboarding.guide.gameID == BlocksModel.gameID)
        #expect(BlocksOnboarding.guide.gameID == BlocksModule().id)
    }

    @Test("ブロックの種類の図: ふつうは 1 回・硬いのは 2 回で壊れ、灰色は何回当てても壊れない")
    func kindsFigure() {
        #expect(BlocksOnboarding.kinds == [.normal, .hard, .solid])
        for kind in BlocksOnboarding.kinds {
            var f = field(["....\(kind.symbol)...."])
            var hits = 0
            while f.block(row: 0, column: 4) != nil, hits < 10 {
                _ = hitCenter(&f)
                hits += 1
            }
            if let points = kind.hitPoints {
                #expect(hits == points, "\(kind) は \(points) 回で壊れる")
                #expect(BlocksOnboarding.label(for: kind) == tr("%lld 回で壊れる", points))
            } else {
                #expect(f.block(row: 0, column: 4)?.kind == kind, "\(kind) は 10 回当てても残る")
                #expect(BlocksOnboarding.label(for: kind) == tr("壊れない"))
            }
        }
        #expect(BlockKind.normal.hitPoints == 1 && BlockKind.hard.hitPoints == 2)
        #expect(BlocksOnboarding.colorHex(for: .solid) == BlocksPalette.solid)
        #expect(BlocksOnboarding.colorHex(for: .hard) == BlocksPalette.hardFull)
    }

    @Test("壊れないブロックが残っていても、壊せるブロックを全部消せばステージクリア")
    func solidDoesNotBlockClear() {
        var f = field(["...sns..."])
        #expect(!f.isCleared)
        _ = hitCenter(&f)
        #expect(f.isCleared)
        #expect(f.block(row: 0, column: 3)?.kind == .solid)
    }

    @Test("パドル: 動かす操作でパドルが動き（発射前は球も乗ったまま）、タップで球が上へ出る")
    func paddleAndLaunch() {
        let model = BlocksModel(services: nil, startingAt: 1, preference: makePreference("paddle"))
        model.movePaddle(to: 30)
        #expect(model.field.paddleX == 30)
        #expect(model.field.ball.x == 30, "発射前の球はパドルに乗って一緒に動く")
        #expect(model.phase == .ready)
        model.launch()
        #expect(model.phase == .playing)
        #expect(model.field.ball.vy > 0, "上へ飛び出す")
    }

    @Test("アイテム: パドルが伸びるのは 12 秒だけ、球は 3 個まで")
    func items() {
        #expect(BlocksRules.widePaddleDuration == 12)
        #expect(BlocksRules.maxBalls == 3)
        #expect(Set(BlocksItemKind.allCases) == [.widePaddle, .multiBall], "伸びる・増えるの 2 種だけ")
        let line = BlocksOnboarding.guide.pages[3].lines[1]
        #expect(line.contains("\(Int(BlocksRules.widePaddleDuration))") && line.contains("\(BlocksRules.maxBalls)"))
    }

    @Test("勝ち負け: 3 回ミスで終わり、全ステージをクリアしたら勝ち")
    func livesAndStages() {
        #expect(BlocksRules.initialLives == 3)
        #expect(BlocksRules.stageCount == 12)
        #expect(BlocksOnboarding.guide.pages[4].lines[2].contains("\(BlocksRules.stageCount)"))

        let model = BlocksModel(services: nil, startingAt: 1, preference: makePreference("lives"))
        for _ in 0..<BlocksRules.initialLives {
            #expect(model.phase != .gameOver)
            model.movePaddle(to: 5)
            model.launch()
            model.placeBallForTesting(x: 95, y: 6, vx: 0, vy: -60)
            for _ in 0..<60 where model.phase == .playing { model.tick(dt: 1.0 / 60) }
        }
        #expect(model.phase == .gameOver)

        let last = BlocksModel(services: nil, startingAt: BlocksRules.stageCount, preference: makePreference("last"))
        var guardCount = 0
        while !last.field.isCleared, guardCount < 4_000 {
            guardCount += 1
            if last.phase == .ready { last.launch() }
            guard last.phase == .playing else { break }
            guard let target = firstBreakable(last.field) else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            last.placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            last.tick(dt: 1.0 / 60)
        }
        #expect(last.phase == .allCleared)
    }

    @Test("球が増えているときは、全部落ちるまでミスにならない")
    func multiBallLossCountsOnlyWhenAllGone() {
        var f = field([".........", "........."])
        f.movePaddle(to: 10)
        f.placeBallsForTesting([
            BlocksBall(x: 90, y: 8, vx: 0, vy: -70),
            BlocksBall(x: 50, y: 60, vx: 0, vy: 70),
        ])
        let first = f.step(dt: 0.3)
        #expect(!first.contains(.ballLost), "1 個落ちただけではミスにならない")
        #expect(f.balls.count == 1)
        f.placeBall(x: 90, y: 8, vx: 0, vy: -70)
        #expect(f.step(dt: 0.3).contains(.ballLost), "最後の 1 個が落ちたらミス")
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let figureTexts = ["%lld 回で壊れる", "壊れない", "指を横に動かす", "タップで発射", "アイテムを受ける",
                           "伸びる・球が増える", "球を落とすと 1 ミス", "3 回で終わり"]
        for text in BlocksOnboarding.guide.texts + figureTexts {
            #expect(GameBlocks.tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
        #expect(GameBlocks.tr("%lld 回で壊れる", 1, language: .english) == "Breaks in 1 hit")
        #expect(GameBlocks.tr("%lld 回で壊れる", 2, language: .english) == "Breaks in 2 hits")
    }

    private func firstBreakable(_ field: BlocksField) -> (row: Int, column: Int)? {
        for row in 0..<field.rowCount {
            for column in 0..<BlocksField.Metrics.columns
            where field.block(row: row, column: column)?.isBreakable == true {
                return (row, column)
            }
        }
        return nil
    }
}
