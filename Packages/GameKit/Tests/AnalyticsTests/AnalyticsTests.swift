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
import MahjongTiles

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 送信されたイベントをそのまま溜めるスパイ。Firebase もネットワークも使わない。
@MainActor
private final class SpyAnalyticsService: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []

    func log(_ event: AnalyticsEvent) { events.append(event) }

    var starts: [String] {
        events.compactMap { if case let .gameStart(gameID) = $0 { return gameID } else { return nil } }
    }
    var ends: [(gameID: String, outcome: GameOutcome, durationSec: Int)] {
        events.compactMap {
            if case let .gameEnd(gameID, outcome, durationSec) = $0 {
                return (gameID, outcome, durationSec)
            }
            return nil
        }
    }
    func starts(of gameID: String) -> Int { starts.filter { $0 == gameID }.count }
    func ends(of gameID: String) -> Int { ends.filter { $0.gameID == gameID }.count }
}

/// 壊れた神経衰弱の中断データ（配列の長さが食い違う）。
///
/// 復元側の `ConcentrationSnapshot` は `private` で外から作れないため、**同じ鍵を持つ**
/// 別の構造体を保存して JSON を作る（デコードは通り、健全性チェックだけが落ちる）。
private struct BrokenConcentrationSnapshot: Codable {
    var symbols: [String] = ["a", "a", "b", "b"]
    var isFaceUp: [Bool] = [false]              // ← symbols と長さが合わない
    var isMatched: [Bool] = [false, false, false, false]
    var currentPlayer: Int = 0
    var playerScore: Int = 0
    var cpuScore: Int = 0
    var pairCount: Int = 6
    var cpuLevel: Int = 1
    var mattaUsed: Bool = false
}

/// ハブに登録済みのゲーム ID。
///
/// 本番は `AppEnvironment.registry.modules.map(\.id)` から作る。テストは App ターゲットへ
/// 依存できないため `GameRegistry` を組み直すが、**ID の文字列は書かず各 `GameModule` の
/// `id` から取る**（`ReviewRequestTests` と同じやり方）。こうしておくと、どれかのモジュールの
/// `id` が変わったときに実装と一緒にここも追従し、値がずれない。
///
/// - Note: ハブへ**新しいゲームを追加**したときは、この配列にもモジュールを1行足す必要がある
///   （PR #162 の CodeRabbit 指摘。Core は各ゲームに依存できないため、Core 側の定数にはできない）。
/// - Note: `GameModule` は `Sendable` ではないため、配列をグローバルに置かず関数の中で組む。
private func makeHubGameIDs() -> Set<String> {
    let modules: [GameModule] = [
        Game2048Module(), ShogiModule(), GomokuModule(), MinesweeperModule(), OthelloModule(),
        PokerModule(), ConcentrationModule(), BlackjackModule(), DaifugoModule(),
        MahjongSolitaireModule(), MahjongModule(),
    ]
    return Set(GameRegistry(modules).modules.map(\.id))
}

private let hubGameIDs: Set<String> = makeHubGameIDs()

/// 進む時計。**実時間を待たない**（実時間の待ち合わせは並列実行で落ちるため）。
@MainActor
private final class TestClock {
    private var seconds: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    func advance(_ interval: TimeInterval) { seconds += interval }
}

@MainActor
private func makeAnalytics(
    enabled: Bool = true,
    clock: TestClock = TestClock(),
    allowedGameIDs: Set<String> = hubGameIDs
) -> (GameAnalytics, SpyAnalyticsService) {
    let spy = SpyAnalyticsService()
    let analytics = GameAnalytics(
        service: GatedAnalyticsService(base: spy) { enabled },
        allowedGameIDs: allowedGameIDs,
        now: { clock.now }
    )
    return (analytics, spy)
}

@MainActor
private func makeServices(
    enabled: Bool = true,
    clock: TestClock = TestClock(),
    snapshots: SnapshotStore = MemorySnapshotStore()
) -> (GameServices, SpyAnalyticsService) {
    let (analytics, spy) = makeAnalytics(enabled: enabled, clock: clock)
    let services = GameServices(
        snapshots: snapshots,
        ads: NoopAdService(),
        analytics: analytics
    )
    return (services, spy)
}

// MARK: - 送信するイベントの形

@Suite("送信するイベントの形")
struct AnalyticsEventShapeTests {

