import Testing
import SwiftUI
import GameKitTestSupport
import Foundation
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack
import GameDaifugo
import GameMahjongSolitaire
import GameMahjong
import GameSudoku
import GameGo
import GameSolitaire
import GameFreeCell
import GameRunner
import GameHanafuda
import GameShiritori
import GameFifteen
import GameFruits
import GameColorRelay
import GameAnzan
import GameBackgammon
import GameMancala
import GameSpeed
import GameOldMaid
import GameHomerun
import GameSpider
@testable import GamePoker
@testable import GameConcentration
@testable import GameBlackjack
@testable import GameDaifugo
@testable import GameSolitaire
@testable import GameFreeCell
@testable import GameSpider
@testable import GameShogi
@testable import GameGo
@testable import GameOthello
@testable import GameChess
@testable import GameGomoku
@testable import GameMahjong
@testable import GameMahjongSolitaire
@testable import GameHanafuda
@testable import GameHomerun
@testable import GameRunner
@testable import Game2048
@testable import GameMinesweeper
@testable import GameSudoku
@testable import GameBlocks
@testable import GameFifteen
@testable import GameFruits
@testable import GameColorRelay
@testable import GameBackgammon
@testable import GameSpeed
@testable import GameAnzan
@testable import GameAkariKeshi
@testable import GameTsunagi
import GameHanoi
import GameYonmoku
@testable import GameCatPuzzle
@testable import GameShiritori
import GameChess
import GameBlocks
import GameOjisanPuzzle
import GameHearts
@testable import GameDiceCombo

/// ハブに登録されている全ゲーム（= 遊び方ガイドが要るゲーム）。
@MainActor
private let registeredModules: [GameModule] = [
    Game2048Module(),
    ShogiModule(),
    GomokuModule(),
    MinesweeperModule(),
    OthelloModule(),
    PokerModule(),
    ConcentrationModule(),
    ShiritoriModule(),
    FifteenModule(),
    AkariKeshiModule(),
    FruitsModule(),
    ColorRelayModule(),
    AnzanModule(),
    BackgammonModule(),
    MancalaModule(),
    SpeedModule(),
    OldMaidModule(),
    DiceComboModule(),
    HomerunModule(),
    BlackjackModule(),
    DaifugoModule(),
    MahjongSolitaireModule(),
    SolitaireModule(),
    FreeCellModule(),
    SpiderModule(),
    RunnerModule(),
    HanafudaModule(),
    MahjongModule(),
    SudokuModule(),
    GoModule(),
    ChessModule(),
    BlocksModule(),
    OjisanPuzzleModule(),
    HeartsModule(),
    TsunagiModule(),
    HanoiModule(),
    YonmokuModule(),
    CatPuzzleModule(),
]

// MARK: - 文言（受け入れ条件: 全ゲームぶんある・ルールは3行以内）

@Suite("遊び方の文言")
@MainActor
struct HowToPlayGuideContentTests {

    @Test("登録されている全ゲームぶんのガイドがある（漏れも余りも無い）")
    func coversEveryRegisteredGame() {
        let registered = Set(registeredModules.map(\.id))
        let guided = Set(HowToPlayGuide.all.map(\.gameID))
        #expect(guided == registered, "ガイドの無いゲーム: \(registered.subtracting(guided))／余分: \(guided.subtracting(registered))")
        #expect(HowToPlayGuide.all.count == registeredModules.count)
    }

    @Test("gameID は重複しない")
    func gameIDsAreUnique() {
        #expect(Set(HowToPlayGuide.all.map(\.gameID)).count == HowToPlayGuide.all.count)
    }

    @Test("ルールは1〜3行、ミニガイドは1行で空でない")
    func textIsShortEnough() {
        for guide in HowToPlayGuide.all {
            #expect((1...3).contains(guide.lines.count), "\(guide.gameID) の行数が 3 行を超えている")
            #expect(guide.lines.allSatisfy { !$0.isEmpty }, "\(guide.gameID) に空行がある")
            #expect(!guide.hint.isEmpty, "\(guide.gameID) のミニガイドが空")
            #expect(!guide.hint.contains("\n"), "\(guide.gameID) のミニガイドが1行に収まっていない")
            #expect(!guide.title.isEmpty)
            #expect(!guide.hintIcon.isEmpty)
        }
    }

