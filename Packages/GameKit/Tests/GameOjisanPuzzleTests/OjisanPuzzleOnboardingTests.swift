import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameOjisanPuzzle

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("おじさんの荷物運びパズル: はじめての遊び方")
struct OjisanPuzzleOnboardingTests {
    /// 図の小さな盤（7 段 × 6 列）を、本番の盤（12 段）の下に置く。
    private func padded(_ grid: [[Int]]) -> [[Int]] {
        let top = OjisanPuzzleBoard.rows - grid.count
        return Array(repeating: Array(repeating: 0, count: OjisanPuzzleBoard.columns), count: top) + grid
    }

    /// 決着するか、落下中の組が出るまで後片付けを進める。
    private func settle(_ model: OjisanPuzzleModel) {
        for _ in 0..<40 where model.outcome == nil && model.current == nil {
            model.tick(elapsed: OjisanPuzzleModel.settleInterval)
        }
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まり、モードで目的と決まりだけが変わる")
    func wellFormed() {
        for mode in OjisanPuzzleMode.allCases {
            let guide = OjisanPuzzleOnboarding.guide(mode: mode)
            #expect(guide.isWellFormed, "\(mode)")
            #expect(guide.gameID == OjisanPuzzleModel.gameID)
            #expect(guide.gameID == OjisanPuzzleModule().id)
        }
        let backpain = OjisanPuzzleOnboarding.guide(mode: .backpain)
        let puzzle = OjisanPuzzleOnboarding.guide(mode: .puzzle)
        #expect(backpain.pages[1].lines == puzzle.pages[1].lines, "操作は両モード共通")
        #expect(backpain.pages[2].lines == puzzle.pages[2].lines, "れんさは両モード共通")
        // パズルモードには腰痛ゲージ・入院・ライン・せり上がりを出さない（会長指示 2026-10-12）。
        for text in puzzle.texts {
            for word in ["腰", "入院", "ライン", "せり上が"] {
                #expect(!text.contains(word), "パズルモードの「\(text)」に「\(word)」が出ている")
            }
        }
    }

    @Test("れんさの図: 4 つ消えて落ちた荷物がまたつながり 2 れんさ、点は 40 + 80 = 120")
    func chainFigure() {
        let steps = ChainFigure.steps
        #expect(steps.count == 3)
        let first = padded(steps[0].grid)
        let result = OjisanPuzzleBoard.resolve(first)
        #expect(result.chains == [4, 4], "4 つ消えて、落ちてまた 4 つ消える")
        #expect(OjisanPuzzleScoring.chainPoints(cells: 4, chain: 1) == 40)
        #expect(OjisanPuzzleScoring.chainPoints(cells: 4, chain: 2) == 80)
        #expect(OjisanPuzzleScoring.totalPoints(chains: result.chains) == 120)
        // 1 コマ目の印は、実際に消える塊。
        let groups = OjisanPuzzleBoard.clearableGroups(first)
        let top = OjisanPuzzleBoard.rows - ChainFigure.rows
        #expect(Set(groups.flatMap { $0 }) == Set(steps[0].highlight.map { OjisanPuzzleCell(row: $0.row + top, col: $0.column) }))
        // 2 コマ目は 1 つ目を消して落とした盤で、印は次に消える塊。
        let second = OjisanPuzzleBoard.applyingGravity(OjisanPuzzleBoard.removing(first, groups: groups))
        #expect(second == padded(steps[1].grid))
        let secondGroups = OjisanPuzzleBoard.clearableGroups(second)
        #expect(Set(secondGroups.flatMap { $0 }) == Set(steps[1].highlight.map { OjisanPuzzleCell(row: $0.row + top, col: $0.column) }))
        // 3 コマ目は落ち着いた盤。
        #expect(result.board == padded(steps[2].grid))
    }

    @Test("1 組でやること: よこに動かし、タップで回し、下へ落とす。はさまれたら 2 回目のタップで上下が入れかわる")
    func controls() {
        let model = OjisanPuzzleModel(board: OjisanPuzzleBoard.emptyBoard(),
                                      current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 5, col: 2, rotation: .up),
                                      mode: .puzzle)
        #expect(model.move(by: 1))
        #expect(model.current?.col == 3)
        #expect(model.rotate(clockwise: true))
        #expect(model.current?.rotation == .right)
        #expect(model.hardDrop())
        #expect(model.board[OjisanPuzzleBoard.rows - 1][3] == 1 && model.board[OjisanPuzzleBoard.rows - 1][4] == 2)

        var walls = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            walls[row][1] = row % 2 + 3
            walls[row][3] = row % 2 + 3
        }
        let pinched = OjisanPuzzleModel(board: walls,
                                        current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 5, col: 2, rotation: .up),
                                        mode: .puzzle)
        #expect(!pinched.rotate(clockwise: true), "1 回目は回せない")
        #expect(pinched.rotate(clockwise: true), "続けてもう 1 回で入れかわる")
        #expect(pinched.current?.rotation == .down)
    }

    @Test("荷物は 5 種類で、重いほど腰にくる。消すと楽になり、腰にくるほど速く落ちて操作が遅れる")
    func gauge() {
        #expect(OjisanPuzzleLuggage.all.count == 5)
        #expect(OjisanPuzzleBoard.kindCount == 5)
        let weights = OjisanPuzzleLuggage.all.map(\.weight)
        #expect(weights == weights.sorted())
        #expect(OjisanPuzzlePain.afterLock(0, weights: [5, 5]) > OjisanPuzzlePain.afterLock(0, weights: [1, 1]))
        #expect(OjisanPuzzlePain.afterChain(50, cells: 4, chain: 1) < 50, "消すと減る")
        let stages = OjisanPuzzlePain.Stage.allCases
        let painAt = [0] + OjisanPuzzlePain.stageThresholds
        #expect(stages.count == painAt.count)
        let fall = painAt.map(OjisanPuzzlePain.fallFactor(for:))
        let delay = painAt.map(OjisanPuzzlePain.inputDelayMilliseconds(for:))
        #expect(zip(fall, fall.dropFirst()).allSatisfy { $0 > $1 }, "腰にくるほど速く落ちる")
        #expect(zip(delay, delay.dropFirst()).allSatisfy { $0 < $1 }, "腰にくるほど操作が遅れる")
        #expect(OjisanPuzzleMode.backpain.hasGauge && !OjisanPuzzleMode.puzzle.hasGauge)
    }

    @Test("荷運びモード: 時間で下から 1 段せり上がる。パズルモードは空の盤から始まり、置くほど速くなる")
    func risingAndSpeedUp() {
        let backpain = OjisanPuzzleModel(mode: .backpain, announcesStart: false, seed: 7)
        #expect(backpain.riseIntervalMilliseconds == OjisanPuzzleCleanup.riseIntervalMilliseconds)
        #expect(backpain.clearLineRow == OjisanPuzzleCleanup.clearLineRow)
        var rng = OjisanPuzzleRandom(seed: 3)
        let risen = OjisanPuzzleCleanup.rising(backpain.board, using: &rng)
        #expect(!risen.overflowed)
        #expect(Array(risen.board.dropLast()) == Array(backpain.board.dropFirst()), "盤全体が 1 段上がる")
        #expect(risen.board[OjisanPuzzleBoard.rows - 1].allSatisfy { $0 != 0 }, "下に 1 段ぶん荷物が入る")

        let puzzle = OjisanPuzzleModel(mode: .puzzle, announcesStart: false, seed: 7)
        #expect(puzzle.board == OjisanPuzzleBoard.emptyBoard())
        #expect(puzzle.riseIntervalMilliseconds == nil && puzzle.clearLineRow == nil)
        #expect(OjisanPuzzleSpeedUp.factor(locks: 0) == 1)
        #expect(OjisanPuzzleSpeedUp.factor(locks: OjisanPuzzleSpeedUp.locksPerLevel) < 1, "置くほど速くなる")
    }

    @Test("荷運びモード: ラインより下まで片付けたらクリアで、記録はタイム")
    func cleared() throws {
        let suite = "asobiba.ojisanpuzzle.onboarding.tests.cleared"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let line = OjisanPuzzleCleanup.clearLineRow
        var board = OjisanPuzzleBoard.emptyBoard()
        board[11][0] = 1; board[10][0] = 3; board[9][0] = 1
        board[line][0] = 2; board[line - 1][0] = 2  // ラインの上に 1 つはみ出している
        #expect(!OjisanPuzzleCleanup.isCleared(board))
        let model = OjisanPuzzleModel(services: services, board: board,
                                      current: OjisanPuzzlePair(axisKind: 2, childKind: 2, row: 1, col: 0, rotation: .up),
                                      mode: .backpain, clearLineRow: line)
        #expect(model.hardDrop())
        settle(model)
        #expect(model.outcome == .cleared)
        let record = try #require(log.record(gameID: OjisanPuzzleModel.gameID, variant: OjisanPuzzleMode.backpain.recordVariant))
        #expect(record.metric == .shortestTime, "早いほど良い記録")
        #expect(record.wins == 1)
    }

    @Test("荷運びモード: ゲージが満タンで入院。負けたときは広告で 1 回だけ続けられる")
    func hospitalizedAndContinueOnce() {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 7..<OjisanPuzzleBoard.rows { board[row][5] = row % 2 + 3 }  // ラインの上にはみ出した列
        let model = OjisanPuzzleModel(board: board,
                                      current: OjisanPuzzlePair(axisKind: 5, childKind: 5, row: 1, col: 0, rotation: .up),
                                      pain: OjisanPuzzlePain.limit - 1, mode: .backpain,
                                      clearLineRow: OjisanPuzzleCleanup.clearLineRow)
        #expect(model.hardDrop())
        #expect(model.outcome == .hospitalized)
        #expect(model.canContinue)
        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        #expect(model.outcome == nil)
        #expect(model.pain < OjisanPuzzlePain.limit)
        model.pause()
        #expect(model.continueUsed)
        #expect(!model.canContinue, "2 回目は無い")
    }

    @Test("▼の列のいちばん上が埋まったら終わり（両モード）。パズルモードの記録は得点")
    func buried() throws {
        let suite = "asobiba.ojisanpuzzle.onboarding.tests.buried"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows { board[row][OjisanPuzzleBoard.spawnColumn] = row % 2 + 3 }
        #expect(OjisanPuzzleBoard.isSpawnBlocked(board))
        let model = OjisanPuzzleModel(services: services, board: board,
                                      current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
                                      mode: .puzzle)
        #expect(model.hardDrop())
        settle(model)
        #expect(model.outcome == .buried)
        #expect(model.canContinue, "埋まったときも広告で続けられる")
        let record = try #require(log.record(gameID: OjisanPuzzleModel.gameID, variant: OjisanPuzzleMode.puzzle.recordVariant))
        #expect(record.metric == .points)
    }

    @Test("入口: 「？」と開始シートに、遊んでいるモードの「はじめての遊び方」をつなぐ")
    func wiring() throws {
        let view = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        #expect(view.contains("model.mode.howToPlayGuide.onboarding(OjisanPuzzleOnboarding.guide(mode: model.mode))"))
        let sheet = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleSetupSheet.swift"))
        #expect(sheet.contains("onboarding: OjisanPuzzleOnboarding.guide(mode: mode)"))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let texts = OjisanPuzzleMode.allCases.flatMap { OjisanPuzzleOnboarding.guide(mode: $0).texts }
        for text in Set(texts) {
            #expect(GameOjisanPuzzle.tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
