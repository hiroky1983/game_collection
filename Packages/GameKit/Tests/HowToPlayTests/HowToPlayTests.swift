import Testing
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
import GameRoulette
import GameFruits
import GameColorRelay
import GameAnzan
import GameBackgammon
import GameSpeed
import GameHomerun
import GameSpider
import GameChess
import GameBlocks
import GameOjisanPuzzle

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
    RouletteModule(),
    FruitsModule(),
    ColorRelayModule(),
    AnzanModule(),
    BackgammonModule(),
    SpeedModule(),
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