    @Test("図入りの項目（#2044）は文が空でなく、改行を含まない短文")
    func illustratedItemsAreShort() {
        for guide in HowToPlayGuide.all {
            for item in guide.items {
                #expect(!item.text.isEmpty, "\(guide.gameID) に空の項目がある")
                #expect(!item.text.contains("\n"), "\(guide.gameID) の項目に改行がある")
                // 1〜2 行（スマホのカードで 1 行 20 字前後）に収める目安。
                #expect(item.text.count <= 70, "\(guide.gameID) の項目が長すぎる: \(item.text)")
            }
            #expect(guide.notes.allSatisfy { !$0.isEmpty }, "\(guide.gameID) に空の補足がある")
            // 補足だけのゲームは作らない（補足は図カードの末尾に出す）。
            if guide.items.isEmpty { #expect(guide.notes.isEmpty, "\(guide.gameID) は項目が無いのに補足がある") }
        }
    }

    @Test("おじさんの荷物運びパズルは図入りの遊び方を持つ（#2044 の先駆け）")
    func ojisanPuzzleHasIllustratedItems() {
        let guide = HowToPlayGuide.ojisanPuzzleBackpain
        #expect(guide.gameID == OjisanPuzzleModule().id)
        #expect(guide.items.count == 6)
        #expect(!guide.notes.isEmpty)
        // 腰痛ゲージは計算方法が検討中なので、数値（目盛り・定数）を文に書かない。
        let gaugeText = guide.items[4].text
        #expect(gaugeText.rangeOfCharacter(from: .decimalDigits) == nil, "腰痛ゲージの項目に数値がある: \(gaugeText)")
        // 積み上がりは「荷物が出てくる位置が埋まったら」の表現で書く（#2088 の判定変更と矛盾させない）。
        #expect(guide.items[5].text.contains("荷物が出てくる位置"))
    }

    @Test("パズルモード用の「？」は gameID が同じで all に入らない（五目並べの禁じ手と同じ作法）")
    func ojisanPuzzlePuzzleSharesGameIDButIsNotRegistered() {
        let guide = HowToPlayGuide.ojisanPuzzlePuzzle
        #expect(guide.gameID == OjisanPuzzleModule().id)
        #expect(!HowToPlayGuide.all.contains(guide))
    }
}

// MARK: - 初回フラグの永続化（受け入れ条件: 表示済みなら二度と出ない）

@Suite("ミニガイドの初回フラグ")
@MainActor
struct HowToPlayFlagTests {