    @Test("イベントは game_start / game_end の2種だけで、パラメータも決まった鍵しか持たない")
    func namesAndParameters() {
        #expect(AnalyticsEvent.gameStart(gameID: "2048").name == "game_start")
        #expect(AnalyticsEvent.gameStart(gameID: "2048").parameters == ["game_id": .string("2048")])

        let end = AnalyticsEvent.gameEnd(gameID: "shogi", outcome: .win, durationSec: 42)
        #expect(end.name == "game_end")
        #expect(end.parameters == [
            "game_id": .string("shogi"),
            "result": .string("win"),
            "duration_sec": .int(42),
        ])
        #expect(Set(end.parameters.keys) == ["game_id", "result", "duration_sec"],
                "受け入れ条件どおり3鍵のみ。スコアや端末識別子の鍵は存在しない")
    }

    @Test("result は win / loss / draw の3値に閉じている")
    func resultIsClosed() {
        // GameOutcome 以外の値を渡す経路が無いことを、全ケースの網羅で示す。
        let outcomes: [GameOutcome] = [.win, .loss, .draw]
        let sent = outcomes.map { outcome -> String in
            guard case let .string(text)? = AnalyticsEvent
                .gameEnd(gameID: "2048", outcome: outcome, durationSec: 0)
                .parameters["result"] else { return "" }
            return text
        }
        #expect(sent == ["win", "loss", "draw"])
    }
}

// MARK: - 発火の抑制と経過秒（GameAnalytics 単体）

@Suite("プレイの数え方")
@MainActor
struct GameAnalyticsTests {

    @Test("開始1回・終局1回で1組。経過秒は開始からの差")
    func onePairPerPlay() {
        let clock = TestClock()
        let (analytics, spy) = makeAnalytics(clock: clock)

        analytics.startPlay(gameID: "2048")
        clock.advance(75)
        analytics.finishPlay(gameID: "2048", outcome: .loss)

        #expect(spy.starts == ["2048"])
        #expect(spy.ends.count == 1)
        #expect(spy.ends.first?.outcome == .loss)
        #expect(spy.ends.first?.durationSec == 75)
    }

    @Test("同じゲームで startPlay を繰り返しても game_start は増えない（再描画・復帰）")
    func startPlayIsIdempotent() {
        let (analytics, spy) = makeAnalytics()
        for _ in 0..<10 { analytics.startPlay(gameID: "2048") }
        #expect(spy.starts.count == 1)
    }

