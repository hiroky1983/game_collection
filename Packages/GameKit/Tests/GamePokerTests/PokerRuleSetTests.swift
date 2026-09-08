import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker

// MARK: - Mocks

private final class MockSnapshotStore: SnapshotStore, @unchecked Sendable {
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
    /// 旧バージョンが書いた JSON（`rules` の鍵が無いもの）を流し込む。
    func inject(_ data: Data, for gameID: String) { store[gameID] = data }
}

private final class NoopAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

private final class SpyGameCenterService: GameCenterService, @unchecked Sendable {
    var scores: [GameCenterScore] = []
    @MainActor func submit(_ score: GameCenterScore) { scores.append(score) }
    @MainActor func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
}

// MARK: - 札の組み立て

/// `PokerModel.makeDeck()` と同じ採番。テストの札が実物のデッキと衝突しない。
private func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
    PokerCard(id: suit.rawValue * 13 + (rank - 2), suit: suit, rank: rank)
}

/// 役なし（J ハイ）で、下の各役と 1 枚も重ならない CPU の手。
private let weakCPUHand = [c(3, .diamonds), c(4, .hearts), c(6, .spades), c(10, .diamonds), c(11, .hearts)]

/// その役ちょうどになる 5 枚。
private func hand(for rank: PokerHandRank) -> [PokerCard] {
    switch rank {
    case .royalFlush:
        return [c(14, .spades), c(13, .spades), c(12, .spades), c(11, .spades), c(10, .spades)]
    case .straightFlush:
        return [c(9, .hearts), c(8, .hearts), c(7, .hearts), c(6, .hearts), c(5, .hearts)]
    case .fourOfAKind:
        return [c(14, .spades), c(14, .hearts), c(14, .diamonds), c(14, .clubs), c(7, .spades)]
    case .fullHouse:
        return [c(13, .spades), c(13, .hearts), c(13, .diamonds), c(9, .spades), c(9, .hearts)]
    case .flush:
        return [c(14, .clubs), c(10, .clubs), c(7, .clubs), c(4, .clubs), c(2, .clubs)]
    case .straight:
        return [c(9, .spades), c(8, .hearts), c(7, .diamonds), c(6, .clubs), c(5, .spades)]
    case .threeOfAKind:
        return [c(8, .spades), c(8, .hearts), c(8, .diamonds), c(4, .spades), c(2, .hearts)]
    case .twoPair:
        return [c(13, .spades), c(13, .hearts), c(9, .diamonds), c(9, .clubs), c(5, .spades)]
    case .onePair:
        return [c(11, .spades), c(11, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)]
    case .highCard:
        return [c(14, .spades), c(10, .hearts), c(7, .diamonds), c(4, .clubs), c(2, .spades)]
    }
}

// MARK: - 局面の組み立て

/// 2 巡目のベッティングを中断データとして注入し、`bet2Action(.check)` 1 回でショーダウンへ
/// 進める局面を作る。CPU は役なしなので必ずチェックで受け、プレイヤーが勝つ。
@MainActor
private func makeModelBeforeShowdown(
    playerHand: [PokerCard],
    rules: PokerRuleSet,
    pot: Int = 40,
    playerChips: Int = 100,
    cpuChips: Int = 100,
    deck: [PokerCard] = [],
    gameCenter: SpyGameCenterService? = nil,
    log: PlayLog? = nil
) -> PokerModel {
    let store = MockSnapshotStore()
    let snap = PokerSnapshot(
        playerHand: playerHand, cpuHand: weakCPUHand, deck: deck,
        playerChips: playerChips, cpuChips: cpuChips, pot: pot,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "", rules: rules
    )
    try? store.save(snap, for: "poker")
    let reporter = gameCenter.map {
        GameCenterReporter(service: $0, allowedGameIDs: ["poker"])
    }
    // 記録先を必ず与える（`recordResult` が「局が閉じたか」の目印になるようにするため。
    // `PlayLog` が無いと `gameDidFinish` は常に nil を返し、閉じたかどうかが読めない）。
    return PokerModel(services: GameServices(
        snapshots: store, ads: NoopAdService(),
        playLog: log ?? PlayLog(defaults: freshDefaults()), gameCenter: reporter
    ))
}