    private func makeDefaults(_ suite: String) -> (UserDefaults, String) {
        let name = "asobiba.howtoplay.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test("初回だけ true を返し、2回目以降は false（= 二度と出ない）")
    func marksOnlyOnce() {
        let (defaults, name) = makeDefaults("once")
        let log = PlayLog(defaults: defaults)

        #expect(log.hasShownGuide(for: "shogi") == false)
        #expect(log.markGuideShown(for: "shogi") == true, "初回は表示する")
        #expect(log.hasShownGuide(for: "shogi") == true)
        #expect(log.markGuideShown(for: "shogi") == false, "2回目は表示しない")
        #expect(log.markGuideShown(for: "shogi") == false)

        defaults.removePersistentDomain(forName: name)
    }

    @Test("ゲームごとに独立している（1つ見ても他のゲームでは出る）")
    func isolatedPerGame() {
        let (defaults, name) = makeDefaults("per-game")
        let log = PlayLog(defaults: defaults)

        log.markGuideShown(for: "othello")
        for guide in HowToPlayGuide.all where guide.gameID != "othello" {
            #expect(log.hasShownGuide(for: guide.gameID) == false, "\(guide.gameID) まで表示済みになっている")
            #expect(log.markGuideShown(for: guide.gameID) == true)
        }

        defaults.removePersistentDomain(forName: name)
    }

    @Test("アプリ再起動後も出ない（永続化されている）")
    func survivesRelaunch() {
        let (defaults, name) = makeDefaults("relaunch")

        let first = PlayLog(defaults: defaults)
        #expect(first.markGuideShown(for: "2048") == true)
        #expect(first.markGuideShown(for: "poker") == true)

        // 再起動相当: 同じ保存先から作り直す。
        let second = PlayLog(defaults: defaults)
        #expect(second.guidedGameIDs == ["2048", "poker"])
        #expect(second.hasShownGuide(for: "2048") == true)
        #expect(second.markGuideShown(for: "2048") == false, "再起動後も初回に戻らない")
        #expect(second.markGuideShown(for: "gomoku") == true, "まだ見ていないゲームは出る")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("全ゲームぶん記録してもキーは1つだけ")
    func usesSingleKey() {
        let (defaults, name) = makeDefaults("keys")
        let log = PlayLog(defaults: defaults)

        for guide in HowToPlayGuide.all { log.markGuideShown(for: guide.gameID) }
        let domain = defaults.persistentDomain(forName: name) ?? [:]
        #expect(Set(domain.keys) == Set(PlayLog.howToPlayKeys), "書き込むキーは \(PlayLog.guidedGameIDsKey) だけ")
        #expect(defaults.stringArray(forKey: PlayLog.guidedGameIDsKey)?.count == HowToPlayGuide.all.count)

        defaults.removePersistentDomain(forName: name)
    }

    @Test("「プレイ記録を消去」で表示履歴も消える")
    func clearRemovesFlags() {
        let (defaults, name) = makeDefaults("clear")
        let log = PlayLog(defaults: defaults)

        for guide in HowToPlayGuide.all { log.markGuideShown(for: guide.gameID) }
        log.clear()

        for key in PlayLog.allKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) が残っている")
        }
        #expect(log.guidedGameIDs.isEmpty)
        #expect(log.hasShownGuide(for: "shogi") == false, "消去後はまた初回から")

        defaults.removePersistentDomain(forName: name)
    }
}

// MARK: - トランプ系 7 本の図（#2044 束 1）

@Suite("トランプ系の図入りの遊び方")
@MainActor
struct CardGameHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("poker", .poker, PokerHowToFigures.items),
            ("concentration", .concentration, ConcentrationHowToFigures.items),
            ("blackjack", .blackjack, BlackjackHowToFigures.items),
            ("daifugo", .daifugo, DaifugoHowToFigures.items),
            ("solitaire", .solitaire, SolitaireHowToFigures.items),
            ("freecell", .freecell, FreeCellHowToFigures.items),
            ("spider", .spider, SpiderHowToFigures.items),
        ]
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
            #expect(illustrated.notes == guide.notes)
        }
    }

    @Test("ポーカーの開始シートに図入りの要点が埋まっている（#2268・#2551）")
    func pokerStartSheetEmbedsGuide() throws {
        #expect(PokerHowToFigures.guide.items.count == HowToPlayGuide.poker.items.count)
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GamePoker/PokerSheets.swift"))
        #expect(code.contains("PokerHowToFigures.guide"), "開始シートに要点が埋まっていない")
    }

    @Test("画面のヘッダーの「？」は図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("GamePoker/PokerView.swift", "PokerHowToFigures.guide)", "poker"),
            ("GameConcentration/ConcentrationView.swift", "HowToPlayGuide.concentration.illustrated(ConcentrationHowToFigures.items)", "concentration"),
            ("GameBlackjack/BlackjackView.swift", "HowToPlayGuide.blackjack.illustrated(BlackjackHowToFigures.items)", "blackjack"),
            ("GameDaifugo/DaifugoView.swift", "HowToPlayGuide.daifugo.illustrated(DaifugoHowToFigures.items)", "daifugo"),
            ("GameSolitaire/SolitaireView.swift", "HowToPlayGuide.solitaire.illustrated(SolitaireHowToFigures.items)", "solitaire"),
            ("GameFreeCell/FreeCellView.swift", "HowToPlayGuide.freecell.illustrated(FreeCellHowToFigures.items)", "freecell"),
            ("GameSpider/SpiderView.swift", "HowToPlayGuide.spider.illustrated(SpiderHowToFigures.items)", "spider"),
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(".howToPlay(" + expected), "\(name) の「？」が図入りの版でない")
        }
    }
}

