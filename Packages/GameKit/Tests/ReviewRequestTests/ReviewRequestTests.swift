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
import MahjongTiles

// MARK: - 共通のヘルパー

private let appVersion = "1.1.1"

/// テスト専用の UserDefaults を作る。テストごとに違う suite 名を渡すこと（並列実行のため）。
@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.review.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

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

/// 各ゲームの Model に渡す services と、そこに載せた評価リクエストサービス。
/// 遅延は 0 にして「呼ばれるかどうか」だけを見る（遅延そのものは別 Suite で検証する）。
@MainActor
private func makeServices(
    suite: String,
    now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
    delay: Duration = .zero
) -> (GameServices, ReviewRequestService) {
    let (log, _, _) = makeLog(suite: suite)
    let service = ReviewRequestService(log: log, appVersion: appVersion, now: now, delay: delay)
    let services = GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        review: service
    )
    return (services, service)
}

/// 勝利を n 回積む（判定条件を満たすところまで空回しする用）。
@MainActor
private func advanceWins(_ service: ReviewRequestService, count: Int) {
    for _ in 0..<count { service.gameDidFinish(outcome: .win) }
}

// MARK: - 発火条件（条件2〜5）

@Suite("評価リクエストの発火条件")
@MainActor
struct ReviewRequestPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("条件2: 4勝までは出ず、5勝目で初回が出る")
    func firstRequestAtFiveWins() {
        for wins in 0...4 {
            let state = ReviewRequestState(totalWins: wins)
            #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false,
                    "\(wins)勝では出さない")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: ReviewRequestState(totalWins: 5), currentVersion: appVersion, now: now) == true)
    }

    @Test("条件3: 前回から120日経つまで出ない")
    func minimumElapsed() {
        func state(_ elapsed: TimeInterval) -> ReviewRequestState {
            .init(totalWins: 100, lastRequestedAt: now.addingTimeInterval(-elapsed),
                  lastRequestedWins: 5, lastRequestedVersion: "1.1.0")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(119 * 24 * 3600), currentVersion: appVersion, now: now) == false)
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(120 * 24 * 3600), currentVersion: appVersion, now: now) == true)
    }

    @Test("条件4: 前回から+20勝するまで出ない")
    func minimumWinsSinceLast() {
        let longAgo = now.addingTimeInterval(-ReviewRequestPolicy.minimumElapsed * 3)
        func state(_ total: Int) -> ReviewRequestState {
            .init(totalWins: total, lastRequestedAt: longAgo,
                  lastRequestedWins: 5, lastRequestedVersion: "1.1.0")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(24), currentVersion: appVersion, now: now) == false, "+19勝では出ない")
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(25), currentVersion: appVersion, now: now) == true, "+20勝で出る")
    }

    @Test("条件5: 同一バージョンでは期間・勝利数を満たしても2回目が出ない")
    func onceOverVersion() {
        let longAgo = now.addingTimeInterval(-ReviewRequestPolicy.minimumElapsed * 10)
        let state = ReviewRequestState(
            totalWins: 1_000, lastRequestedAt: longAgo,
            lastRequestedWins: 5, lastRequestedVersion: appVersion
        )
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false)
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: "1.2.0", now: now) == true,
                "バージョンが上がれば条件3・4を満たしていれば出る")
    }

    @Test("端末の時計が巻き戻っていても出ない（条件3を満たさない扱い）")
    func clockWentBackwards() {
        let state = ReviewRequestState(
            totalWins: 1_000, lastRequestedAt: now.addingTimeInterval(60 * 60),
            lastRequestedWins: 5, lastRequestedVersion: "1.1.0"
        )
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false)
    }
}

// MARK: - サービス（記録と1回だけの発火）

@Suite("評価リクエストの記録と発火")
@MainActor
struct ReviewRequestServiceTests {

    @Test("条件1: 敗北・引き分けでは勝利数が増えず、リクエストも予定されない")
    func ignoresNonWins() {
        let (_, service) = makeServices(suite: "service-non-win")
        for _ in 0..<50 {
            service.gameDidFinish(outcome: .loss)
            service.gameDidFinish(outcome: .draw)
        }
        #expect(service.log.totalWins == 0, "勝利以外は1回も数えない")
        #expect(service.pendingRequestID == nil, "何回負けてもリクエストしない")
    }

    @Test("4勝目までは予定されず、5勝目で予定される")
    func pendsOnFifthWin() {
        let (_, service) = makeServices(suite: "service-fifth")
        advanceWins(service, count: 4)
        #expect(service.pendingRequestID == nil)
        service.gameDidFinish(outcome: .win)
        #expect(service.pendingRequestID != nil)
    }

