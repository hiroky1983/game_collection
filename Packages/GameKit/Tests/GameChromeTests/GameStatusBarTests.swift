import Foundation
import SwiftUI
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

    /// 余白より前に下限を掛けると 56pt になる（CodeRabbit 指摘）。完成した高さで見る。
    @Test("小さな中身でも完成した高さは 44pt")
    @MainActor
    func completedHeightIsMinHeight() {
        let renderer = ImageRenderer(content: GameStatusBar { Text("a") } trailing: { Text("b") }
            .frame(width: 343))
        renderer.scale = 1
        #expect(renderer.cgImage?.height == 44)
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

    /// 一人用の 6 本（#1420）。2048・15 パズル・ブロック崩しは大きなスコア表示を残す例外。
    @Test("一人用の対象 6 本も GameStatusBar を通る")
    func soloGamesUseSharedBar() throws {
        let games = ["GameSolitaire", "GameFreeCell", "GameSpider", "GameMahjongSolitaire",
                     "GameSudoku", "GameMinesweeper"]
        for game in games {
            let source = SourceScan.strippingComments(try SourceScan.moduleSources(game))
            #expect(source.range(of: #"GameStatusBar\s*[({]"#, options: .regularExpression) != nil,
                    "\(game) が GameStatusBar を使っていない")
        }
    }
}