/// 昇順に並べた山札（ダブルアップで「必ず上」を作れる）。
private func ascendingDeck(_ ranks: [Int]) -> [PokerCard] {
    ranks.enumerated().map { c($0.element, PokerSuit.allCases[$0.offset % 4]) }
}

// MARK: - RuleSet の焼き込み

@Suite("ポーカー: 1局=1RuleSet の焼き込み（#496）")
@MainActor
struct PokerRuleSetBakingTests {

    @Test("局に焼き込まれたルールは、局が終わるまで変わらない")
    func rulesStayFixedThroughTheRound() {
        let model = makeModelBeforeShowdown(playerHand: hand(for: .fullHouse), rules: .bonus)
        #expect(model.rules == .bonus)
        model.bet2Action(.check)
        #expect(model.phase == .result)
        #expect(model.rules == .bonus, "決着まで進めてもルールは動かない")
    }

    @Test("引数なしの startGame は前の局と同じルールを引き継ぐ")
    func startGameKeepsPreviousRules() {
        let model = makeModelBeforeShowdown(playerHand: hand(for: .onePair), rules: .bonus)
        model.bet2Action(.check)
        model.startGame()
        #expect(model.rules == .bonus, "「次のゲーム」でルールが勝手に戻ってはいけない")
        model.startGame(rules: .standard)
        #expect(model.rules == .standard, "ルールが変わるのは開始時に明示したときだけ")
    }

    @Test("中断から復元した局は、保存されていたルールで再開する")
    func restoredRoundKeepsBakedRules() {
        let store = MockSnapshotStore()
        let snap = PokerSnapshot(
            playerHand: hand(for: .twoPair), cpuHand: weakCPUHand, deck: [],
            playerChips: 100, cpuChips: 100, pot: 40, phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0, cpuFolded: false, cpuAction: "", rules: .bonus
        )
        try? store.save(snap, for: "poker")
        let restored = PokerModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.rules == .bonus)
    }

    @Test("ルールを持たない旧データはスタンダードとして復元する")
    func legacySnapshotFallsBackToStandard() throws {
        let store = MockSnapshotStore()
        // `rules` の鍵ごと無い JSON（v1.1.3 までが書いていた形）。
        let legacy = """
        {"playerHand":[],"cpuHand":[],"deck":[],"playerChips":100,"cpuChips":100,"pot":40,
         "phase":"betting2","currentBet":0,"playerBetInRound":0,"cpuBetInRound":0,
         "cpuFolded":false,"cpuAction":""}
        """
        store.inject(Data(legacy.utf8), for: "poker")
        #expect(store.load(PokerSnapshot.self, for: "poker") != nil, "旧データが読めなくなっていない")
        let restored = PokerModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.rules == .standard)
    }

    @Test("Model はグローバル設定を一切読まない（読むと局中に足元が変わる）")
    func modelReadsNoGlobalSettings() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // GamePokerTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // GameKit
                .appendingPathComponent("Sources/GamePoker/PokerModel.swift"),
            encoding: .utf8
        )
        #expect(!source.contains("UserDefaults"))
        #expect(!source.contains("AppStorage"))
    }
}

// MARK: - 役ボーナス

@Suite("ポーカー: 役ボーナス配当（#496）")
@MainActor
struct PokerBonusPayoutTests {

    @Test("配当表の全役が、勝負に勝ったときポットとは別に配当される", arguments: PokerBonusTable.payouts)
    func everyRankPaysItsBonus(payout: PokerBonusPayout) {
        let pot = 40
        let model = makeModelBeforeShowdown(
            playerHand: hand(for: payout.rank), rules: .bonus, pot: pot, playerChips: 100
        )
        model.bet2Action(.check)
        #expect(model.winner == .player)
        #expect(model.playerHandRank == payout.rank)
        #expect(model.playerBonus == payout.chips)
        #expect(model.playerChips == 100 + pot + payout.chips)
    }

    @Test("ワンペア以下には配当が付かない", arguments: [PokerHandRank.onePair, .highCard])
    func weakRanksPayNothing(rank: PokerHandRank) {
        let model = makeModelBeforeShowdown(playerHand: hand(for: rank), rules: .bonus, pot: 40)
        model.bet2Action(.check)
        #expect(model.playerHandRank == rank)
        #expect(model.playerBonus == 0)
        #expect(model.playerChips == 140)
        #expect(PokerBonusTable.chips(for: rank) == 0)
    }