    @Test("呼んだ時点で記録され、直後の勝利では再度呼ばれない")
    func recordsOnCallAndStopsRepeating() async {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (_, service) = makeServices(suite: "service-record", now: { clock })
        var requested = 0

        advanceWins(service, count: 5)
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
        #expect(service.pendingRequestID == nil)
        #expect(service.log.reviewState.lastRequestedAt == clock, "呼んだ時点を記録する")
        #expect(service.log.reviewState.lastRequestedWins == 5)
        #expect(service.log.reviewState.lastRequestedVersion == appVersion)

        // 同じバージョン・同じ日のまま勝ち続けても二度と呼ばれない（条件3〜5）。
        for _ in 0..<200 {
            service.gameDidFinish(outcome: .win)
            await service.performPendingRequest { requested += 1 }
        }
        #expect(requested == 1, "生涯で1回に収まっている（実際: \(requested)）")
        #expect(service.log.totalWins == 205, "勝利数の記録自体は続く")
    }

    @Test("2回目は120日以上かつ+20勝を満たしたときだけ呼ばれる")
    func secondRequestNeedsBothGates() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _, _) = makeLog(suite: "service-second")
        var version = "1.1.1"
        let service = ReviewRequestService(
            log: log, appVersion: version, now: { clock }, delay: .zero
        )
        var requested = 0

        advanceWins(service, count: 5)
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)

        // 120日経過するが +20勝には届かない（+19勝）。
        clock = clock.addingTimeInterval(ReviewRequestPolicy.minimumElapsed)
        version = "1.1.2"
        let afterVersionUp = ReviewRequestService(
            log: log, appVersion: version, now: { clock }, delay: .zero
        )
        advanceWins(afterVersionUp, count: 19)
        await afterVersionUp.performPendingRequest { requested += 1 }
        #expect(requested == 1, "+19勝では出ない")

        afterVersionUp.gameDidFinish(outcome: .win) // +20勝目
        await afterVersionUp.performPendingRequest { requested += 1 }
        #expect(requested == 2, "120日 + 20勝の両方を満たして2回目")
    }

    @Test("バージョンが上がっても120日経っていなければ出ない")
    func versionUpAloneIsNotEnough() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _, _) = makeLog(suite: "service-version-up")
        let first = ReviewRequestService(log: log, appVersion: "1.1.1", now: { clock }, delay: .zero)
        var requested = 0
        advanceWins(first, count: 5)
        await first.performPendingRequest { requested += 1 }
        #expect(requested == 1)

        clock = clock.addingTimeInterval(30 * 24 * 3600) // 30日後に新バージョン
        let second = ReviewRequestService(log: log, appVersion: "1.2.0", now: { clock }, delay: .zero)
        advanceWins(second, count: 100)
        await second.performPendingRequest { requested += 1 }
        #expect(requested == 1, "期間の歯止めはバージョン更新で解除されない")
    }
}

// MARK: - 条件6（リザルトの1.0秒後・進行中には呼ばない）

@Suite("評価リクエストの表示タイミング")
@MainActor
struct ReviewRequestTimingTests {

    @Test("既定では即時に呼ばれない（リザルト表示の1.0秒後）")
    func doesNotFireImmediately() async {
        let (log, _, _) = makeLog(suite: "timing-default")
        let service = ReviewRequestService(log: log, appVersion: appVersion) // 既定 = 1.0秒
        advanceWins(service, count: 5)

        var requested = 0
        let task = Task { await service.performPendingRequest { requested += 1 } }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(requested == 0, "1.0秒経つ前には呼ばない")
        task.cancel()
        _ = await task.value
    }

    @Test("待っている間に画面を離れたら呼ばれず、予定も破棄される")
    func cancelledWhileWaiting() async {
        let (log, _, _) = makeLog(suite: "timing-cancel")
        let service = ReviewRequestService(
            log: log, appVersion: appVersion, delay: .milliseconds(300)
        )
        advanceWins(service, count: 5)
        #expect(service.pendingRequestID != nil)

        var requested = 0
        let task = Task { await service.performPendingRequest { requested += 1 } }
        task.cancel()
        _ = await task.value

        #expect(requested == 0, "キャンセルされたら呼ばない")
        #expect(service.pendingRequestID == nil, "別の画面で不意に出さないよう予定を破棄する")
        #expect(service.log.reviewState.lastRequestedAt == nil, "呼んでいないので記録もしない")
    }

