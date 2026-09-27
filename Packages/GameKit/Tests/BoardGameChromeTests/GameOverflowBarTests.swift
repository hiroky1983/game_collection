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
        #expect(hanafuda.contains("GameOverflowBar("), "花札の投了が共通の「⋯」の行に乗っていない")
    }

    // MARK: - 盤→「⋯」→余白→広告 の並び（#1485）

    /// `(ファイル, 盤の目印, 「⋯」の行の目印)`。盤の目印から「⋯」の行までに `Spacer` を挟まないこと、
    /// 余白を吸う `Spacer` が「⋯」の行と `BannerSlot` のあいだにあることを本体の組み立てで確かめる。
    ///
    /// トランプのソリティア系 3 本（フリーセル・スパイダー・ソリティア）はこの並びを自前の body には
    /// 持たず、共通の器 `OrientationAdaptiveGameLayout`（`Core/GameLandscapeLayout.swift`）へ委ねている
    /// （#1511）。それらの並びは `sharedLandscapeLayoutKeepsPortraitOrder` で別途固定し、ここでは
    /// 委譲していることだけを見る（`landscapeAdaptiveGamesDelegateToSharedLayout`）。
    static let layoutCases: [(String, String, String)] = [
        ("GameChess/ChessView.swift", "\n            board\n", "controlArea"),
        ("GameShogi/ShogiView.swift", "\n            board\n", "controlArea"),
        ("GameGo/GoView.swift", "\n            board\n", "controlArea"),
        ("GameGomoku/GomokuView.swift", "\n            board\n", "controlArea"),
        ("GameOthello/OthelloView.swift", "\n            board\n", "controlArea"),
        ("GameMinesweeper/MinesweeperView.swift", "\n            board\n", "controlArea"),
        ("GameMahjongSolitaire/MahjongSolitaireView.swift", "\n            board\n", "controlArea"),
        ("GameSudoku/SudokuView.swift", "\n            board\n", "controlArea"),
    ]

    /// 共通の器へ委ねているソリティア系 3 本の View ファイル。
    static let landscapeAdaptiveViewPaths: [String] = [
        "GameFreeCell/FreeCellView.swift",
        "GameSpider/SpiderView.swift",
        "GameSolitaire/SolitaireView.swift",
    ]

    @Test("「⋯」の行は盤のすぐ下に付き、余白は「⋯」の行と広告のあいだにある", arguments: layoutCases.indices)
    func overflowRowSitsRightUnderTheBoard(index: Int) throws {
        let (path, boardMark, controlMark) = Self.layoutCases[index]
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        let body = try #require(SourceScan.declaration(of: "public var body: some View", in: source), "\(path) の body が無い")
        let board = try #require(body.range(of: boardMark), "\(path) の body に盤が無い")
        let control = try #require(body.range(of: controlMark, range: board.upperBound..<body.endIndex),
                                   "\(path) の「⋯」の行が盤より下に無い")
        let banner = try #require(body.range(of: "BannerSlot(", range: control.upperBound..<body.endIndex),
                                  "\(path) の広告が「⋯」の行より下に無い")
        #expect(!body[board.upperBound..<control.lowerBound].contains("Spacer("),
                "\(path) の盤と「⋯」の行のあいだに Spacer がある（「⋯」が盤から離れて浮く）")
        #expect(body[control.upperBound..<banner.lowerBound].contains("Spacer(minLength: 0)"),
                "\(path) の「⋯」の行と広告のあいだに余白を吸う Spacer が無い")
    }

    @Test("横向き対応3画面（#1511）は盤下の並びを共通の器（OrientationAdaptiveGameLayout）に委ねている",
          arguments: landscapeAdaptiveViewPaths)
    func landscapeAdaptiveGamesDelegateToSharedLayout(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        let body = try #require(SourceScan.declaration(of: "public var body: some View", in: source), "\(path) の body が無い")
        #expect(body.contains("OrientationAdaptiveGameLayout("),
                "\(path) が共通の器に乗っていない（盤下の並びはその器の中でしか保証されない）")
    }

    @Test("共通の器（OrientationAdaptiveGameLayout）の縦向きは、盤のすぐ下に操作が付き、余白は操作/ヒントと広告のあいだにある")
    func sharedLandscapeLayoutKeepsPortraitOrder() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameLandscapeLayout.swift"))
        let body = try #require(SourceScan.declaration(of: "private var portraitBody: some View", in: source),
                                "portraitBody が無い")
        let board = try #require(body.range(of: "\n            board\n"), "portraitBody に盤が無い")
        let controls = try #require(body.range(of: "\n            controls\n", range: board.upperBound..<body.endIndex),
                                    "portraitBody の操作が盤より下に無い")
        let banner = try #require(body.range(of: "BannerSlot(", range: controls.upperBound..<body.endIndex),
                                  "portraitBody の広告が操作より下に無い")
        #expect(!body[board.upperBound..<controls.lowerBound].contains("Spacer("),
                "portraitBody の盤と操作のあいだに Spacer がある（「⋯」が盤から離れて浮く）")
        #expect(body[controls.upperBound..<banner.lowerBound].contains("Spacer(minLength: 0)"),
                "portraitBody の操作と広告のあいだに余白を吸う Spacer が無い")
    }

    @Test("盤下の操作エリアは対局中の中身を上寄せにする（「⋯」を広告の直上へ沈めない）")
    func controlAreaAlignsPlayingRowToTop() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameChrome.swift"))
        let area = try #require(SourceScan.declaration(of: "public struct GameControlArea", in: source))
        #expect(area.contains("ZStack(alignment: .top)"))
        #expect(!area.contains("alignment: .bottom"))
    }

    @Test("神経衰弱: 「⋯」の行は札の並びと同じ枠で札のすぐ下に置き、余りは下に残す")
    func concentrationRowFollowsTheGrid() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameConcentration/ConcentrationView.swift"))
        let body = try #require(SourceScan.declaration(of: "public var body: some View", in: source))
        #expect(!body.contains("mattaControls"), "「⋯」の行が札の枠の外（広告側）に出ている")
        let grid = try #require(SourceScan.declaration(of: "private var cardGrid: some View", in: source))
        let lazyGrid = try #require(grid.range(of: "LazyVGrid("))
        let row = try #require(grid.range(of: "mattaControls", range: lazyGrid.upperBound..<grid.endIndex))
        #expect(grid[row.upperBound...].contains("alignment: .top"), "札と「⋯」を上から詰めていない")
        #expect(grid.contains("geo.size.height - controls"), "「⋯」の行の高さを札の高さから引いていない")
    }

    @Test("花札: 「⋯」の行は手札のすぐ下に置き、手番は状態の帯に出す（盤の下に「あなたの番」だけの行を残さない）")
    func hanafudaRowAndTurnBadge() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHanafuda/HanafudaView.swift"))
        let body = try #require(SourceScan.declaration(of: "public var body: some View", in: source))
        let hand = try #require(body.range(of: "handArea(fit)"))
        let row = try #require(body.range(of: "overflowBar", range: hand.upperBound..<body.endIndex))
        #expect(body.range(of: "BannerSlot(", range: row.upperBound..<body.endIndex) != nil)
        let actionArea = try #require(SourceScan.declaration(of: "private var actionArea: some View", in: source))
        #expect(!actionArea.contains("TurnBadge"), "盤の下の行に手番が残っている")
        #expect(!actionArea.contains("GameControlMenu"), "「⋯」が札の外の行に残っている")
        let scoreBar = try #require(SourceScan.declaration(of: "private var scoreBar: some View", in: source))
        #expect(scoreBar.contains("turnBadge"), "状態の帯に手番が無い")
        let badge = try #require(SourceScan.declaration(of: "private var turnBadge: some View", in: source))
        #expect(badge.contains("TurnBadge(isYourTurn:"))
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
