import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// 盤下の共通の「⋯」の行 `GameOverflowBar`（#1468。旧 `GameControlBar`・#1422）。
///
/// 描画の大きさには出ない性質（44pt の丸・破壊的操作の並び・各ゲームが共通部品に乗っていること・
/// 帯にボタンが無いこと）をソースで固定する。
@Suite("盤下の「⋯」の行")
struct GameOverflowBarTests {
    private static func coreSource() throws -> String {
        try SourceScan.packageSource("Sources/Core/GameOverflowBar.swift")
    }

    @Test("「⋯」は丸 44pt で、当たり判定も枠の中に取る")
    func menuIsA44ptCircle() throws {
        let source = SourceScan.strippingComments(try Self.coreSource())
        #expect(SourceScan.matchCount(of: #"width:\s*BoardGameControlMetrics\.minTapTarget,\s*height:\s*BoardGameControlMetrics\.minTapTarget"#,
                                      in: source) == 1, "「⋯」の丸が 44pt になっていない")
        #expect(source.contains("Circle().fill(Theme.fillMuted)"))
        #expect(source.contains(".contentShape(Circle())"))
        #expect(source.contains(".frame(minHeight: BoardGameControlMetrics.minTapTarget)"), "行の高さが 44pt を割りうる")
    }

    @Test("「⋯」はメニューに入れるものが無いときは出さない")
    func menuIsOmittedWhenEmpty() throws {
        let source = SourceScan.strippingComments(try Self.coreSource())
        #expect(source.contains("if !menuItems.isEmpty {"))
    }

    @Test("チェック付きの項目は Toggle で出す（メモ・拡大・旗モード）")
    func checkedItemsUseToggle() throws {
        let source = SourceScan.strippingComments(try Self.coreSource())
        #expect(source.contains("if let isChecked = item.isChecked {"))
        #expect(source.contains("Toggle(isOn:"))
    }

    @Test("投了・あきらめるなどの破壊的操作はメニューの末尾に寄る（元の並びは保つ）")
    @MainActor func destructiveItemsGoLast() {
        func item(_ id: String, destructive: Bool = false) -> GameControlMenuItem {
            GameControlMenuItem(id: id, title: id, systemImage: "circle", isDestructive: destructive) {}
        }
        let ordered = GameControlMenu.ordered([item("resign", destructive: true), item("undo"), item("hint")])
        #expect(ordered.map(\.id) == ["undo", "hint", "resign"])
    }

    /// 操作は右下の「⋯」にだけある。盤の下に手描きのカプセルが戻ると、色・高さ・並びが再びずれる。
    @Test("一人用パズル・ソリティア系・神経衰弱は共通の「⋯」の行を使う",
          arguments: ["GameSudoku", "GameMinesweeper", "GameSolitaire", "GameFreeCell",
                      "GameSpider", "GameMahjongSolitaire", "GameConcentration"])
    func gamesUseTheSharedBar(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(SourceScan.matchCount(of: #"GameOverflowBar\("#, in: source) >= 1,
                "\(module) が GameOverflowBar を使っていない")
        #expect(SourceScan.matchCount(of: #"private func controlButton\("#, in: source) == 0,
                "\(module) に画面ごとの手描きの操作ボタン（controlButton）が残っている")
    }

    /// ヘッダー下の状態の帯（`GameStatusBar`）には表示だけを置き、ボタン・トグルは置かない（会長決裁 2026-09-26）。
    @Test("状態の帯を持つゲームの帯にボタン・トグルは無い",
          arguments: ["GameSudoku", "GameMinesweeper", "GameFreeCell", "GameSpider", "GameMahjongSolitaire",
                      "GameShogi", "GameChess", "GameGo", "GameGomoku", "GameOthello"])
    func statusBarsHaveNoButtons(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        for declaration in ["private var statusBar", "private func statusBarRow"] {
            guard let block = SourceScan.declaration(of: declaration, in: source) else { continue }
            #expect(!block.contains("Button"), "\(module) の \(declaration) にボタンがある")
            #expect(!block.contains("Toggle"), "\(module) の \(declaration) にトグルがある")
        }
    }

    @Test("盤ゲーム 5 本は盤の下の操作行を持たず、共通の行に待った・投了を入れる",
          arguments: ["GameShogi", "GameChess", "GameGo", "GameGomoku", "GameOthello"])
    func boardGamesUseTheOverflowRow(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(SourceScan.matchCount(of: #"BoardGameControlBar\("#, in: source) == 1)
        #expect(!source.contains("BoardUndoButton"), "\(module) に待ったのボタンが残っている")
        #expect(!source.contains("BoardResignButton"), "\(module) に投了のボタンが残っている")
    }

    @Test("囲碁のパス・花札の投了も「⋯」に入っている")
    func passAndResignLiveInTheMenu() throws {
        let go = SourceScan.strippingComments(try SourceScan.moduleSources("GameGo"))
        #expect(go.contains(#"id: "pass""#))
        let hanafuda = SourceScan.strippingComments(try SourceScan.moduleSources("GameHanafuda"))
        #expect(hanafuda.contains(#"id: "resign""#))
        #expect(hanafuda.contains("GameControlMenu(items:"))
    }

    @Test("あきらめるは確認付きで「⋯」メニューに入っている（ナンプレ・マインスイーパー）",
          arguments: ["GameSudoku", "GameMinesweeper"])
    func giveUpLivesInTheMenu(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(source.contains(#"GameControlMenuItem(id: "giveUp""#))
        #expect(source.contains("showGiveUpConfirm = true"))
        #expect(source.contains("GameOverflowBar("), "項目を GameOverflowBar に渡していない")
        #expect(!source.contains(#"Label("諦める""#), "盤下に手描きの「諦める」ボタンが残っている")
    }
}