    @Test("待ち時間が経てば呼ばれる")
    func firesAfterDelay() async {
        let (log, _, _) = makeLog(suite: "timing-fires")
        let service = ReviewRequestService(
            log: log, appVersion: appVersion, delay: .milliseconds(50)
        )
        advanceWins(service, count: 5)

        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
    }
}

// MARK: - レコメンド（#52）との競合調停

@Suite("同じリザルトでのレコメンドとの競合")
@MainActor
struct ReviewVersusRecommendationTests {

    private static let hubOrder = [
        "2048", "shogi", "gomoku", "minesweeper", "othello", "poker", "concentration", "blackjack",
    ]

    private func makeBoth(suite: String) -> (GameServices, ReviewRequestService, RecommendationService) {
        let (log, _, _) = makeLog(suite: suite)
        let registry = GameRegistry([
            Game2048Module(), ShogiModule(), GomokuModule(), MinesweeperModule(),
            OthelloModule(), PokerModule(), ConcentrationModule(), BlackjackModule(),
        ])
        let review = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        let recommend = RecommendationService(
            log: log,
            availableModules: { Self.hubOrder.compactMap { registry.module(id: $0) } }
        )
        let services = GameServices(
            snapshots: MemorySnapshotStore(),
            ads: NoopAdService(),
            recommendations: recommend,
            review: review
        )
        return (services, review, recommend)
    }

    @Test("評価リクエストが出る回はレコメンドを出さず、次のリザルトに送る")
    func reviewWinsTheSlot() {
        let (services, review, recommend) = makeBoth(suite: "conflict-review-wins")

        // レコメンドの条件（20回終了）と評価リクエストの条件（5勝）を同じ回で満たす。
        for _ in 0..<19 { services.gameDidFinish(gameID: "shogi", outcome: .loss) }
        for _ in 0..<4 { review.gameDidFinish(outcome: .win) }
        #expect(recommend.suggestedGameID == nil)

        services.gameDidFinish(gameID: "shogi", outcome: .win) // 20回目 かつ 5勝目
        #expect(review.pendingRequestID != nil, "評価リクエストが予定される")
        #expect(recommend.suggestedGameID == nil, "同じリザルトにレコメンドは出さない")
        #expect(recommend.log.state.lastShownAt == nil, "提示カウントも消費していない")

        services.gameDidFinish(gameID: "shogi", outcome: .loss) // 次のリザルト
        #expect(recommend.suggestedGameID == "gomoku", "次の回でレコメンドが出る")
    }

    @Test("評価リクエストが出ない回はレコメンドが通常どおり出る")
    func recommendationUnaffected() async {
        let (services, review, recommend) = makeBoth(suite: "conflict-no-review")
        for _ in 0..<5 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        // 予定を消化する（実機では同じリザルト画面が必ず消化するため、予定が残り続けることはない）。
        await review.performPendingRequest {}
        #expect(review.pendingRequestID == nil)

        // 以降は条件5（同一バージョンでは1回まで）で予定が立たないため、レコメンドは抑止されない。
        for _ in 0..<15 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        #expect(review.log.totalWins == 20)
        #expect(recommend.suggestedGameID == "gomoku", "20回目のリザルトでレコメンドが出る")
    }

    @Test("予定が残っている間はレコメンドを抑止し続ける")
    func suppressionLastsWhilePending() {
        let (services, review, recommend) = makeBoth(suite: "conflict-pending-lasts")
        for _ in 0..<20 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        // 5勝目で立った予定を消化しない間は、以降のリザルトでもレコメンドを出さない。
        #expect(review.pendingRequestID != nil)
        #expect(recommend.suggestedGameID == nil)
        #expect(recommend.log.state.lastShownAt == nil, "提示カウントも消費しない")
    }
}

// MARK: - 各ゲームの勝敗の振り分け（条件1）

@Suite("全9ゲームの勝敗の振り分け")
@MainActor
struct GameOutcomeRoutingTests {

