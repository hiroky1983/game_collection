import Testing
import Foundation
import SwiftUI
import Core
import GameKitTestSupport
import CoreTestSupport
@testable import GameFifteen

/// 視聴完了・未完了を制御できる広告スタブ。
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

@Suite("15パズルのヒント用ソルバー（#1975）")
struct FifteenHintSolverTests {

    /// 示された升を 1 手ずつ動かし続けると必ず揃う（上限手数の内で）。
    @Test("ヒントの通りに動かし続けると、どの盤も揃う", arguments: 0..<12)
    func followingHintsSolvesTheBoard(seed: Int) throws {
        var generator = SplitMix64(seed: UInt64(seed))
        var tiles = FifteenLogic.shuffled(using: &generator)
        var steps = 0
        while !FifteenLogic.isSolved(tiles) {
            let index = try #require(FifteenHintSolver.nextIndex(tiles), "seed \(seed) step \(steps)")
            let blank = try #require(tiles.firstIndex(of: 0))
            // 示す升は空白の隣（1 枚だけ動く）。
            let slid = try #require(FifteenLogic.slide(tiles, at: index))
            #expect(slid.distance == 1, "seed \(seed) step \(steps) blank \(blank) index \(index)")
            tiles = slid.tiles
            steps += 1
            try #require(steps <= 400, "seed \(seed) が収束しない")
        }
    }

    @Test("あと 1 手の盤は、その 1 手を示す")
    func oneMoveAway() {
        // 揃った盤から 11 のタイルを下へ動かした盤（空白が 11 の位置）。戻すには 15 の升（index 15）のタイルを…ではなく 11 を戻す。
        let tiles = FifteenLogic.slide(FifteenLogic.solved, at: 11)!.tiles
        #expect(FifteenHintSolver.nextIndex(tiles) == 15)
    }

    @Test("揃っている盤・解けない盤は nil")
    func noHint() {
        #expect(FifteenHintSolver.nextIndex(FifteenLogic.solved) == nil)
        var broken = FifteenLogic.solved
        broken.swapAt(13, 14)
        #expect(FifteenHintSolver.nextIndex(broken) == nil)
    }

    @Test("難しい盤でも実用時間で返る（最難級 80 手の盤）")
    func hardestBoardReturnsQuickly() throws {
        // 最短 80 手が必要な盤の 1 つ。
        let tiles = [0, 12, 9, 13, 15, 11, 10, 14, 3, 7, 2, 5, 4, 8, 6, 1]
        try #require(FifteenLogic.isSolvable(tiles))
        let start = ContinuousClock.now
        #expect(FifteenHintSolver.nextIndex(tiles) != nil)
        // Debug・並列実行の負荷下でも落ちない緩い上限（単独の Debug で約 1.6 秒。Release はその数十分の一）。暴走だけを検出する。
        #expect(ContinuousClock.now - start < .seconds(60))
    }
}

@MainActor
@Suite("15パズル ヒント（#1975）")
struct FifteenHintTests {