    @Test("終局後の startPlay も増えない（リザルト表示中の再描画）")
    func startPlayAfterFinishIsIgnored() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        for _ in 0..<10 { analytics.startPlay(gameID: "2048") }
        #expect(spy.starts.count == 1)
        #expect(spy.ends.count == 1)
    }

    @Test("「新しいゲーム」は必ず次の1プレイとして数える")
    func restartAlwaysCounts() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        #expect(spy.starts.count == 3)
    }

    @Test("終局が二度来ても game_end は1回だけ")
    func finishIsNotSentTwice() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        analytics.finishPlay(gameID: "2048", outcome: .win)
        #expect(spy.ends.count == 1)
        #expect(spy.ends.first?.outcome == .loss)
    }

    @Test("開始を数えていないプレイの終局は送らない（中断からの再開）")
    func finishWithoutStartSendsNothing() {
        let (analytics, spy) = makeAnalytics()
        analytics.finishPlay(gameID: "2048", outcome: .win)
        #expect(spy.events.isEmpty)
    }

    @Test("終局したあと画面を離れると、次に開いたときが新しい1プレイになる")
    func leavingGameAllowsNextPlay() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        analytics.leaveGame(gameID: "2048")
        analytics.startPlay(gameID: "2048")
        #expect(spy.starts.count == 2)
        #expect(spy.ends.count == 1)
    }

    @Test("遊びかけで画面を離れても進行中の扱いは続き、戻って終局すれば game_end が出る")
    func leavingMidPlayKeepsItInFlight() {
        let clock = TestClock()
        let (analytics, spy) = makeAnalytics(clock: clock)
        analytics.startPlay(gameID: "2048")
        clock.advance(40)
        analytics.leaveGame(gameID: "2048")   // ハブへ戻った（まだ遊びかけ）
        clock.advance(20)
        analytics.startPlay(gameID: "2048")   // 「続きから」で再開 → 数え直さない
        clock.advance(30)
        analytics.finishPlay(gameID: "2048", outcome: .loss)

        #expect(spy.starts.count == 1, "再開で game_start は増えない")
        #expect(spy.ends.count == 1, "遊び切ったので game_end は出る")
        #expect(spy.ends.first?.durationSec == 90, "経過秒は最初の開始からの通算")
    }

    @Test("遊びかけで離れたあと「新しいゲーム」を選べば次の1プレイとして数える")
    func leavingMidPlayThenRestart() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.leaveGame(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        #expect(spy.starts.count == 2, "遊びかけの1回 + 新しいゲームの1回")
        #expect(spy.ends.count == 1, "終局したのは後者だけ")
    }

    @Test("ゲームごとに独立して数える")
    func playsAreTrackedPerGame() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.startPlay(gameID: "shogi")
        analytics.finishPlay(gameID: "shogi", outcome: .win)
        #expect(spy.starts == ["2048", "shogi"])
        #expect(spy.ends.map(\.gameID) == ["shogi"])
    }

    @Test("送信対象の gameID はハブの登録内容と一致する（11本）")
    func allowedGameIDsMatchHub() {
        #expect(hubGameIDs.count == 11, "ハブに並ぶゲームは11本")
        // 各 Model が使う gameID と、ハブのモジュールの id が食い違っていないこと。
        // 食い違うと、そのゲームのイベントだけ丸ごと捨てられて気付けない。
        let (services, spy) = makeServices()
        _ = Game2048Model(services: services)
        #expect(spy.starts == ["2048"], "Model の gameID がモジュールの id と一致している")
    }

    @Test("登録されていない gameID は送らない（任意の文字列が game_id にならない）")
    func unknownGameIDsAreDropped() {
        let (analytics, spy) = makeAnalytics(allowedGameIDs: ["2048"])
        analytics.startPlay(gameID: "../../etc/passwd")
        analytics.restartPlay(gameID: "device-1234-ABCD")
        analytics.finishPlay(gameID: "device-1234-ABCD", outcome: .win)
        #expect(spy.events.isEmpty)

        analytics.startPlay(gameID: "2048")
        #expect(spy.starts == ["2048"], "登録済みの ID は通る")
    }

    @Test("時計が巻き戻っても duration_sec は負にならない")
    func durationIsNeverNegative() {
        let clock = TestClock()
        let (analytics, spy) = makeAnalytics(clock: clock)
        analytics.startPlay(gameID: "2048")
        clock.advance(-500)
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        #expect(spy.ends.first?.durationSec == 0)
    }
}

// MARK: - 設定のオン / オフ

@Suite("解析送信の設定トグル")
@MainActor
struct AnalyticsToggleTests {

    @Test("オフのあいだは1度も logEvent が呼ばれない")
    func offSendsNothing() {
        let (analytics, spy) = makeAnalytics(enabled: false)
        analytics.startPlay(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .win)
        #expect(spy.events.isEmpty, "オフでは送信実装へ委譲しない")
    }

    @Test("オフのままゲームを1本遊び切っても送信は0件")
    func offDuringWholePlay() {
        let (services, spy) = makeServices(enabled: false)
        let model = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(model.gameOver, "終局まで遊んでいる")
        #expect(spy.events.isEmpty)
    }

    /// 設定トグルを再現する道具。`setEnabled` は本番で `GameSettings.analyticsEnabled` の
    /// `didSet` が行うのと同じ2つ（送信可否の切り替えと `discardPlayState()`）をまとめて行う。
    @MainActor
    private final class ToggleHarness {
        /// 送信可否。`GatedAnalyticsService` に閉じ込めた判定の裏側を書き換えるための箱。
        private final class Flag { var isOn: Bool; init(_ isOn: Bool) { self.isOn = isOn } }

        let spy: SpyAnalyticsService
        let analytics: GameAnalytics
        private let flag: Flag

        init(enabled: Bool = true, clock: TestClock = TestClock()) {
            let spy = SpyAnalyticsService()
            let flag = Flag(enabled)
            self.spy = spy
            self.flag = flag
            self.analytics = GameAnalytics(
                service: GatedAnalyticsService(base: spy) { flag.isOn },
                allowedGameIDs: hubGameIDs,
                now: { clock.now }
            )
        }

        func setEnabled(_ value: Bool) {
            flag.isOn = value
            analytics.discardPlayState()
        }
    }

