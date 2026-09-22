import Testing
import Foundation
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
    /// 整形で赤くならないよう、インデント込みの照合ではなく件数で見る。
    @Test("視聴中は失敗幕の「諦めて答えを見る」を押せない")
    func giveUpButtonIsDisabledWhileWatching() throws {
        let sudoku = SourceScan.strippingComments(try SourceScan.moduleSources("GameSudoku"))
        let failedOverlay = try #require(SourceScan.declaration(of: "private var failedOverlay", in: sudoku),
                                         "失敗幕の定義が見つからない（走査が空振りしている）")
        #expect(failedOverlay.contains("RewardedContinueOverlay("))
        #expect(failedOverlay.contains(#"secondaryTitle: "諦めて答えを見る""#))
        #expect(failedOverlay.contains("secondaryAction: { model.giveUp() }"))

        let core = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/RewardedRescue.swift"))
        let overlay = try #require(SourceScan.declaration(of: "public struct RewardedContinueOverlay", in: core),
                                   "RewardedContinueOverlay の定義が見つからない（走査が空振りしている）")
        let disabledWhileWatching = ".disabled(continueRescue.isWatching)"
        // 救済ボタンと二次ボタンの 2 か所。
        #expect(overlay.components(separatedBy: disabledWhileWatching).count - 1 == 2,
                "広告のロード〜視聴中に押せるボタンが幕に残っている")
        let secondary = try #require(overlay.range(of: "Button(secondaryTitle)"),
                                     "二次ボタンの定義が見つからない（走査が空振りしている）")
        #expect(overlay[secondary.upperBound...].contains(disabledWhileWatching),
                "広告のロード〜視聴中に「諦めて答えを見る」が押せる")
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
