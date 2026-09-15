import Testing
import Foundation
import GameKitTestSupport
@testable import GameMinesweeper

/// 広告のコンティニューを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("マインスイーパー 広告のコンティニューの局ガード（#729）")
struct MinesweeperRewardedContinueTests {

    @Test("広告のあいだに新規ゲームを始めたら、前の局のコンティニューは新しい局に乗らない")
    func continueForReplacedGameIsRejected() throws {
        let model = MinesweeperModel(services: nil)
        let game = model.gameSerial
        // 新しい局でも地雷を踏み、「コンティニューを提案できない」という状態の確認だけでは弾けない形にする。
        // 地雷は最初のタップで配られるので、初手で全マスが開いて勝つ配置を引いたら配り直す。
        var attempts = 0
        repeat {
            model.newGame(rows: 9, cols: 9, mines: 10)
            model.tap(row: 0, col: 0)
            attempts += 1
        } while model.gameState != .playing && attempts < 10
        try #require(model.gameState == .playing)
        let mine = try #require((0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.cells[$0.0][$0.1].isMine })
        model.tap(row: mine.0, col: mine.1)
        defer { model.pauseTimer() }
        try #require(model.canContinue)

        #expect(model.gameSerial != game)
        #expect(!model.continueAfterAd(forGame: game), "入れ替わった局へコンティニューを適用している")
        #expect(model.gameState == .lost)
        #expect(!model.continueUsed)
        #expect(model.continueAfterAd(forGame: model.gameSerial), "今の局に対する広告なら適用できる")
        #expect(model.gameState == .playing)
    }

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（#816。BJ・ポーカーの #727 と同じ形）。
    /// 範囲を「あきらめる」ボタンから先に絞るのは、手前のコンティニューボタンにも同じ `.disabled` があり、
    /// ファイル全体を探すとそちらに当たって空振りするため。
    @Test("視聴中は「あきらめる」を押せない")
    func giveUpButtonIsDisabledWhileWatching() throws {
        let source = try SourceScan.packageSource("Sources/GameMinesweeper/MinesweeperView.swift")
        let start = try #require(source.range(of: "Button { showContinue = false } label: {"),
                                 "「あきらめる」ボタンの定義が見つからない（走査が空振りしている）")
        let end = try #require(source.range(of: "// MARK: - 盤の下の操作エリア", range: start.upperBound..<source.endIndex))
        let giveUpButton = source[start.upperBound..<end.lowerBound]
        #expect(giveUpButton.contains("\n                .disabled(continueRescue.isWatching)"),
                "広告のロード〜視聴中に「あきらめる」が押せる")
    }
}