    @Test("スタンダードでは同じ役でも配当が付かない")
    func standardPaysNoBonus() {
        let model = makeModelBeforeShowdown(playerHand: hand(for: .fullHouse), rules: .standard, pot: 40)
        model.bet2Action(.check)
        #expect(model.playerHandRank == .fullHouse)
        #expect(model.playerBonus == 0)
        #expect(model.playerChips == 140, "ポットの総取りだけ")
        #expect(!model.awaitsDoubleUp)
        #expect(!model.canStartDoubleUp)
    }

    @Test("フォールド勝ちには配当もダブルアップも付かない")
    func foldWinPaysNoBonus() {
        // CPU が降りる局面を作る: プレイヤーが 20 枚ベットし、役なしの CPU はフォールドする。
        let model = makeModelBeforeShowdown(
            playerHand: hand(for: .fullHouse), rules: .bonus, pot: 40, deck: ascendingDeck([2, 3])
        )
        model.bet2Action(.bet(20))
        #expect(model.cpuFolded)
        #expect(model.winner == .player)
        #expect(model.playerBonus == 0, "手を見せずに勝った局に役の見返りは出さない")
        #expect(!model.awaitsDoubleUp)
    }

    @Test("配当表は強い役ほど高い")
    func tableIsMonotonic() {
        let payouts = PokerBonusTable.payouts
        #expect(payouts.count == 8)
        for (higher, lower) in zip(payouts, payouts.dropFirst()) {
            #expect(higher.rank > lower.rank)
            #expect(higher.chips > lower.chips)
        }
    }
}

// MARK: - ダブルアップ

@Suite("ポーカー: ダブルアップ（#496）")
@MainActor
struct PokerDoubleUpTests {

    /// 勝ってダブルアップの提示まで進んだ局面。山札の先頭が見せ札になる。
    @MainActor
    private func won(deck: [PokerCard], pot: Int = 40, log: PlayLog? = nil,
                     gameCenter: SpyGameCenterService? = nil) -> PokerModel {
        // ツーペア（+10）で勝つので、賭けられるのは pot + 10。
        let model = makeModelBeforeShowdown(
            playerHand: hand(for: .twoPair), rules: .bonus, pot: pot, deck: deck,
            gameCenter: gameCenter, log: log
        )
        model.bet2Action(.check)
        return model
    }

    @Test("勝つとダブルアップの提示に入り、記録はまだ確定しない")
    func winOffersDoubleUp() {
        let log = PlayLog(defaults: freshDefaults())
        let model = won(deck: ascendingDeck([5, 13]), log: log)
        #expect(model.awaitsDoubleUp)
        #expect(model.canStartDoubleUp)
        #expect(model.pendingWinnings == 50, "ポット40 + ツーペアの配当10")
        #expect(model.recordResult == nil, "決着待ちの間は自己ベストを確定しない")
        #expect(log.record(gameID: "poker", variant: "bonus") == nil)
    }

    @Test("当てると賭け金が倍になり、賭け金は手持ちから預けられている")
    func correctGuessDoublesTheStake() {
        let model = won(deck: ascendingDeck([5, 13]))
        let chipsBeforeChallenge = model.playerChips
        model.startDoubleUp()
        #expect(model.playerChips == chipsBeforeChallenge - 50, "賭け金は手持ちから引かれる")
        #expect(model.doubleUp?.baseCard.rank == 5)

        model.guessDoubleUp(.high)
        #expect(model.doubleUp?.result == .success)
        #expect(model.doubleUp?.stake == 100)
        #expect(model.doubleUp?.streak == 1)
        #expect(model.awaitsDoubleUp, "受け取るか続けるかを選ぶまで局は閉じない")
    }