    @Test("オフ中に開始したプレイは、オンに戻して終局しても game_end を送らない（#212 シナリオ1）")
    func playStartedWhileOffSendsNoEnd() {
        let harness = ToggleHarness(enabled: false)
        harness.analytics.startPlay(gameID: "2048")   // オフなので game_start は送られない
        harness.setEnabled(true)                      // 設定をオンに戻す
        harness.analytics.finishPlay(gameID: "2048", outcome: .win)
        #expect(harness.spy.events.isEmpty, "対応する game_start の無い game_end を送らない")
    }

    @Test("オフ期間をまたいだプレイは終局しても game_end を送らない（duration にオフ期間が混ざらない・#212 シナリオ2）")
    func playSpanningOffPeriodSendsNoEnd() {
        let clock = TestClock()
        let harness = ToggleHarness(clock: clock)
        harness.analytics.startPlay(gameID: "2048")
        #expect(harness.spy.starts == ["2048"], "オンで始めたので game_start は出る")

        clock.advance(30)
        harness.setEnabled(false)   // 遊びかけでオフにする
        clock.advance(600)          // この時間が duration_sec に混ざってはいけない
        harness.setEnabled(true)
        harness.analytics.finishPlay(gameID: "2048", outcome: .win)

        #expect(harness.spy.ends.isEmpty, "設定をまたいだプレイの終局は送らない")
    }

    @Test("設定を切り替えたあとに始めたプレイは、通常どおり1組で送られる")
    func playStartedAfterToggleIsCountedNormally() {
        let clock = TestClock()
        let harness = ToggleHarness(enabled: false, clock: clock)
        harness.setEnabled(true)
        harness.analytics.startPlay(gameID: "2048")
        clock.advance(12)
        harness.analytics.finishPlay(gameID: "2048", outcome: .loss)
        #expect(harness.spy.starts.count == 1)
        #expect(harness.spy.ends.count == 1, "オンのあいだに始めて終わったプレイは1組そろう")
        #expect(harness.spy.ends.first?.durationSec == 12, "経過秒は切り替え後の開始からの差")
    }
}

// MARK: - 二重発火の抑制（実際の Model 経路）

@Suite("二重発火の抑制")
@MainActor
struct AnalyticsDoubleFireTests {

    @Test("画面の再描画で Model が作り直されても game_start は増えない")
    func reRenderDoesNotAddStarts() {
        // SwiftUI は親の再描画のたびに `State(initialValue: Model(services:))` を評価するため、
        // 同じ services で Model が何度も作られる。それを実際に再現する。
        let (services, spy) = makeServices()
        _ = Game2048Model(services: services)
        _ = Game2048Model(services: services)
        _ = Game2048Model(services: services)
        #expect(spy.starts(of: "2048") == 1)
    }

    @Test("「続きから」での再開では game_start を数えない")
    func resumingSavedGameDoesNotStart() {
        let snapshots = MemorySnapshotStore()
        let (first, spyFirst) = makeServices(snapshots: snapshots)
        let model = Game2048Model(services: first)
        model.move(.left)
        model.move(.up)
        #expect(spyFirst.starts(of: "2048") == 1, "初回の開始は1回")
        #expect(snapshots.exists(for: "2048"), "中断の保存がある")

        // 再起動相当: 同じ保存先から作り直す（送信側は新しいスパイ = 記憶を持たない）。
        let (resumed, spyResumed) = makeServices(snapshots: snapshots)
        _ = Game2048Model(services: resumed)
        _ = Game2048Model(services: resumed)
        #expect(spyResumed.events.isEmpty, "続きからは新しいプレイではないので何も送らない")
    }

