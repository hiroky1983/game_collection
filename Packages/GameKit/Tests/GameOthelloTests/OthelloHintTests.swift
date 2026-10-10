import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameOthello

/// 視聴完了・未完了を制御できる広告スタブ（五目並べの `GomokuAdHintTests` と同じ形）。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var shownCount = 0
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        shownCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// 無料3回＋広告で最大5回のヒント（#2011）。回数の勘定そのものは Core の `BoardHintBudget`
/// （`BoardHintTests`）が固定するので、ここでは**オセロの対局にどう結線されているか**を見る。
@MainActor
@Suite("オセロ ヒント（#2011）")
struct OthelloHintTests {

    private func makeModel(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore(),
        screenGeneration: GameScreenGeneration = GameScreenGeneration()
    ) -> (OthelloModel, StubAdService) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let services = GameServices(snapshots: store, ads: ads, screenGeneration: screenGeneration)
        return (OthelloModel(services: services, flipSettleDelay: .zero), ads)
    }

    /// 使用回数を `used` にした中断データを入れた保存先（8 回ぶん読むと 16 秒かかるのを避ける）。
    private func store(hintsUsed used: Int) throws -> MemorySnapshotStore {
        let store = MemorySnapshotStore()
        let seed = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()), flipSettleDelay: .zero)
        seed.newGame()
        let data = try #require(store.rawData(for: "othello"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"hintsUsed\":0"), "前提: 中断データに使用回数の鍵がある")
        let edited = text.replacingOccurrences(of: "\"hintsUsed\":0", with: "\"hintsUsed\":\(used)")
        store.inject(try #require(edited.data(using: .utf8)), for: "othello")
        return store
    }

    @Test("押すと置くと良い升が1つ出て、残りが1つ減る")
    func showsBestSquareAndSpendsOne() async throws {
        let (model, _) = makeModel()
        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        let point = try #require(model.hintPoint, "ヒントの升が出ていない")
        #expect(model.board.isValid(row: point.row, col: point.col, stone: model.currentStone), "置けない升を示している")
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() throws {
        let (model, _) = makeModel()
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        try #require(model.isAITurn, "前提: CPU の手番になっている")
        #expect(!model.canUseHint)
    }

    @Test("打つとヒントの印は消える（回数は戻らない）")
    func hintMarkDisappearsAfterTheMove() async throws {
        let (model, _) = makeModel()
        await model.requestHint()
        let point = try #require(model.hintPoint)

        model.tap(row: point.row, col: point.col)

        #expect(model.hintPoint == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1, "打ったら回数が戻っている")
    }

    @Test("待ったでもヒントの印は消える")
    func hintMarkDisappearsAfterUndo() async throws {
        let (model, _) = makeModel()
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        await model.performAIMoveIfNeeded()
        await model.requestHint()
        try #require(model.hintPoint != nil)

        model.undoLastExchange()

        #expect(model.hintPoint == nil)
    }

    @Test("新規対局で全回数に戻り、印も消える")
    func newGameRefillsHints() async {
        let (model, _) = makeModel()
        await model.requestHint()
        #expect(model.hintsRemaining < BoardHintBudget.total)

        model.newGame()

        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.hintPoint == nil, "前の対局のヒントの印が残っている")
    }

    @Test("無料枠が残っているうちは広告を要求しない")
    func doesNotNeedAdWhileFreeRemains() async {
        let (model, ads) = makeModel()
        #expect(!model.needsAdForHint)

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(ads.shownCount == 0, "無料枠があるのに広告を出している")
        #expect(model.hints.used == 0)
    }

    @Test("無料3回を使い切ると requestHint()（無料専用）は何も起きず、次の1回に広告が要る")
    func freeOnlyStopsAfterThree() async throws {
        let (model, _) = makeModel(store: try store(hintsUsed: BoardHintBudget.perGame))
        #expect(model.needsAdForHint)
        #expect(model.canUseHint, "広告枠が残っているので押せる状態のまま")
        #expect(model.hintsRemaining == BoardHintBudget.adRefillMax)

        await model.requestHint()

        #expect(model.hints.used == BoardHintBudget.perGame, "無料専用の requestHint() で回数が動いている")
    }

    @Test("広告を視聴すると置くと良い升が1つ出て、広告枠が1つ減る")
    func adGrantsOneMoreHint() async throws {
        let (model, ads) = makeModel(store: try store(hintsUsed: BoardHintBudget.perGame))

        let outcome = await model.requestAdHint()

        #expect(outcome == .granted)
        #expect(ads.shownCount == 1)
        #expect(model.hints.used == BoardHintBudget.perGame + 1)
        #expect(model.hintPoint != nil, "ヒントの升が出ていない")
    }

    @Test("視聴しなかったときは回数を減らさない")
    func notEarnedDoesNotConsume() async throws {
        let (model, ads) = makeModel(rewardEarned: false, store: try store(hintsUsed: BoardHintBudget.perGame))

        let outcome = await model.requestAdHint()

        #expect(outcome == .notEarned)
        #expect(ads.shownCount == 1)
        #expect(model.hints.used == BoardHintBudget.perGame, "視聴未完了なのに回数が減っている")
    }

    @Test("使い切る最後の1回を広告で出すと押せなくなり、広告も要求しない")
    func stopsAfterEightHintsTotal() async throws {
        let (model, _) = makeModel(store: try store(hintsUsed: BoardHintBudget.total - 1))

        let last = await model.requestAdHint()
        #expect(last == .granted)
        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)
        #expect(!model.needsAdForHint, "使い切ったら広告要求の状態も外れる")

        let extra = await model.requestAdHint()
        #expect(extra == .unavailable)
        #expect(model.hints.used == BoardHintBudget.total)
    }

    @Test("広告を見ているあいだに新しい対局が始まったら、捨てた局へは適用しない")
    func discardsTheHintIfANewGameStartedDuringTheAd() async throws {
        let (model, ads) = makeModel(store: try store(hintsUsed: BoardHintBudget.perGame))
        ads.duringAd = { model.newGame() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(model.hints.used == 0, "新しい対局の回数へ広告の分が乗っている")
    }

    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルには適用しない")
    func discardsTheHintIfTheScreenWasLeftDuringTheAd() async throws {
        let generation = GameScreenGeneration()
        let (model, ads) = makeModel(store: try store(hintsUsed: BoardHintBudget.perGame), screenGeneration: generation)
        ads.duringAd = { generation.advance() }

        let outcome = await model.requestAdHint()

        #expect(outcome == .unavailable)
        #expect(model.hints.used == BoardHintBudget.perGame, "画面を離れたのに回数が増えている")
    }

    @Test("中断データに使った回数が乗り、再開しても残りが戻らない（印は保存しない）")
    func hintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        await model.requestHint()
        try #require(model.hints.used == 1)

        let (restored, _) = makeModel(store: store)
        #expect(restored.hintsRemaining == BoardHintBudget.total - 1, "再開でヒントが戻っている")
        #expect(restored.hintPoint == nil, "印は保存しない（開き直したら出し直す）")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        model.newGame()
        let legacy = try #require(store.rawData(for: "othello"))
        let text = try #require(String(data: legacy, encoding: .utf8))
        #expect(text.contains("hintsUsed"), "前提: いまの形式は鍵を持つ")
        let stripped = try #require(
            text.replacingOccurrences(of: "\"hintsUsed\":0,", with: "")
                .replacingOccurrences(of: ",\"hintsUsed\":0", with: "")
                .data(using: .utf8)
        )
        store.inject(stripped, for: "othello")

        let (restored, _) = makeModel(store: store)
        #expect(restored.hintsRemaining == BoardHintBudget.total)
    }

    @Test("ヒントを使った対局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() async throws {
        let name = "asobiba.othello.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = OthelloModel(services: services, flipSettleDelay: .zero)

        #expect(model.hints.winLossScore.isLeaderboardEligible, "前提: 使う前は順位表の対象")
        await model.requestHint()
        try #require(model.hints.used == 1)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        model.resign()
        #expect(log.record(gameID: "othello")?.plays == 1, "自己ベスト（端末内）は使用有無を問わず残す")
        #expect(model.recordResult != nil)
    }

    @Test("ヒントの VoiceOver 読み上げに「ヒントの手」が付く")
    func accessibilityLabelMentionsHint() {
        let label = OthelloAccessibility.squareLabel(row: 2, col: 3, stone: nil, isValidMove: true,
                                                     isLastMove: false, isHint: true)
        #expect(label.contains("ヒントの手"))
        #expect(!OthelloAccessibility.squareLabel(row: 2, col: 3, stone: nil, isValidMove: true,
                                                  isLastMove: false).contains("ヒント"))
    }

    @Test("ヒントは むずかしい より 0.5 秒長く考え、他は むずかしい のまま")
    func hintThinksHalfSecondLongerThanHard() {
        let hard = OthelloEngine(level: CPUStrength.hard.rawValue)
        let hint = OthelloEngine.hint()
        #expect(hint.timeLimit == hard.timeLimit + BoardHintBudget.extraThinkingTime)
        #expect(hint.depthLimit == hard.depthLimit)
        #expect(hint.policy.isExact)
        #expect(hard.timeLimit == 1.5, "対局 CPU の むずかしい は変えない")
    }
}
