import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// 盤下の共通の操作行 `GameControlBar`（#1422）。
///
/// 描画の大きさには出ない性質（44pt の枠・「⋯」の出し分け・各ゲームが共通部品に乗っていること）を
/// ソースで固定する。
@Suite("盤下の共通の操作行")
struct GameControlBarTests {
    private static func coreSource() throws -> String {
        try SourceScan.packageSource("Sources/Core/GameControlBar.swift")
    }

    @Test("操作行のボタンは 44pt の共通カプセル、「⋯」の枠も 44pt")
    func buttonsUseTheTapTargetCapsule() throws {
        let source = SourceScan.strippingComments(try Self.coreSource())
        #expect(SourceScan.matchCount(of: #"\.buttonStyle\(BoardGameControlCapsuleStyle\(fill: tint\)\)"#, in: source) == 1,
                "GameControlButton が 44pt の共通カプセルを通っていない")
        #expect(SourceScan.matchCount(of: #"minHeight:\s*BoardGameControlMetrics\.minTapTarget"#, in: source) == 1,
                "「⋯」の当たり判定が 44pt の枠になっていない")
    }

    @Test("「⋯」はメニューに入れるものが無いときは出さない")
    func menuIsOmittedWhenEmpty() throws {
        let source = SourceScan.strippingComments(try Self.coreSource())
        #expect(source.contains("if !menuItems.isEmpty {"))
    }

    /// 7 本すべてが共通の操作行に乗っていること。手描きのカプセルに戻ると、色・高さ・並びが再びずれる。
    @Test("一人用パズル・ソリティア系 7 本は共通の操作行を使う",
          arguments: ["GameSudoku", "GameMinesweeper", "GameSolitaire", "GameFreeCell",
                      "GameSpider", "GameMahjongSolitaire", "GameConcentration"])
    func gamesUseTheSharedBar(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(SourceScan.matchCount(of: #"GameControlBar\("#, in: source) + SourceScan.matchCount(of: #"GameControlBar \{"#, in: source) >= 1,
                "\(module) が GameControlBar を使っていない")
        #expect(SourceScan.matchCount(of: #"private func controlButton\("#, in: source) == 0,
                "\(module) に画面ごとの手描きの操作ボタン（controlButton）が残っている")
    }

    /// 取り消し（戻す／待った）はティール（#1011 の色決裁）。コーラルは「終わらせる」操作の色。
    @Test("取り消しボタンはコーラルではない",
          arguments: ["GameSudoku", "GameSolitaire", "GameFreeCell", "GameSpider",
                      "GameMahjongSolitaire", "GameConcentration"])
    func undoIsNotCoral(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(SourceScan.matchCount(of: #"GameControlButton\([^{]*Theme\.Fill\.coral"#, in: source) == 0,
                "\(module) の操作行にコーラルのボタンが残っている")
    }

    @Test("あきらめるは確認付きで「⋯」メニューに入っている（ナンプレ・マインスイーパー）",
          arguments: ["GameSudoku", "GameMinesweeper"])
    func giveUpLivesInTheMenu(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(source.contains(#"GameControlMenuItem(id: "giveUp""#))
        #expect(source.contains("showGiveUpConfirm = true"))
        #expect(source.contains("GameControlBar(menuItems:"), "項目を GameControlBar に渡していない")
        #expect(!source.contains(#"Label("諦める""#), "盤下に手描きの「諦める」ボタンが残っている")
    }
}