    @Test("マインスイーパー: 全マス開放は勝利として数える")
    func minesweeperWin() {
        let (services, service) = makeServices(suite: "route-minesweeper-win")
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 2, cols: 2, mines: 1)
        model.tap(row: 0, col: 0)
        for r in 0..<2 {
            for c in 0..<2 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }
        #expect(model.gameState == .won)
        #expect(service.log.totalWins == 1)
    }

    @Test("マインスイーパー: 地雷を踏んでも・諦めても勝利にならない")
    func minesweeperLoss() {
        let (services, service) = makeServices(suite: "route-minesweeper-loss")
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        guard let mine = model.cells.indices.flatMap({ r in
            model.cells[r].indices.map { (r, $0) }
        }).first(where: { model.cells[$0.0][$0.1].isMine }) else {
            Issue.record("地雷が見つからない")
            return
        }
        model.tap(row: mine.0, col: mine.1)
        #expect(model.gameState == .lost)

        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 4, col: 4)
        model.giveUp()
        #expect(model.gameState == .lost)

        #expect(service.log.totalWins == 0, "地雷・諦めは1回も数えない")
        #expect(service.pendingRequestID == nil)
    }

    @Test("神経衰弱: 人が勝てば数え、CPU が勝てば数えない")
    func concentration() {
        let (services, service) = makeServices(suite: "route-concentration")
        let model = ConcentrationModel(services: services)
        model.newGame(pairCount: .medium, cpuLevel: .normal)
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
        #expect(model.reviewOutcome == .win, "全ペアを人が取ったので勝利")
        #expect(service.log.totalWins == 1)
    }

    @Test("将棋: 投了は勝利にならない")
    func shogiResign() {
        let (services, service) = makeServices(suite: "route-shogi")
        let model = ShogiGameModel(services: services)
        model.resign()
        #expect(model.gameOver)
        #expect(service.log.totalWins == 0)
        #expect(service.pendingRequestID == nil)
    }

    @Test("五目並べ: 投了は勝利にならない")
    func gomokuResign() {
        let (services, service) = makeServices(suite: "route-gomoku")
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(service.log.totalWins == 0)
    }

    @Test("囲碁: 投了は勝利にならない")
    func goResign() {
        let (services, service) = makeServices(suite: "route-go")
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .easy)
        model.resign()
        #expect(service.log.totalWins == 0)
    }

    @Test("オセロ: 投了は勝利にならない")
    func othelloResign() {
        let (services, service) = makeServices(suite: "route-othello")
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(model.reviewOutcome == .loss)
        #expect(service.log.totalWins == 0)
    }

    @Test("2048: ゲームオーバーは勝利にならない")
    func game2048() {
        let (services, service) = makeServices(suite: "route-2048")
        let model = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(model.gameOver)
        #expect(service.log.totalWins == 0, "2048 には「クリア」が無く、終局は必ずゲームオーバー")
    }

    @Test("ブラックジャック: ラウンドの結果どおりに振り分ける")
    func blackjack() {
        let (services, service) = makeServices(suite: "route-blackjack")
        let model = BlackjackModel(services: services)
        model.restartSession()
        model.placeBet(100)
        if model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result)

        switch model.reviewOutcome {
        case .win:  #expect(service.log.totalWins == 1)
        default:    #expect(service.log.totalWins == 0)
        }
    }

    @Test("大富豪: 大富豪なら勝ち・大貧民なら負けに振り分ける")
    func daifugo() async {
        let (services, service) = makeServices(suite: "route-daifugo")
        let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 2026)
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

        switch model.reviewOutcome {
        case .win:
            #expect(model.playerTitle == "大富豪")
            #expect(service.log.totalWins == 1)
        default:
            #expect(model.playerTitle != "大富豪")
            #expect(service.log.totalWins == 0)
        }
    }

    @Test("四人打ち麻雀: 1位なら勝ち・4位なら負け・中位は引き分けに振り分ける")
    func mahjongFourPlayer() async {
        let (services, service) = makeServices(suite: "route-mahjong4")
        let model = MahjongModel(services: services, cpuDelay: .zero, seed: 4649)
        model.startGame()
        await playMahjongFourPlayer(model)
        #expect(model.phase == .gameResult)

        switch model.reviewOutcome {
        case .win:
            #expect(model.playerPlace == 0)
            #expect(service.log.totalWins == 1)
        case .loss:
            #expect(model.playerPlace == MahjongModel.playerCount - 1)
            #expect(service.log.totalWins == 0)
        case .draw:
            #expect(model.playerPlace != 0)
            #expect(service.log.totalWins == 0)
        }
    }

    @Test("麻雀ソリティア: 取り切ったときだけ勝ちに数える（諦めた回は記録しない・#240）")
    func mahjong() {
        let (services, service) = makeServices(suite: "route-mahjong")
        let model = MahjongSolitaireModel(services: services, seed: 909)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        #expect(service.log.totalWins == 1, "クリアは勝ちとして数える")

        let (services2, service2) = makeServices(suite: "route-mahjong-loss")
        let giveUp = MahjongSolitaireModel(services: services2, seed: 910)
        giveUp.giveUpAndRestart()
        #expect(service2.log.totalWins == 0, "諦めた回は勝ちに数えない")
    }

    @Test("数独: 解き切れば勝ち・諦めれば負けに振り分ける")
    func sudoku() async {
        let (services, service) = makeServices(suite: "route-sudoku")
        let model = SudokuModel(services: services, seed: 777)
        await model.newGame(difficulty: .easy)
        for index in 0..<81 where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }
        #expect(model.state == .cleared)
        #expect(service.log.totalWins == 1, "クリアは勝ちとして数える")

        let (services2, service2) = makeServices(suite: "route-sudoku-loss")
        let giveUp = SudokuModel(services: services2, seed: 778)
        await giveUp.newGame(difficulty: .easy)
        giveUp.giveUp()
        #expect(service2.log.totalWins == 0, "諦めた回は勝ちに数えない")
    }

    @Test("ポーカー: ラウンドの結果どおりに振り分ける")
    func poker() {
        let (services, service) = makeServices(suite: "route-poker")
        let model = PokerModel(services: services)
        model.restartSession()
        model.startGame()
        model.bet1Action(.check)
        if model.phase == .exchange { model.confirmExchange() }
        if model.phase == .betting2 { model.bet2Action(.check) }
        if model.phase == .betting2, model.currentBet > 0 { model.callCPUBet() }
        #expect(model.phase == .result)

        switch model.reviewOutcome {
        case .win:  #expect(service.log.totalWins == 1)
        default:    #expect(service.log.totalWins == 0)
        }
    }
}

