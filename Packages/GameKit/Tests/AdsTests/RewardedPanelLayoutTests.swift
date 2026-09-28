import Testing
import Foundation
import GameKitTestSupport
@testable import Core

/// 失敗パネル（盤に重ねる広告コンティニューの幕）の内側余白を全ゲームで揃える（#1520。#1486 の未達分）。
///
/// 画面は swift test から描けないので、書き方そのものを見る。共通部品の既定値が 0 のまま、
/// 2048・ブロックならべだけ横幅いっぱいのボタンが盤の端に接していた。
@Suite("失敗パネルの内側余白の統一（#1520）")
struct RewardedPanelLayoutTests {

    @Test("内側の余白は 0 ではない（ボタンが盤の端に接しない）")
    func paddingIsNotZero() {
        #expect(RewardedPanelLayout.contentPadding > 0)
    }

    /// 余白を上書きしている面は、共通の値からずれていく。共通部品を使う面は既定値に任せる。
    @Test("共通の幕を使う面は余白を上書きしない",
          arguments: ["Game2048", "GameBlockPuzzle", "GameSudoku", "GameFruits"])
    func overlayUsersKeepDefaultPadding(module: String) throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(code.contains("RewardedContinueOverlay("), "\(module): 幕の呼び出しが見つからない（走査が空振りしている）")
        #expect(!code.contains("contentPadding:"), "\(module) が幕の内側余白を独自の値で上書きしている")
    }

    @Test("マインスイーパーの幕も同じ余白を使う")
    func minesweeperUsesSharedPadding() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameMinesweeper"))
        let content = try #require(SourceScan.declaration(of: "private var continueContent", in: code),
                                   "幕の中身の定義が見つからない（走査が空振りしている）")
        #expect(content.contains(".padding(RewardedPanelLayout.contentPadding)"))
    }

    /// 大きな文字設定で幕が盤からはみ出す（SE・#1520）ため、収まらないときだけスクロールへ落とす。
    @Test("マインスイーパーの幕は収まらないときスクロールに切り替わる")
    func minesweeperOverlayScrollsWhenNotFitting() throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources("GameMinesweeper"))
        let overlay = try #require(SourceScan.declaration(of: "private var continueOverlay", in: code),
                                   "幕の定義が見つからない（走査が空振りしている）")
        #expect(overlay.contains("ViewThatFits(in: .vertical)"))
        #expect(overlay.contains("ScrollView"))
    }
}
