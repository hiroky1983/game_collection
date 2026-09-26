import Foundation
import Testing
import Core
import GameKitTestSupport

/// 対戦ゲームのヘッダー下の行（#1419）が、共通の枠と手番表示を通っていること。
@Suite("対戦ゲームのステータス行")
struct GameStatusBarTests {
    /// 対象の 9 本（ディレクトリ名）。
    private static let games = ["GameShogi", "GameChess", "GameGo", "GameOthello", "GameGomoku",
                                "GameConcentration", "GameHanafuda", "GameDaifugo", "GameShiritori"]

    @Test("最小の高さは 44pt・余白は横 12 / 縦 6")
    func styleValues() {
        #expect(GameStatusBarStyle.minHeight == 44)
        #expect(GameStatusBarStyle.horizontalPadding == 12)
        #expect(GameStatusBarStyle.verticalPadding == 6)
    }

    @Test("手番の色: あなた＝ティール / CPU＝コーラル / 終局＝fillMuted")
    func turnBadgeColors() {
        #expect(TurnBadge.Kind.you.fill == Theme.Fill.teal)
        #expect(TurnBadge.Kind.cpu.fill == Theme.Fill.coral)
        #expect(TurnBadge.Kind.finished.fill == Theme.fillMuted)
    }

    @Test("どの対象ゲームも GameStatusBar を通る")
    func gamesUseSharedBar() throws {
        for game in Self.games {
            let source = SourceScan.strippingComments(try SourceScan.moduleSources(game))
            #expect(source.contains("GameStatusBar {"), "\(game) が GameStatusBar を使っていない")
            #expect(source.contains("TurnBadge(") || game == "GameConcentration",
                    "\(game) が TurnBadge を使っていない")
        }
    }
}