// MARK: - 盤ゲーム 5 本の図（#2044 束 2）

@Suite("盤ゲームの図入りの遊び方")
@MainActor
struct BoardGameHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("shogi", .shogi, ShogiHowToFigures.items),
            ("go", .go, GoHowToFigures.items),
            ("othello", .othello, OthelloHowToFigures.items),
            ("chess", .chess, ChessHowToFigures.items),
            ("gomoku", .gomoku, GomokuHowToFigures.items),
            ("gomokuRenju", .gomokuRenju, GomokuHowToFigures.renjuItems),
        ]
    }

    @Test("五目並べの開始シートは、禁じ手の選択に合わせた図入りの要点を並べる（#2268）")
    func gomokuSetupSheetShowsGuide() throws {
        #expect(GomokuHowToFigures.guide(forbiddenMoves: false).items.count == HowToPlayGuide.gomoku.items.count)
        #expect(GomokuHowToFigures.guide(forbiddenMoves: true).items.count == HowToPlayGuide.gomokuRenju.items.count)
        #expect(GomokuHowToFigures.guide(forbiddenMoves: true).items.allSatisfy { $0.figure != nil })
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameGomoku/GomokuView.swift"))
        #expect(code.contains("GomokuHowToFigures.guide(forbiddenMoves: renju)"), "開始シートに要点が埋まっていない")
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
        }
    }

    @Test("画面のヘッダーの「？」は図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("GameShogi/ShogiView.swift", "HowToPlayGuide.shogi.illustrated(ShogiHowToFigures.items)", "shogi"),
            ("GameGo/GoView.swift", "HowToPlayGuide.go.illustrated(GoHowToFigures.items)", "go"),
            ("GameOthello/OthelloView.swift", "HowToPlayGuide.othello.illustrated(OthelloHowToFigures.items)", "othello"),
            ("GameChess/ChessView.swift", "HowToPlayGuide.chess.illustrated(ChessHowToFigures.items)", "chess"),
            ("GameGomoku/GomokuView.swift", "GomokuHowToFigures.guide(forbiddenMoves: model.forbiddenMovesEnabled)", "gomoku"),
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(expected), "\(name) の「？」が図入りの版でない")
        }
    }
}

// MARK: - 麻雀・麻雀ソリティア・花札の図（#2044 束 3）

