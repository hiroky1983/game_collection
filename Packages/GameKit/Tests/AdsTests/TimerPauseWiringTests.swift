import Testing
import Foundation
import GameKitTestSupport
@testable import Core

/// 計時のあるゲームは、広告のロード〜視聴中に計時を止める（#1382）。
///
/// 全画面広告は `onDisappear` を発火させないので、View に結線が無いと広告の 15〜30 秒が
/// クリアタイム（自己ベスト）に乗る。ソースを走査して、対象画面の救済がすべて
/// `gameTimerLifecycle(rescues:)`（中で `pausesTimerWhileWatching` に渡す・#1857）に渡っていることを固定する。
@Suite("広告視聴中の計時停止の結線（#1382）")
struct TimerPauseWiringTests {
    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

    /// 計時（`pauseTimer` を持つ）とリワード救済の両方があるゲームの View。
    private static let timedViews = [
        "GameSudoku/SudokuView.swift",
        "GameSolitaire/SolitaireView.swift",
        "GameFreeCell/FreeCellView.swift",
        "GameSpider/SpiderView.swift",
        "GameMahjongSolitaire/MahjongSolitaireView.swift",
    ]

    @Test("計時のあるゲームの救済は、すべて計時の一時停止に結線している")
    func everyRescueOfTimedGamesPausesTheTimer() throws {
        let declaration = try NSRegularExpression(pattern: #"var (\w+) = RewardedRescue\(\)"#)
        for path in Self.timedViews {
            let text = try String(contentsOf: Self.sourcesRoot.appendingPathComponent(path), encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            let names = declaration.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
            #expect(!names.isEmpty, "\(path): 救済の宣言が読めていない")
            guard let start = text.range(of: ".gameTimerLifecycle(\n            rescues: [") else {
                Issue.record("\(path): gameTimerLifecycle(rescues:) が無い")
                continue
            }
            let list = text[start.upperBound...].prefix { $0 != "]" }
            for name in names {
                #expect(list.contains(name), "\(path): \(name) が計時の一時停止に渡っていない")
            }
        }
    }

    @Test("gameTimerLifecycle は救済の視聴中に計時を止める（pausesTimerWhileWatching に渡す）")
    func lifecycleModifierPausesWhileWatching() throws {
        let text = try String(contentsOf: Self.sourcesRoot.appendingPathComponent("Core/GameClockLabel.swift"), encoding: .utf8)
        #expect(text.contains(".pausesTimerWhileWatching(rescues, pause: pause, resume: resume)"))
    }

    // MARK: - シート表示中の計時停止（#2406）

    @Test("止める要因が 1 つでもあれば動かさない（シート・遊び方・広告）")
    func holdPolicy() {
        #expect(GameTimerHold.allowsRunning(isHeld: false, isHowToPlayOpen: false, rescueHoldsClock: false))
        #expect(!GameTimerHold.allowsRunning(isHeld: true, isHowToPlayOpen: false, rescueHoldsClock: false))
        #expect(!GameTimerHold.allowsRunning(isHeld: false, isHowToPlayOpen: true, rescueHoldsClock: false))
        #expect(!GameTimerHold.allowsRunning(isHeld: false, isHowToPlayOpen: false, rescueHoldsClock: true))
    }

    @Test("gameTimerLifecycle は「遊び方」の表示を読み、isHeld の変化で止める・再開する")
    func lifecycleObservesHowToPlayAndHeld() throws {
        let life = try String(contentsOf: Self.sourcesRoot.appendingPathComponent("Core/GameClockLabel.swift"), encoding: .utf8)
        #expect(life.contains(".onPreferenceChange(HowToPlayPresentedKey.self)"))
        #expect(life.contains(".onChange(of: isHeld || isHowToPlayOpen)"))
        let how = try String(contentsOf: Self.sourcesRoot.appendingPathComponent("Core/HowToPlay.swift"), encoding: .utf8)
        #expect(how.contains(".preference(key: HowToPlayPresentedKey.self, value: isPresented)"))
    }

    /// タイムを競う 8 本。新規ゲーム・開始のシートを `@State` で開く画面は、その真偽値を `isHeld` に渡す。
    @Test("タイムを競うゲームは、開いているシートを isHeld に渡している",
          arguments: [
            "GameSudoku/SudokuView.swift", "GameMinesweeper/MinesweeperView.swift",
            "GameSolitaire/SolitaireView.swift", "GameSpider/SpiderView.swift",
            "GameFreeCell/FreeCellView.swift", "GameHanoi/HanoiView.swift",
            "GameMahjongSolitaire/MahjongSolitaireView.swift", "GameAkariKeshi/AkariKeshiView.swift",
          ])
    func timedGamesHoldWhileSheetIsOpen(path: String) throws {
        let text = try String(contentsOf: Self.sourcesRoot.appendingPathComponent(path), encoding: .utf8)
        let start = try #require(text.range(of: ".gameTimerLifecycle("), "\(path): gameTimerLifecycle が無い")
        let call = String(text[start.upperBound...].prefix(while: { $0 != ")" || false }).prefix(400))
        for flag in ["showNewGame", "showSetup"] where text.contains(".sheet(isPresented: $\(flag)") {
            #expect(call.contains("isHeld:") && call.contains(flag), "\(path): \(flag) のシート表示中に計時を止めていない")
        }
    }

    /// 確認ダイアログ・アラートを出している間も計時が進み、迷った時間がタイムに乗っていた（#3143）。
    @Test("タイムを競うゲームは、確認ダイアログ・アラートの表示中も isHeld で計時を止めている",
          arguments: [
            "GameSudoku/SudokuView.swift", "GameMinesweeper/MinesweeperView.swift",
            "GameSolitaire/SolitaireView.swift", "GameSpider/SpiderView.swift",
            "GameFreeCell/FreeCellView.swift", "GameHanoi/HanoiView.swift",
            "GameMahjongSolitaire/MahjongSolitaireView.swift", "GameAkariKeshi/AkariKeshiView.swift",
          ])
    func timedGamesHoldWhileConfirmIsShown(path: String) throws {
        let text = try String(contentsOf: Self.sourcesRoot.appendingPathComponent(path), encoding: .utf8)
        let start = try #require(text.range(of: ".gameTimerLifecycle("), "\(path): gameTimerLifecycle が無い")
        let call = String(text[start.upperBound...].prefix(600))
        let pattern = try NSRegularExpression(pattern: #"\.(?:confirmationDialog|alert)\([^\n]*isPresented: \$(\w+)"#)
        let flags = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
        // 広告の視聴は救済側（`rescues`）が止める。ここで見るのは `@State` の真偽値で出す確認だけ。
        for flag in flags where text.contains("@State private var \(flag)") {
            #expect(call.contains("isHeld:") && call.contains(flag), "\(path): \(flag) の確認表示中に計時を止めていない")
        }
    }
}
