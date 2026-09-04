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
import GameChess

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
    BlackjackModule(),
    DaifugoModule(),
    MahjongSolitaireModule(),
    SolitaireModule(),
    MahjongModule(),
    SudokuModule(),
    GoModule(),
    ChessModule(),
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