    @Test("外すと賭け金を失い、その場で局が閉じる")
    func wrongGuessLosesTheStake() {
        let log = PlayLog(defaults: freshDefaults())
        let model = won(deck: ascendingDeck([13, 3]), log: log)
        let chipsBeforeChallenge = model.playerChips
        model.startDoubleUp()
        model.guessDoubleUp(.high)   // K より上を予想して 3 が出る
        #expect(model.doubleUp?.result == .failure)
        #expect(model.doubleUp?.stake == 0)
        #expect(model.playerChips == chipsBeforeChallenge - 50, "賭けた50枚は戻らない")
        #expect(!model.awaitsDoubleUp)
        #expect(model.recordResult != nil, "局が閉じたので記録が確定する")
        #expect(log.record(gameID: "poker", variant: "bonus")?.bestPoints == chipsBeforeChallenge - 50)
    }

    @Test("同じ数字は引き分けで、賭け金も挑戦回数も減らない")
    func sameRankIsAPush() {
        let model = won(deck: [c(7, .spades), c(7, .diamonds), c(13, .clubs)])
        model.startDoubleUp()
        model.guessDoubleUp(.high)
        #expect(model.doubleUp?.result == .push)
        #expect(model.doubleUp?.stake == 50)
        #expect(model.doubleUp?.streak == 0)
        #expect(model.awaitsDoubleUp)

        model.continueDoubleUp()
        #expect(model.doubleUp?.baseCard.rank == 7, "めくった札が次の見せ札になる")
        #expect(model.doubleUp?.isAwaitingGuess == true)
    }

    @Test("途中で受け取ると賭け金が手持ちに戻り、局が閉じる")
    func takingSettlesTheRound() {
        let model = won(deck: ascendingDeck([5, 13]))
        let chipsBeforeChallenge = model.playerChips
        model.startDoubleUp()
        model.guessDoubleUp(.high)
        model.takeDoubleUpWinnings()
        #expect(model.playerChips == chipsBeforeChallenge + 50, "50枚を賭けて100枚になった")
        #expect(model.doubleUp?.payout == 100)
        #expect(model.doubleUp?.isSettled == true)
        #expect(!model.awaitsDoubleUp)
        #expect(model.recordResult != nil)
    }

    @Test("受け取りは二度できない")
    func takingIsIdempotent() {
        let model = won(deck: ascendingDeck([5, 13]))
        model.startDoubleUp()
        model.guessDoubleUp(.high)
        model.takeDoubleUpWinnings()
        let settled = model.playerChips
        model.takeDoubleUpWinnings()
        #expect(model.playerChips == settled)
    }

    @Test("挑戦しなければ勝ち分をそのまま受け取って局が閉じる")
    func decliningKeepsTheWinnings() {
        let model = won(deck: ascendingDeck([5, 13]))
        let chips = model.playerChips
        model.declineDoubleUp()
        #expect(model.playerChips == chips)
        #expect(model.doubleUp == nil)
        #expect(!model.awaitsDoubleUp)
        #expect(model.recordResult != nil)
    }

    @Test("5回連続で当てると打ち止めになり、自動で受け取る")
    func fiveWinsInARowStops() {
        let model = won(deck: ascendingDeck([2, 3, 4, 5, 6, 7, 8]))
        let chipsBeforeChallenge = model.playerChips
        model.startDoubleUp()
        for _ in 0..<PokerModel.maxDoubleUpStreak {
            model.guessDoubleUp(.high)
            if model.doubleUp?.isSettled == false { model.continueDoubleUp() }
        }
        #expect(model.doubleUp?.streak == PokerModel.maxDoubleUpStreak)
        #expect(model.doubleUp?.isSettled == true)
        #expect(model.doubleUp?.payout == 50 * 32, "50枚が5回倍で1600枚")
        #expect(model.playerChips == chipsBeforeChallenge - 50 + 1600)
        #expect(!model.awaitsDoubleUp)
    }

    @Test("打ち止めのあとは続けられない")
    func cannotContinuePastTheLimit() {
        let model = won(deck: ascendingDeck([2, 3, 4, 5, 6, 7, 8]))
        model.startDoubleUp()
        for _ in 0..<PokerModel.maxDoubleUpStreak {
            model.guessDoubleUp(.high)
            if model.doubleUp?.isSettled == false { model.continueDoubleUp() }
        }
        let chips = model.playerChips
        model.continueDoubleUp()
        model.guessDoubleUp(.high)
        #expect(model.playerChips == chips)
        #expect(model.doubleUp?.streak == PokerModel.maxDoubleUpStreak)
    }