@Suite("麻雀・花札の図入りの遊び方")
@MainActor
struct MahjongHanafudaHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("mahjong", .mahjong, MahjongHowToFigures.items),
            ("mahjongSingleHand", .mahjongSingleHand, MahjongHowToFigures.singleHandItems),
            ("mahjongHanchan", .mahjongHanchan, MahjongHowToFigures.hanchanItems),
            ("mahjongSolitaire", .mahjongSolitaire, MahjongSolitaireHowToFigures.items),
            ("hanafuda", .hanafuda, HanafudaHowToFigures.items),
        ]
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
            #expect(illustrated.notes == guide.notes)
        }
    }

    @Test("一局戦の「？」は gameID が同じで all に入らず、違うのは対局の流れの項目だけ")
    func mahjongSingleHandVariant() {
        let tonpuu = HowToPlayGuide.mahjong
        let single = HowToPlayGuide.mahjongSingleHand
        #expect(single.gameID == MahjongModule().id)
        #expect(!HowToPlayGuide.all.contains(single))
        #expect(tonpuu.items[0].text != single.items[0].text)
        #expect(Array(tonpuu.items.dropFirst()) == Array(single.items.dropFirst()))
        #expect(MahjongGameLength.tonpuu.howToPlayGuide.items.map(\.text) == tonpuu.items.map(\.text))
        #expect(MahjongGameLength.singleHand.howToPlayGuide.items.map(\.text) == single.items.map(\.text))
    }

    @Test("麻雀の開始シートは、選んでいる長さの項目を常時と折りたたみに分けて全部出す")
    func mahjongSetupSheetShowsEveryItem() {
        for length in MahjongGameLength.allCases {
            let all = length.howToPlayGuide.items.map(\.text)
            let shown = (length.setupKeyItems + length.setupDetailItems).map(\.text)
            #expect(Set(shown) == Set(all) && shown.count == all.count, "\(length) の開始シートに出ない項目がある")
            // 長さで変わる項目（対局の流れ）は常に見せる。
            #expect(length.setupKeyItems.first?.text == all.first)
        }
    }

    @Test("画面のヘッダーの「？」と開始シートは図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("GameMahjong/MahjongView.swift", ".howToPlay(model.gameLength.howToPlayGuide", "mahjong"),  // 後ろに .onboarding(...)（#2825）が続く
            ("GameMahjong/MahjongStartSheet.swift", "length.setupKeyItems", "mahjong の開始シート"),
            ("GameMahjongSolitaire/MahjongSolitaireView.swift", ".howToPlay(HowToPlayGuide.mahjongSolitaire.illustrated(MahjongSolitaireHowToFigures.items)", "mahjongSolitaire"),  // 後ろに .onboarding(...)（#2825）が続く
            ("GameHanafuda/HanafudaView.swift", ".howToPlay(HowToPlayGuide.hanafuda.illustrated(HanafudaHowToFigures.items)", "hanafuda"),  // 後ろに .onboarding(...)（#2827）が続く
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(expected), "\(name) の「？」が図入りの版でない")
        }
    }
}

// MARK: - 柵越えおじさん・チャリンコおじさんの図（#2044 束 4）

@Suite("おじさんゲームの図入りの遊び方")
@MainActor
struct OjisanGamesHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("homerun", .homerun, HomerunHowToFigures.items),
            ("runner", .runner, RunnerHowToFigures.items),
            ("runnerEndless", .runnerEndless, RunnerHowToFigures.endlessItems),
        ]
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
            #expect(illustrated.notes == guide.notes)
        }
    }

    @Test("エンドレスの「？」は gameID が同じで all に入らず、操作の項目はステージ制と同じ")
    func runnerEndlessVariant() {
        let stages = HowToPlayGuide.runner
        let endless = HowToPlayGuide.runnerEndless
        #expect(endless.gameID == RunnerModule().id)
        #expect(!HowToPlayGuide.all.contains(endless))
        #expect(Array(stages.items[1...3]) == Array(endless.items[1...3]))
        #expect(stages.items[0] != endless.items[0] && stages.items[4] != endless.items[4])
        #expect(RunnerMode.stages.howToPlayGuide.items.map(\.text) == stages.items.map(\.text))
        #expect(RunnerMode.endless.howToPlayGuide.items.map(\.text) == endless.items.map(\.text))
        #expect(endless.lines.last?.contains("チェックポイント") == false)
        #expect(endless.lines.last?.contains("やり直せます") == false)
        #expect(stages.lines.last?.contains("チェックポイント") == true)
    }

    @Test("チャリンコおじさんの開始シートは、選んでいるモードの項目を常時と折りたたみに分けて全部出す")
    func runnerSetupSheetShowsEveryItem() {
        for mode in RunnerMode.allCases {
            let all = mode.howToPlayGuide.items.map(\.text)
            let shown = (mode.setupKeyItems + mode.setupDetailItems).map(\.text)
            #expect(Set(shown) == Set(all) && shown.count == all.count, "\(mode) の開始シートに出ない項目がある")
            #expect(mode.setupKeyItems.first?.text == all.first)
        }
    }

    @Test("画面のヘッダーの「？」と開始シートは図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("GameHomerun/HomerunView.swift", ".howToPlay(HowToPlayGuide.homerun.illustrated(HomerunHowToFigures.items)", "homerun"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameRunner/RunnerView.swift", ".howToPlay(model.mode.howToPlayGuide", "runner"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameRunner/RunnerStartSheet.swift", "mode.setupKeyItems", "runner の開始シート"),
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(expected), "\(name) の「？」が図入りの版でない")
        }
    }
}