    @Test("遊びかけでハブに戻り、続きから再開して終局すると game_end が出る（実際の Model 経路）")
    func leaveThenResumeThenFinishSendsEnd() {
        let snapshots = MemorySnapshotStore()
        let (services, spy) = makeServices(snapshots: snapshots)

        let first = Game2048Model(services: services)
        first.move(.left)
        first.move(.up)
        #expect(spy.starts(of: "2048") == 1)

        // ハブへ戻る（`HubView` が path の変化で呼ぶ経路）。
        services.gameDidLeave(gameID: "2048")

        // 「続きから」で開き直して終局まで遊ぶ。
        let resumed = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                resumed.move(direction)
                if resumed.gameOver { break outer }
            }
        }
        #expect(resumed.gameOver)
        #expect(spy.starts(of: "2048") == 1, "再開で game_start は増えない")
        #expect(spy.ends(of: "2048") == 1, "遊び切ったぶんが「始めたのに終わっていない」に落ちない")
    }

    @Test("神経衰弱: 壊れた中断データからのフォールバックは新しい1プレイとして数える（#212）")
    func concentrationBrokenSnapshotCountsAsFreshStart() {
        let snapshots = MemorySnapshotStore()
        // 復元側の健全性チェック（配列長が揃っていること）に引っかかる中断データを置く。
        // `ConcentrationSnapshot` は private のため、同じ鍵を持つ構造体を保存して再現する。
        try? snapshots.save(BrokenConcentrationSnapshot(), for: "concentration")

        let (services, spy) = makeServices(snapshots: snapshots)
        let model = ConcentrationModel(services: services)

        #expect(model.cards.isEmpty == false, "壊れたデータでも新しい盤で始まる")
        #expect(spy.starts(of: "concentration") == 1,
                "復元できず新しい盤で始まったので、続く終局が捨てられないよう game_start を数える")

        // 実際に遊び切ると game_end と1組になる（開始を数えていないと捨てられていた）。
        for _ in 0..<model.cards.count where !model.isGameOver {
            let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
            guard let first = unmatched.first,
                  let second = unmatched.first(where: {
                      $0 != first && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            if model.firstFlippedIndex == nil { model.tap(index: first) }
            model.tap(index: second)
        }
        #expect(model.isGameOver)
        #expect(spy.ends(of: "concentration") == 1)
    }

    @Test("神経衰弱: 正しい中断データからの復元では game_start を数えない")
    func concentrationValidSnapshotDoesNotStart() {
        let snapshots = MemorySnapshotStore()
        let (first, spyFirst) = makeServices(snapshots: snapshots)
        let model = ConcentrationModel(services: first)
        model.tap(index: 0)   // 保存が走る手を1つ指す
        #expect(spyFirst.starts(of: "concentration") == 1, "初回の開始は1回")
        #expect(snapshots.exists(for: "concentration"))

        let (resumed, spyResumed) = makeServices(snapshots: snapshots)
        _ = ConcentrationModel(services: resumed)
        #expect(spyResumed.events.isEmpty, "続きからは新しいプレイではないので何も送らない")
    }

    @Test("バックグラウンド復帰の計時再開では何も送らない")
    func resumingTimerDoesNotSend() {
        let (services, spy) = makeServices()
        let model = MinesweeperModel(services: services)
        // 初手で全安全マスが開ききって即クリアにならない大きさを選ぶ（終局を挟まずに復帰を試す）。
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        #expect(model.gameState == .playing, "プレイ中のまま")
        #expect(spy.starts(of: "minesweeper") == 1)

        // 復帰のたびに View から呼ばれる経路を何度も叩く。
        for _ in 0..<5 { model.resumeTimerIfNeeded() }
        #expect(spy.starts(of: "minesweeper") == 1)
        #expect(spy.ends(of: "minesweeper") == 0)

        let mahjong = MahjongSolitaireModel(services: services, seed: 909)
        #expect(spy.starts(of: "mahjong") == 1)
        for _ in 0..<5 { mahjong.resumeTimerIfNeeded() }
        #expect(spy.starts(of: "mahjong") == 1)
    }

    @Test("盤を用意しただけ（未着手）では game_start を数えない: マインスイーパー")
    func minesweeperCountsOnFirstTap() {
        let (services, spy) = makeServices()
        let model = MinesweeperModel(services: services)
        #expect(spy.events.isEmpty, "画面を開いただけでは数えない")
        model.newGame(rows: 3, cols: 3, mines: 1)
        #expect(spy.events.isEmpty, "難易度を選び直しただけでも数えない")
        model.tap(row: 0, col: 0)
        #expect(spy.starts(of: "minesweeper") == 1, "地雷が置かれて計時が始まった時点で1回")
    }

    @Test("コンティニューは続きを次の1プレイとして数え、game_end と対応が崩れない")
    func continueAfterAdKeepsPairs() {
        let (services, spy) = makeServices()
        let model = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(spy.starts(of: "2048") == 1)
        #expect(spy.ends(of: "2048") == 1)

        model.continueAfterAd()
        #expect(model.gameOver == false)
        #expect(spy.starts(of: "2048") == 2, "続きは次の1プレイ")
        #expect(spy.ends(of: "2048") == 1, "game_end が1つの game_start に2回付くことはない")
    }
}