    @Test("山札が2枚に満たない局では挑戦を出さない")
    func needsTwoCardsInTheDeck() {
        let model = won(deck: [c(5, .spades)])
        #expect(!model.canStartDoubleUp)
        #expect(!model.awaitsDoubleUp, "挑戦できない局はその場で閉じる")
        #expect(model.recordResult != nil)
    }

    @Test("決着待ちのまま次の局を始めても、賭け金は取りこぼさない")
    func startingNextRoundSettlesFirst() {
        let model = won(deck: ascendingDeck([5, 13, 3, 4, 6, 7, 8, 9, 10, 11, 12, 2]))
        model.startDoubleUp()
        model.guessDoubleUp(.high)      // 賭け金 100 枚を預けたまま次へ進もうとする
        let heldChips = model.playerChips
        model.startGame()
        #expect(!model.awaitsDoubleUp)
        // 預けた 100 枚が手持ちに戻り、次の局のアンティ 10 枚が引かれている。
        #expect(model.playerChips == heldChips + 100 - 10)
    }
}

// MARK: - Game Center の送信ゲート

@Suite("ポーカー: 順位表はスタンダード固定（#496）")
@MainActor
struct PokerLeaderboardGateTests {

    @Test("スタンダードの成績はリーダーボードへ送られる")
    func standardIsSubmitted() {
        let spy = SpyGameCenterService()
        let model = makeModelBeforeShowdown(
            playerHand: hand(for: .fullHouse), rules: .standard, pot: 40, gameCenter: spy
        )
        model.bet2Action(.check)
        #expect(spy.scores.count == 1)
        #expect(spy.scores.first?.leaderboardID == GameCenterLeaderboard.pokerChips)
        #expect(spy.scores.first?.value == model.playerChips)
    }

    @Test("ボーナスルールの成績は送られない")
    func bonusIsNotSubmitted() {
        let spy = SpyGameCenterService()
        let model = makeModelBeforeShowdown(
            playerHand: hand(for: .fullHouse), rules: .bonus, pot: 40, gameCenter: spy
        )
        model.bet2Action(.check)
        model.declineDoubleUp()
        #expect(model.recordResult != nil, "局は閉じている（＝送信の機会はあった）")
        #expect(spy.scores.isEmpty, "配当の出どころが違うので同じ順位表に混ぜない")
    }

    @Test("自己ベストはルールごとに別枠で数える")
    func recordsAreKeptPerRuleSet() {
        let defaults = freshDefaults()
        let log = PlayLog(defaults: defaults)

        let standard = makeModelBeforeShowdown(
            playerHand: hand(for: .fullHouse), rules: .standard, pot: 40, log: log
        )
        standard.bet2Action(.check)

        let bonus = makeModelBeforeShowdown(
            playerHand: hand(for: .fullHouse), rules: .bonus, pot: 40, log: log
        )
        bonus.bet2Action(.check)
        bonus.declineDoubleUp()

        let standardRecord = log.record(gameID: "poker")
        let bonusRecord = log.record(gameID: "poker", variant: "bonus")
        #expect(standardRecord?.plays == 1)
        #expect(standardRecord?.bestPoints == 140)
        #expect(standardRecord?.variantLabel == nil, "従来の記録に区分名を後付けしない")
        #expect(bonusRecord?.plays == 1)
        #expect(bonusRecord?.bestPoints == 240, "ポット40 + 配当100")
        #expect(bonusRecord?.variantLabel == "ボーナスルール")
    }

    @Test("スタンダードの記録の保存先は従来どおり（区分キーを付けない）")
    func standardKeepsTheLegacyRecordKey() {
        #expect(PokerRuleSet.standard.recordVariant == nil)
        #expect(PokerRuleSet.standard.recordVariantLabel == nil)
        #expect(PokerRuleSet.standard.isLeaderboardEligible)
        #expect(PokerRuleSet.bonus.recordVariant == "bonus")
        #expect(!PokerRuleSet.bonus.isLeaderboardEligible)
    }
}

/// テストごとに空の `UserDefaults`（記録が混ざらないようにする）。
private func freshDefaults() -> UserDefaults {
    let name = "asobiba.poker.rules.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