    private func makeModel(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore(), seed: UInt64 = 1
    ) -> (FifteenModel, StubAdService) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let services = GameServices(snapshots: store, ads: ads)
        return (FifteenModel(services: services, seed: seed), ads)
    }

    @Test("押すと動かすタイルの升が1つ出て、残りが1つ減る")
    func showsTileAndSpendsOne() {
        let (model, _) = makeModel()
        #expect(model.hintsRemaining == BoardHintBudget.total)
        model.requestHint()
        let index = try? #require(model.hintIndex)
        #expect(index != nil)
        #expect(model.hints.used == 1)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        if let index { #expect(FifteenLogic.slide(model.tiles, at: index)?.distance == 1) }
    }

    @Test("盤を動かすと印は消える")
    func moveClearsMark() throws {
        let (model, _) = makeModel()
        model.requestHint()
        let index = try #require(model.hintIndex)
        model.tap(at: index)
        #expect(model.hintIndex == nil)
    }

    @Test("無料は3回まで。4回目は広告が要り、requestHint では消費しない")
    func freeLimitIsThree() {
        let (model, ads) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { model.requestHint() }
        #expect(model.hints.used == 3)
        #expect(model.needsAdForHint)
        model.requestHint()
        #expect(model.hints.used == 3, "無料を使い切ったあとは広告なしでは減らない")
        #expect(ads.shownCount == 0, "広告は自動で出さない")
    }

    @Test("広告を見ると+1回だけ足せる")
    func adGrantsOne() {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { model.requestHint() }
        #expect(model.grantAdHint(forGame: model.gameSerial))
        #expect(model.hints.used == 4)
        #expect(model.hintIndex != nil)
    }

    @Test("無料が残っているあいだは広告の報酬を受け付けない")
    func adRejectedWhileFreeRemains() {
        let (model, _) = makeModel()
        #expect(!model.grantAdHint(forGame: model.gameSerial))
        #expect(model.hints.used == 0)
    }

    @Test("広告を見ているあいだに新規ゲームが始まったら、報酬は乗らない")
    func adGrantIgnoresReplacedGame() {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { model.requestHint() }
        let old = model.gameSerial
        model.newGame()
        #expect(!model.grantAdHint(forGame: old))
        #expect(model.hints.used == 0)
    }

    @Test("新規ゲームで回数が戻り、印も消える")
    func newGameResets() {
        let (model, _) = makeModel()
        model.requestHint()
        model.newGame()
        #expect(model.hints.used == 0)
        #expect(model.hintIndex == nil)
    }

    @Test("中断データから復元しても使った回数は戻らない（印は出し直し）")
    func restoreKeepsUsedCount() throws {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        for _ in 0..<BoardHintBudget.perGame { model.requestHint() }
        model.tap(at: try #require(model.hintIndex)) // 盤を動かして保存し直す
        let (restored, _) = makeModel(store: store, seed: 99)
        #expect(restored.tiles == model.tiles)
        #expect(restored.hints.used == 3)
        #expect(restored.hintsRemaining == BoardHintBudget.total - 3)
        #expect(restored.hintIndex == nil)
    }

    @Test("ヒントを使い切ると押せない")
    func exhausted() throws {
        let (model, _) = makeModel()
        for _ in 0..<BoardHintBudget.perGame { model.requestHint() }
        for _ in 0..<BoardHintBudget.adRefillMax { #expect(model.grantAdHint(forGame: model.gameSerial)) }
        #expect(!model.canUseHint)
        #expect(!model.grantAdHint(forGame: model.gameSerial))
        #expect(model.hints.used == BoardHintBudget.total)
    }

    @Test("クリア後は押せない")
    func solvedDisables() {
        var tiles = FifteenLogic.solved
        tiles.swapAt(14, 15)
        let model = FifteenModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), tiles: tiles)
        model.tap(at: 15)
        #expect(model.isSolved)
        #expect(!model.canUseHint)
    }

    @Test("ヒントを使った局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() throws {
        let name = "asobiba.fifteen.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        // あと 1 手で揃う盤（右下の 15 を左へ動かす）。
        var tiles = FifteenLogic.solved
        tiles.swapAt(14, 15)
        let model = FifteenModel(services: services, tiles: tiles, hintsUsed: 1)
        model.tap(at: 15)
        #expect(model.isSolved)
        #expect(log.record(gameID: "fifteen")?.plays == 1)
        #expect(model.hints.wasUsed)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)
    }

    @Test("読み上げ: ヒントのタイルとボタン")
    func accessibility() {
        #expect(FifteenAccessibility.cellLabel(index: 0, value: 3, isHint: true).contains("ヒント"))
        #expect(!FifteenAccessibility.cellLabel(index: 0, value: 3).contains("ヒント"))
        #expect(FifteenAccessibility.hintLabel(remaining: 8, needsAd: false).contains("残り8回"))
        #expect(FifteenAccessibility.hintLabel(remaining: 5, needsAd: true).contains("広告"))
    }
}