// MARK: - パズル・その他の図（#2044 束 5）

@Suite("パズル・その他の図入りの遊び方")
@MainActor
struct PuzzleOtherHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("2048", .game2048, Game2048HowToFigures.items),
            ("minesweeper", .minesweeper, MinesweeperHowToFigures.items),
            ("sudoku", .sudoku, SudokuHowToFigures.items),
            ("blocks", .blocks, BlocksHowToFigures.items),
            ("fifteen", .fifteen, FifteenHowToFigures.items),
            ("anzan", .anzan, AnzanHowToFigures.items),
            ("akarikeshi", .akariKeshi, AkariKeshiHowToFigures.items),
            ("tsunagi", .tsunagi, TsunagiHowToFigures.items),
            ("catpuzzle", .catPuzzle, CatPuzzleHowToFigures.items),
            ("dicecombo", .diceCombo, DiceComboHowToFigures.items),
            ("shiritori", .shiritori, ShiritoriHowToFigures.items),
            ("shiritoriEndless", .shiritoriEndless, ShiritoriHowToFigures.endlessItems),
        ]
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
            #expect(illustrated.notes == guide.notes)
        }
    }

    @Test("ハブに並ぶ全ゲームの「？」が図入りになった（#2044 の完了条件）")
    func everyRegisteredGameIsIllustrated() {
        // 除外は無い（倉庫のゲームも含む。盆栽・いろリレー・バックギャモン・スピードは #2386 で図を足した）。
        for guide in HowToPlayGuide.all {
            #expect(!guide.items.isEmpty, "\(guide.gameID) の遊び方が図入りでない")
        }
    }

    @Test("とことんの「？」は gameID が同じで all に入らず、違うのは勝ち方の項目だけ")
    func shiritoriEndlessVariant() {
        let quota = HowToPlayGuide.shiritori
        let endless = HowToPlayGuide.shiritoriEndless
        #expect(endless.gameID == ShiritoriModule().id)
        #expect(!HowToPlayGuide.all.contains(endless))
        #expect(quota.items[0] != endless.items[0])
        #expect(Array(quota.items.dropFirst()) == Array(endless.items.dropFirst()))
        #expect(ShiritoriMode.quota.howToPlayGuide.items.map(\.text) == quota.items.map(\.text))
        #expect(ShiritoriMode.endless.howToPlayGuide.items.map(\.text) == endless.items.map(\.text))
    }

    @Test("カードしりとりの開始シートは、選んでいる遊び方の項目を常時と折りたたみに分けて全部出す")
    func shiritoriSetupSheetShowsEveryItem() {
        for mode in ShiritoriMode.allCases {
            let all = mode.howToPlayGuide.items.map(\.text)
            let shown = (mode.setupKeyItems + mode.setupDetailItems).map(\.text)
            #expect(Set(shown) == Set(all) && shown.count == all.count, "\(mode) の開始シートに出ない項目がある")
            #expect(mode.setupKeyItems.first?.text == all.first)
        }
    }

    @Test("画面のヘッダーの「？」と開始シートは図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("Game2048/Game2048View.swift", ".howToPlay(HowToPlayGuide.game2048.illustrated(Game2048HowToFigures.items)", "2048"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameMinesweeper/MinesweeperView.swift", ".howToPlay(HowToPlayGuide.minesweeper.illustrated(MinesweeperHowToFigures.items)", "minesweeper"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameSudoku/SudokuView.swift", ".howToPlay(HowToPlayGuide.sudoku.illustrated(SudokuHowToFigures.items)", "sudoku"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameBlocks/BlocksView.swift", ".howToPlay(HowToPlayGuide.blocks.illustrated(BlocksHowToFigures.items)", "blocks"),
            ("GameFifteen/FifteenView.swift", ".howToPlay(HowToPlayGuide.fifteen.illustrated(FifteenHowToFigures.items)", "fifteen"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameAnzan/AnzanView.swift", ".howToPlay(HowToPlayGuide.anzan.illustrated(AnzanHowToFigures.items)", "anzan"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameAkariKeshi/AkariKeshiView.swift", ".howToPlay(HowToPlayGuide.akariKeshi.illustrated(AkariKeshiHowToFigures.items))", "akarikeshi"),
            ("GameTsunagi/TsunagiView.swift", ".howToPlay(HowToPlayGuide.tsunagi.illustrated(TsunagiHowToFigures.items))", "tsunagi"),
            ("GameDiceCombo/DiceComboView.swift", ".howToPlay(HowToPlayGuide.diceCombo.illustrated(DiceComboHowToFigures.items)", "dicecombo"),  // 後ろに .onboarding(...)（#2826）が続く
            ("GameShiritori/ShiritoriView.swift", ".howToPlay(model.mode.howToPlayGuide", "shiritori"),
            ("GameShiritori/ShiritoriView.swift", "mode.setupKeyItems", "shiritori の開始シート"),
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(expected), "\(name) の「？」が図入りの版でない")
        }
    }
}