// MARK: - 全10ゲームで1プレイ1組

@Suite("全10ゲームの発火（1プレイにつき game_start 1回・終局で game_end 1回）")
@MainActor
struct AllGamesAnalyticsTests {

    /// 1プレイぶんの発火を検証する共通の確認。
    private func expectOnePair(
        _ spy: SpyAnalyticsService,
        gameID: String,
        durationSec: Int? = nil
    ) {
        #expect(spy.starts(of: gameID) == 1, "\(gameID): game_start が \(spy.starts(of: gameID)) 回")
        #expect(spy.ends(of: gameID) == 1, "\(gameID): game_end が \(spy.ends(of: gameID)) 回")
        #expect(spy.events.count == 2, "\(gameID): 送ったイベントは2件だけ")
        if let durationSec {
            #expect(spy.ends.first?.durationSec == durationSec)
        }
    }

    @Test("2048: 開いた時点で開始・ゲームオーバーで終局（loss）")
    func game2048() {
        let clock = TestClock()
        let (services, spy) = makeServices(clock: clock)
        let model = Game2048Model(services: services)
        clock.advance(31)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(model.gameOver)
        expectOnePair(spy, gameID: "2048", durationSec: 31)
        #expect(spy.ends.first?.outcome == .loss, "2048 に勝ちは無い")
    }

    @Test("将棋: 開いた時点で開始・投了で終局（loss）")
    func shogi() {
        let (services, spy) = makeServices()
        let model = ShogiGameModel(services: services)
        model.resign()
        #expect(model.gameOver)
        expectOnePair(spy, gameID: "shogi")
        #expect(spy.ends.first?.outcome == .loss)
    }

    @Test("五目並べ: 開いた時点で開始・投了で終局（loss）")
    func gomoku() {
        let (services, spy) = makeServices()
        let model = GomokuModel(services: services)
        model.resign()
        expectOnePair(spy, gameID: "gomoku")
        #expect(spy.ends.first?.outcome == .loss)
    }

    @Test("マインスイーパー: 初手で開始・全マス開放で終局（win）")
    func minesweeper() {
        let (services, spy) = makeServices()
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 2, cols: 2, mines: 1)
        model.tap(row: 0, col: 0)
        for r in 0..<2 {
            for c in 0..<2 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }
        #expect(model.gameState == .won)
        expectOnePair(spy, gameID: "minesweeper")
        #expect(spy.ends.first?.outcome == .win)
    }

    @Test("オセロ: 開いた時点で開始・投了で終局（loss）")
    func othello() {
        let (services, spy) = makeServices()
        let model = OthelloModel(services: services)
        model.resign()
        expectOnePair(spy, gameID: "othello")
        #expect(spy.ends.first?.outcome == .loss)
    }

    @Test("ポーカー: 配られた時点で開始・ラウンド決着で終局")
    func poker() {
        let (services, spy) = makeServices()
        let model = PokerModel(services: services)
        #expect(spy.events.isEmpty, "画面を開いただけではラウンドが始まらない")
        model.startGame()
        model.bet1Action(.check)
        if model.phase == .exchange { model.confirmExchange() }
        if model.phase == .betting2 { model.bet2Action(.check) }
        if model.phase == .betting2, model.currentBet > 0 { model.callCPUBet() }
        #expect(model.phase == .result)
        expectOnePair(spy, gameID: "poker")
    }

    @Test("神経衰弱: 開いた時点で開始・全ペア成立で終局")
    func concentration() {
        let (services, spy) = makeServices()
        let model = ConcentrationModel(services: services)
        for _ in 0..<model.cards.count where !model.isGameOver {
            let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
            guard let first = unmatched.first,
                  let second = unmatched.first(where: {
                      $0 != first && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            if model.firstFlippedIndex == nil { model.tap(index: first) }
            model.tap(index: second)
        }
        #expect(model.isGameOver)
        expectOnePair(spy, gameID: "concentration")
    }

    @Test("ブラックジャック: 配られた時点で開始・ラウンド決着で終局")
    func blackjack() {
        let (services, spy) = makeServices()
        let model = BlackjackModel(services: services)
        #expect(spy.events.isEmpty, "ベット前はラウンドが始まらない")
        model.placeBet(100)
        if model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result)
        expectOnePair(spy, gameID: "blackjack")
    }


    @Test("大富豪: 配られた時点で開始・決着で終局")
    func daifugo() async {
        let (services, spy) = makeServices()
        let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 2026)
        #expect(spy.events.isEmpty, "画面を開いただけでは配られない")
        model.startGame()
        for _ in 0..<500 where model.phase == .playing {
            await model.runCPUTurnsIfNeeded()
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if let play = DaifugoRules.greedyPlay(
                hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
            ) {
                for card in play { model.toggleSelection(card) }
                model.playSelected()
            } else {
                model.pass()
            }
        }
        #expect(model.phase == .result)
        expectOnePair(spy, gameID: "daifugo")
    }

    @Test("四人打ち麻雀: 東風戦 1 回が 1 プレイ（局ごとには数えない）")
    func mahjongFourPlayer() async {
        let (services, spy) = makeServices()
        let model = MahjongModel(services: services, cpuDelay: .zero, seed: 4649)
        #expect(spy.events.isEmpty, "画面を開いただけでは配られない")
        model.startGame()
        await playMahjongFourPlayer(model)
        #expect(model.phase == .gameResult)
        // 東 4 局まで進んでも、開始と終局は東風戦ごとに 1 組だけ。
        expectOnePair(spy, gameID: "mahjong4")
    }

    @Test("麻雀ソリティア: 盤が配られた時点で開始・取り切りで終局（win）")
    func mahjongSolitaire() {
        let (services, spy) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 909)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        expectOnePair(spy, gameID: "mahjong")
        #expect(spy.ends.first?.outcome == .win)
    }

    @Test("麻雀ソリティア: 手詰まりで「最初から」は loss で終局し、次の盤が新しい1プレイになる")
    func mahjongGiveUpAndRestart() {
        let (services, spy) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 910)
        model.giveUpAndRestart()
        #expect(spy.starts(of: "mahjong") == 2, "諦めた回 + 配り直した回")
        #expect(spy.ends(of: "mahjong") == 1)
        #expect(spy.ends.first?.outcome == .loss)
    }

    @Test("2回続けて遊ぶと2組になる（「新しいゲーム」）")
    func twoPlaysInARow() {
        let (services, spy) = makeServices()
        let model = GomokuModel(services: services)
        model.resign()
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(spy.starts(of: "gomoku") == 2)
        #expect(spy.ends(of: "gomoku") == 2)
    }
}