// MARK: - 保存（再起動・キー数・消去）

@Suite("評価リクエストの記録の保存")
@MainActor
struct ReviewRequestStorageTests {

    /// 保存内容のバイト数（バイナリ plist 換算）。
    private func storedSize(_ domain: [String: Any]) -> Int {
        (try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0))?.count ?? -1
    }

    @Test("アプリ再起動をまたいで勝利数と前回リクエストが保持される")
    func survivesRelaunch() {
        let name = "asobiba.review.tests.persist"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let first = PlayLog(defaults: defaults)
        for _ in 0..<7 { first.recordWin() }
        first.markReviewRequested(at: requestedAt, version: appVersion)

        // 再起動相当: 同じ保存先から作り直す。
        let second = PlayLog(defaults: defaults)
        #expect(second.totalWins == 7)
        #expect(second.reviewState.lastRequestedAt == requestedAt)
        #expect(second.reviewState.lastRequestedWins == 7)
        #expect(second.reviewState.lastRequestedVersion == appVersion)

        defaults.removePersistentDomain(forName: name)
    }

    @Test("勝ち続けてもキーは9つのまま。データ量も増えない")
    func keysAndSizeAreBounded() {
        let name = "asobiba.review.tests.size"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for _ in 0..<20 { log.recordWin() }
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_800_000_000), version: appVersion)
        let after20 = defaults.persistentDomain(forName: name) ?? [:]

        for _ in 0..<10_000 { log.recordWin() }
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_900_000_000), version: appVersion)
        let after10020 = defaults.persistentDomain(forName: name) ?? [:]

        #expect(Set(after20.keys) == Set(PlayLog.reviewRequestKeys), "書き込むキーは4つだけ")
        #expect(Set(after10020.keys) == Set(after20.keys), "1万回勝ってもキーは増えない")
        // 増えうるのは整数の桁だけ（バイナリ plist の整数幅）。追記型ログなら数百 KB になる。
        #expect(storedSize(after10020) - storedSize(after20) <= 16, "データ量はほぼ一定")
        #expect(storedSize(after10020) <= 512, "キー名と plist の枠を含めても 512 バイト以内")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("「プレイ記録を消去」で評価リクエストの記録も消える")
    func clearRemovesReviewKeys() {
        let name = "asobiba.review.tests.clear"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for _ in 0..<10 { log.recordWin() }
        log.recordFinish(gameID: "shogi")
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_800_000_000), version: appVersion)

        log.clear()
        for key in PlayLog.allKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) が残っている")
        }
        #expect(log.totalWins == 0)
        #expect(log.reviewState == ReviewRequestState(), "判定用の状態も初期化される")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("消去した直後は5勝するまで再びリクエストされない")
    func requestsRestartAfterClear() {
        let (log, _, _) = makeLog(suite: "clear-then-request")
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        advanceWins(service, count: 5)
        #expect(service.pendingRequestID != nil)

        log.clear()
        let afterClear = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        advanceWins(afterClear, count: 4)
        #expect(afterClear.pendingRequestID == nil)
        afterClear.gameDidFinish(outcome: .win)
        #expect(afterClear.pendingRequestID != nil)
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
        case .callOffer:
            // この通しテストは「常に自摸切り」の方針なので鳴かない。
            model.declineCall()
        case .handResult:
            model.advanceToNextHand()
        case .idle, .gameResult:
            return
        }
    }
}