// MARK: - 図がなかった本の図（#2386）

@Suite("盆栽・いろリレー・バックギャモン・スピードの図入りの遊び方")
@MainActor
struct LateIllustratedHowToFiguresTests {
    private var pairs: [(name: String, guide: HowToPlayGuide, figures: [@MainActor @Sendable () -> AnyView])] {
        [
            ("fruits", .fruits, FruitsHowToFigures.items),
            ("colorRelay", .colorRelay, ColorRelayHowToFigures.items),
            ("backgammon", .backgammon, BackgammonHowToFigures.items),
            ("speed", .speed, SpeedHowToFigures.items),
        ]
    }

    @Test("項目ごとに図が 1 つずつあり、図を差し込んでも文言は変わらない")
    func everyItemHasFigure() {
        for (name, guide, figures) in pairs {
            #expect(!guide.items.isEmpty, "\(name) に図入りの項目が無い")
            #expect(figures.count == guide.items.count, "\(name): 図と項目の数がずれている")
            let illustrated = guide.illustrated(figures)
            #expect(illustrated.items.allSatisfy { $0.figure != nil })
            #expect(illustrated.items.map(\.text) == guide.items.map(\.text))
            #expect(illustrated.notes == guide.notes)
        }
    }

    @Test("画面のヘッダーの「？」は図入りの版をつなぐ")
    func viewsWireIllustratedGuide() throws {
        let files: [(String, String, String)] = [
            ("GameFruits/FruitsView.swift", "HowToPlayGuide.fruits.illustrated(FruitsHowToFigures.items)", "fruits"),
            ("GameColorRelay/ColorRelayView.swift", "HowToPlayGuide.colorRelay.illustrated(ColorRelayHowToFigures.items)", "colorRelay"),
            ("GameBackgammon/BackgammonView.swift", "HowToPlayGuide.backgammon.illustrated(BackgammonHowToFigures.items)", "backgammon"),
            ("GameSpeed/SpeedView.swift", "HowToPlayGuide.speed.illustrated(SpeedHowToFigures.items)", "speed"),
        ]
        for (path, expected, name) in files {
            let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/" + path))
            #expect(code.contains(".howToPlay(" + expected), "\(name) の「？」が図入りの版でない")
        }
    }
}