// MARK: - 送信データの範囲

@Suite("送信データの範囲")
@MainActor
struct AnalyticsPayloadScopeTests {

    @Test("スコアを持つゲームでも、送るのは勝敗と経過秒だけ（点数の生値を送らない）")
    func scoresAreNotSent() {
        let (services, spy) = makeServices()
        let model = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(model.score > 0, "点数は付いている")
        let keys = spy.events.flatMap { Array($0.parameters.keys) }
        #expect(Set(keys) == ["game_id", "result", "duration_sec"])
        // 点数がどのパラメータにも現れないことを値でも確かめる。
        let ints = spy.events.flatMap { $0.parameters.values }.compactMap { value -> Int? in
            if case let .int(number) = value { return number } else { return nil }
        }
        #expect(ints.allSatisfy { $0 != model.score }, "スコアと同じ整数を送っていない")
    }
}

/// 四人打ち麻雀: 常に自摸切り・和了できるときは必ず和了する方針で東風戦を最後まで進める。
/// CPU の間合いは 0 なので実時間は待たない。
@MainActor
private func playMahjongFourPlayer(_ model: MahjongModel, rejectOnce: Bool = false) async {
    var didReject = !rejectOnce
    var guardCount = 0
    while model.phase != .gameResult, guardCount < 800 {
        guardCount += 1
        switch model.phase {
        case .playing:
            if model.currentPlayer == MahjongModel.humanIndex, let drawn = model.drawnTile {
                if !didReject {
                    didReject = true
                    // 手牌にもツモ牌にも無い牌を指定すると拒否される（警告の発火を確かめる）。
                    let absent = MahjongTileOrder.all.first {
                        model.playerHand.count(of: $0) == 0 && $0 != drawn
                    }
                    if let absent { model.discard(absent) }
                }
                if model.canDeclareTsumo {
                    model.declareTsumo()
                } else {
                    model.discard(drawn)
                }
            } else {
                await model.runCPUTurnsIfNeeded()
            }
        case .ronOffer:
            model.declareRon()
        case .handResult:
            model.advanceToNextHand()
        case .idle, .gameResult:
            return
        }
    }
}
