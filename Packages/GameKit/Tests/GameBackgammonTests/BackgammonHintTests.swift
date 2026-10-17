import Testing
import Foundation
import SwiftUI
import Core
import CoreEngine
import CoreTestSupport
@testable import GameBackgammon

/// 視聴完了・未完了を制御できる広告スタブ（オセロの `OthelloHintTests` と同じ形）。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var shownCount = 0

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        shownCount += 1
        return rewardEarned
    }
}

/// 無料3回＋広告で最大5回のヒント（#2302）。回数の勘定そのものは Core の `BoardHintBudget`
/// （`BoardHintTests`）が固定するので、ここでは**バックギャモンの対局にどう結線されているか**を見る。
@MainActor
@Suite("バックギャモン ヒント（#2302）")
struct BackgammonHintTests {

    /// 人間の手番で 5・3 を振った初期配置。
    private func makeModel(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore()
    ) -> (BackgammonModel, StubAdService, MemorySnapshotStore) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let services = GameServices(snapshots: store, ads: ads)
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 7)
        model.configureForTesting(board: BackgammonBoard(), roll: (5, 3))
        return (model, ads, store)
    }

    @Test("押すと動かす 1 手が示され、残りが 1 つ減る")
    func showsBestMoveAndSpendsOne() async throws {
        let (model, _, _) = makeModel()
        #expect(model.hintsRemaining == BoardHintBudget.total)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        let move = try #require(model.hintMove, "ヒントの手が出ていない")
        #expect(model.legalMoves.contains(move), "動かせない手を示している")
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() throws {
        let (model, _, _) = makeModel()
        let move = try #require(model.legalMoves.first)
        // 目が 2 つ残るので 2 手目まで進めて手番を渡す。
        model.tap(move.from); model.tap(move.to)
        while !model.isAITurn, !model.gameOver, let m = model.legalMoves.first {
            model.tap(m.from); model.tap(m.to)
        }
        try #require(model.isAITurn, "前提: CPU の手番になっている")
        #expect(!model.canUseHint)
    }

    @Test("駒を動かすとヒントの印は消える（回数は戻らない）")
    func hintMarkDisappearsAfterTheMove() async throws {
        let (model, _, _) = makeModel()
        await model.requestHint()
        let move = try #require(model.hintMove)
        model.tap(move.from); model.tap(move.to)
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
    }

    @Test("やり直し・新規対局でも印は消え、新規対局では回数が戻る")
    func restartAndNewGameClearTheMark() async throws {
        let (model, _, _) = makeModel()
        let first = try #require(model.legalMoves.first)
        model.tap(first.from); model.tap(first.to)
        await model.requestHint()
        try #require(model.hintMove != nil)
        model.restartTurn()
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1)

        await model.requestHint()
        model.newGame()
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total)
    }

    @Test("無料 3 回の後は広告が要り、視聴すると 1 回出る")
    func adRefillsAfterFreeHints() async throws {
        let (model, ads, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame {
            #expect(!model.needsAdForHint)
            await model.requestHint()
        }
        #expect(model.needsAdForHint)
        #expect(ads.shownCount == 0, "無料のうちは広告を見せない")
        let before = model.hintsRemaining

        let outcome = await model.requestAdHint()

        #expect(outcome == .granted)
        #expect(ads.shownCount == 1)
        #expect(model.hintsRemaining == before - 1)
        #expect(model.hintMove != nil)
    }

    @Test("広告を最後まで見なければ回数は減らず、ヒントも出ない")
    func unearnedAdSpendsNothing() async throws {
        let (model, _, _) = makeModel(rewardEarned: false)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        let before = model.hintsRemaining
        let move = try #require(model.legalMoves.first)
        model.tap(move.from); model.tap(move.to)   // 印を消してから広告を試す
        try #require(model.hintMove == nil)

        let outcome = await model.requestAdHint()

        #expect(outcome == .notEarned)
        #expect(model.hintsRemaining == before)
        #expect(model.hintMove == nil)
    }

    @Test("無料枠が残っているあいだ requestAdHint は広告を出さない")
    func adHintIsUnavailableWhileFreeRemains() async {
        let (model, ads, _) = makeModel()
        let outcome = await model.requestAdHint()
        #expect(outcome == .unavailable)
        #expect(ads.shownCount == 0)
    }

    @Test("使った回数は中断データに持ち回り、使った局は順位表に送らない")
    func persistsUsedCountAndDropsLeaderboard() async throws {
        let (model, _, store) = makeModel()
        let move = try #require(model.legalMoves.first)
        model.tap(move.from); model.tap(move.to)   // 1 手動かすと中断データが保存される
        await model.requestHint()
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        let restored = BackgammonModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
        #expect(restored.hintsRemaining == BoardHintBudget.total - 1)
        #expect(restored.hintMove == nil, "印は永続化しない")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let (model, _, store) = makeModel()
        let move = try #require(model.legalMoves.first)
        model.tap(move.from); model.tap(move.to)
        let data = try #require(store.rawData(for: "backgammon"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"hintsUsed\":0"), "前提: 中断データに使用回数の鍵がある")
        let legacy = text.replacingOccurrences(of: ",\"hintsUsed\":0", with: "")
            .replacingOccurrences(of: "\"hintsUsed\":0,", with: "")
        #expect(!legacy.contains("hintsUsed"))
        store.inject(try #require(legacy.data(using: .utf8)), for: "backgammon")

        let restored = BackgammonModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
        #expect(restored.hintsRemaining == BoardHintBudget.total)
    }

    @Test("動かせる手が無い（パス）ときは押せない")
    func cannotUseHintWhenMustPass() {
        let ads = StubAdService(rewardEarned: true)
        let model = BackgammonModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: ads), cpuDelay: .zero, seed: 1)
        // 白がバーに 1 個で、入口 (6 → 19 ポイント) がすべて黒の 2 個以上のポイントで塞がれている局面。
        var p = Array(repeating: 0, count: 24)
        p[0] = 14
        for i in 18..<24 { p[i] = -2 }
        p[17] = -3
        model.configureForTesting(board: BackgammonBoard(points: p, bar: [1, 0], off: [0, 0]), roll: (6, 5))
        #expect(model.mustPass)
        #expect(!model.canUseHint)
    }
}
