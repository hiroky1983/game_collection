import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport
@testable import GameSudoku

/// 広告のコンティニューを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("数独 広告のコンティニューの局ガード（#729）")
struct SudokuRewardedContinueTests {

    @Test("広告のあいだに新規ゲームを始めたら、前の局のコンティニューは新しい局に乗らない")
    func continueForReplacedGameIsRejected() async {
        let model = SudokuModel(services: nil, seed: 2026)
        await model.newGame(difficulty: .easy)
        let game = model.gameSerial
        await model.newGame(difficulty: .easy)
        // 新しい局もミス上限にし、「ミス上限ではない」という状態の確認だけでは弾けない形にする。
        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        #expect(model.state == .failed, "前提: 新しい局もミス上限になっている")

        #expect(!model.continueAfterAd(forGame: game), "入れ替わった局へコンティニューを適用している")
        #expect(model.state == .failed)
        #expect(model.mistakes == SudokuModel.maxMistakes)
        #expect(model.continueAfterAd(forGame: model.gameSerial), "今の局に対する広告なら適用できる")
        #expect(model.state == .playing)
    }

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（#911。マインスイーパーの #816 と同じ趣旨）。
    /// ナンプレの失敗幕は Core の `RewardedContinueOverlay` に寄せてある（#829）ため、「ナンプレがその幕を使い、
    /// 諦めるボタンを二次ボタンとして渡していること」と「幕の二次ボタンが視聴中に止まること」の両方を固定する。
    /// #1486 でボタンを共通部品（`GameDeadEndActionButton` / `GameDeadEndDismissButton`）へ寄せたため、
    /// 「視聴中に押せない」は `.disabled` 修飾子ではなく `isDisabled:` 引数で見る。
    /// 整形で赤くならないよう、インデント込みの照合ではなく件数で見る。
    @Test("視聴中は失敗幕の「諦めて答えを見る」を押せない")
    func giveUpButtonIsDisabledWhileWatching() throws {
        let sudoku = SourceScan.strippingComments(try SourceScan.moduleSources("GameSudoku"))
        let failedOverlay = try #require(SourceScan.declaration(of: "private var failedOverlay", in: sudoku),
                                         "失敗幕の定義が見つからない（走査が空振りしている）")
        #expect(failedOverlay.contains("RewardedContinueOverlay("))
        #expect(failedOverlay.contains(#"secondaryTitle: tr("諦めて答えを見る")"#))
        #expect(failedOverlay.contains("secondaryAction: { model.giveUp() }"))

        let core = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/RewardedRescue.swift"))
        let overlay = try #require(SourceScan.declaration(of: "public struct RewardedContinueOverlay", in: core),
                                   "RewardedContinueOverlay の定義が見つからない（走査が空振りしている）")
        let disabledWhileWatching = "isDisabled: continueRescue.isWatching"
        // 救済ボタン（GameDeadEndActionButton）と二次ボタン（GameDeadEndDismissButton）の 2 か所。
        #expect(overlay.components(separatedBy: disabledWhileWatching).count - 1 == 2,
                "広告のロード〜視聴中に押せるボタンが幕に残っている")
        let secondary = try #require(overlay.range(of: "GameDeadEndDismissButton(secondaryTitle"),
                                     "二次ボタンの定義が見つからない（走査が空振りしている）")
        let secondaryCall = try #require(overlay[secondary.lowerBound...].range(of: ") {"))
        #expect(overlay[secondary.lowerBound..<secondaryCall.lowerBound].contains(disabledWhileWatching),
                "広告のロード〜視聴中に「諦めて答えを見る」が押せる")
    }

    // MARK: - ミス上限での負けの記録（#3144）

    private func makeLog(_ name: String) -> PlayLog {
        let suite = "asobiba.sudoku.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PlayLog(defaults: defaults)
    }

    private func failedModel(log: PlayLog) async -> SudokuModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = SudokuModel(services: services, seed: 2026)
        await model.newGame(difficulty: .easy)
        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        return model
    }

    @Test("ミス上限に達した局を新規で捨てても負けが 1 つ付く")
    func abandoningFailedGameRecordsLoss() async {
        let log = makeLog("abandon")
        let model = await failedModel(log: log)
        #expect(model.state == .failed)
        await model.newGame(difficulty: .easy)
        let record = log.record(gameID: "sudoku", variant: SudokuDifficulty.easy.rawValue)
        #expect(record?.losses == 1)
        #expect(record?.plays == 1)
    }

    @Test("コンティニューすると、ミス上限で付けた負けは取り消される")
    func continueCancelsLoss() async {
        let log = makeLog("continue")
        let model = await failedModel(log: log)
        #expect(model.continueAfterAd())
        let record = log.record(gameID: "sudoku", variant: SudokuDifficulty.easy.rawValue)
        #expect((record?.losses ?? 0) == 0)
        #expect((record?.plays ?? 0) == 0)
        #expect(model.recordResult == nil)
    }

    @Test("ミス上限から諦めても負けは 1 つだけ")
    func giveUpFromFailedDoesNotDoubleCount() async {
        let log = makeLog("giveup")
        let model = await failedModel(log: log)
        model.giveUp()
        let record = log.record(gameID: "sudoku", variant: SudokuDifficulty.easy.rawValue)
        #expect(record?.losses == 1)
        #expect(model.recordResult != nil, "リザルトに出す記録は残る")
    }

    /// 空きマスを1つ選び、正解ではない数字を入れる。
    private func enterWrongDigit(_ model: SudokuModel) {
        guard let index = (0..<81).first(where: { !model.given[$0] && model.board[$0] == 0 }) else {
            Issue.record("空きマスが無い")
            return
        }
        if model.selected != index { model.select(index: index) }
        let wrong = (1...9).first { $0 != model.solution[index] }!
        model.enter(digit: wrong)
    }
}
