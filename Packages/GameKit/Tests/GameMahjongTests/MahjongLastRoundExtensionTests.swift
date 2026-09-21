import Testing
import Foundation
import SwiftUI
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

private final class ExtensionAdStub: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 広告を見ているあいだに起きること（= ユーザーの割り込み）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// 保存済みの JSON から鍵を落とせる中断データ置き場（旧データの再現用。`MahjongGameLengthTests` と同じ道具）。
private final class RawMemoryStore: SnapshotStore, @unchecked Sendable {
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

    func removeKey(_ key: String, for gameID: String) {
        guard let data = store[gameID],
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        object.removeValue(forKey: key)
        store[gameID] = try? JSONSerialization.data(withJSONObject: object)
    }
}

@MainActor
private func makeModel(
    rewardEarned: Bool, playLog: PlayLog? = nil, store: SnapshotStore = MemorySnapshotStore(),
    analytics: GameAnalytics? = nil
) -> (MahjongModel, ExtensionAdStub) {
    let ads = ExtensionAdStub(rewardEarned: rewardEarned)
    let model = MahjongModel(
        services: GameServices(snapshots: store, ads: ads, playLog: playLog, analytics: analytics),
        cpuDelay: .zero,
        seed: 2026
    )
    model.startGame()
    return (model, ads)
}

/// 東 4 局を全員ノーテン流局（点棒が動かない）で終え、指定した持ち点のまま東風戦を終局させる。
@MainActor
private func finishLastRound(
    _ model: MahjongModel, scores: [Int], length: MahjongGameLength? = nil, roundNumber: Int = 4,
    dealer: Int = 3, tenpaiPlayer: Int? = nil
) {
    let junk = MahjongNotation.hand("159m159p159s1234z")
    let tenpai = MahjongNotation.hand("123m456m789m123p1s")
    model.configureForTesting(
        hands: (0..<MahjongModel.playerCount).map { $0 == tenpaiPlayer ? tenpai : junk },
        wall: [],
        dealer: dealer,
        scores: scores,
        roundNumber: roundNumber,
        length: length
    )
    model.exhaustWallForTesting()
    model.advanceToNextHand()
}

/// 自分（0 番）が単独の最下位。点棒の合計は問わない（流局で動かないので狙った順位のまま終局する）。
private let lastPlaceScores = [20_000, 26_000, 27_000, 27_001]

@Suite("最終局の延長（東5局・#1201）")
@MainActor
struct MahjongLastRoundExtensionTests {

    @Test("東 4 局を終えて自分が最下位なら、延長を提示する")
    func offersWhenLastPlace() {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)

        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .completedAllRounds)
        #expect(model.canExtendAfterLastPlace)
        #expect(!model.canReviveAfterBust, "トビ復活とは別の導線")
    }

    @Test("最下位でなければ提示しない（1 位・中間順位）")
    func doesNotOfferWhenNotLastPlace() {
        let (top, _) = makeModel(rewardEarned: true)
        finishLastRound(top, scores: [40_000, 20_000, 20_000 + 1, 20_000 + 2])
        #expect(top.phase == .gameResult)
        #expect(!top.canExtendAfterLastPlace)

        let (middle, _) = makeModel(rewardEarned: true)
        finishLastRound(middle, scores: [26_000, 20_000, 27_000, 28_000])
        #expect(middle.phase == .gameResult)
        #expect(!middle.canExtendAfterLastPlace)
    }

    @Test("トビ終了は延長の対象外（復活の側）")
    func doesNotOfferWhenBusted() {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(model.gameEndReason == .busted)
        #expect(!model.canExtendAfterLastPlace)
    }

    @Test("一局戦は延長の対象外")
    func doesNotOfferInSingleHand() {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores, length: .singleHand, roundNumber: 1)
        #expect(model.phase == .gameResult)
        #expect(!model.canExtendAfterLastPlace)
    }

    @Test("対局中・決着前には提示しない")
    func doesNotOfferWhilePlaying() {
        let (model, _) = makeModel(rewardEarned: true)
        #expect(!model.canExtendAfterLastPlace)
    }

    @Test("視聴完了なら東 5 局が配られ、持ち点は 1 点も動かない")
    func extendsWhenRewardEarned() async {
        let (model, ads) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)

        let outcome = await model.extendAfterAd()

        #expect(outcome == .granted)
        #expect(ads.rewardedCount == 1)
        #expect(model.phase == .playing)
        #expect(model.roundNumber == 5)
        #expect(model.scores == lastPlaceScores, "得点操作はしない")
        #expect(model.ranking.isEmpty)
        #expect(!model.canExtendAfterLastPlace)
    }

    @Test("視聴未完了なら何も変わらず、もう一度試せる")
    func doesNotExtendWhenRewardNotEarned() async {
        let (model, ads) = makeModel(rewardEarned: false)
        finishLastRound(model, scores: lastPlaceScores)

        let outcome = await model.extendAfterAd()

        #expect(outcome == .notEarned)
        #expect(ads.rewardedCount == 1)
        #expect(model.phase == .gameResult)
        #expect(model.canExtendAfterLastPlace)
    }

    @Test("延長した東 5 局が終わったら、最下位でも再延長せず終局する（1 半荘 1 回）")
    func extendsOncePerGame() async {
        let (model, ads) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(await model.extendAfterAd() == .granted)

        // 東 5 局を全員ノーテン流局で終える（親は次へ回り 6 局目 = 打ち切り）。配りは乱数なので、
        // 手牌を作り直して流局の形を固定する（延長で足された東 5 局のまま。`hasExtendedGame` は保つ）。
        model.configureForTesting(
            hands: Array(repeating: MahjongNotation.hand("159m159p159s1234z"), count: MahjongModel.playerCount),
            wall: [],
            dealer: 0,
            scores: lastPlaceScores,
            roundNumber: 5
        )
        model.exhaustWallForTesting()
        #expect(model.phase == .handResult)
        #expect(model.concludesAfterCurrentResult, "延長した最終局を終えたら終局へ進む")
        model.advanceToNextHand()

        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .completedAllRounds)
        #expect(!model.canExtendAfterLastPlace)
        #expect(await model.extendAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 1, "2 回目は広告を出さない")
    }

    @Test("延長した東 5 局の手前（東 4 局）では終局しない")
    func extendedGameDoesNotEndAtRoundFour() async {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(await model.extendAfterAd() == .granted)
        #expect(model.roundLimit == 5)
        #expect(!model.isGameOver())
    }

    @Test("「もう一度」で次の半荘を始めれば延長枠は戻る")
    func budgetResetsOnNewGame() async {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(await model.extendAfterAd() == .granted)

        model.startGame()
        #expect(model.roundLimit == 4)
        finishLastRound(model, scores: lastPlaceScores)

        #expect(model.canExtendAfterLastPlace)
    }

    @Test("延長戦の途中で中断して復元しても、東 5 局まで打ち切れる")
    func extensionSurvivesRestore() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(rewardEarned: true, store: store)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(await model.extendAfterAd() == .granted)
        #expect(store.exists(for: "mahjong4"), "延長後の局は中断データとして保存されている")

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: ExtensionAdStub(rewardEarned: true)),
            cpuDelay: .zero
        )

        #expect(restored.roundNumber == 5)
        #expect(restored.roundLimit == 5)
        #expect(!restored.isGameOver(), "復元しても東 5 局の途中が終局扱いにならない")
    }

    @Test("延長したら、決着で記録した負けを取り消して 1 半荘 = 1 プレイに保つ")
    func cancelsRecordedLoss() async {
        let name = "mahjong.extend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let log = PlayLog(defaults: defaults)
        let (model, _) = makeModel(rewardEarned: true, playLog: log)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(log.record(gameID: "mahjong4")?.losses == 1)

        #expect(await model.extendAfterAd() == .granted)

        #expect(log.record(gameID: "mahjong4")?.plays == 0, "同じ半荘の続きなので負けを巻き戻す")
        #expect(log.record(gameID: "mahjong4")?.losses == 0)
        #expect(model.recordResult == nil, "リザルトの記録行も消す")

        // 延長した東 5 局を終えれば、その 1 回だけが残る。
        finishLastRound(model, scores: lastPlaceScores, roundNumber: 5, dealer: 0)
        #expect(model.phase == .gameResult)
        #expect(log.record(gameID: "mahjong4")?.plays == 1)
        #expect(log.record(gameID: "mahjong4")?.losses == 1)
    }

    @Test("アガリやめで終わった東 4 局でも、最下位なら延長できる。局と親は次へ進めて東 5 局を配る")
    func extendsAfterAgariYame() async {
        let (model, _) = makeModel(rewardEarned: true)
        // 親（CPU3）がトップで聴牌流局 → 連荘条件成立 + アガリやめで終局。自分は最下位。
        finishLastRound(model, scores: [20_000, 21_000, 22_000, 40_000], tenpaiPlayer: 3)
        #expect(model.gameEndReason == .agariYame)
        #expect(model.roundNumber == 4, "アガリやめは局が進んでいない")
        #expect(model.canExtendAfterLastPlace)

        #expect(await model.extendAfterAd() == .granted)

        #expect(model.phase == .playing)
        #expect(model.roundNumber == 5)
        #expect(model.dealer == 0, "親は次の家（自分）へ回る")
        #expect(model.honba == 0)
        #expect(!model.endsAfterThisHand)
        #expect(!model.isGameOver())
    }

    @Test("延長した東 5 局でトップの親が連荘し続けたら、アガリやめで終局する")
    func extendedRoundCanEndByAgariYame() async {
        let (model, _) = makeModel(rewardEarned: true)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(await model.extendAfterAd() == .granted)

        // 東 5 局: 親（CPU1）がトップで聴牌流局 → 連荘条件成立。延長した最終局なのでアガリやめ。
        finishLastRound(model, scores: [20_000, 40_000, 21_000, 22_000], roundNumber: 5, dealer: 1, tenpaiPlayer: 1)

        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .agariYame)
        #expect(model.roundNumber == 5)
        #expect(!model.canExtendAfterLastPlace, "延長は 1 半荘 1 回")
    }

    @Test("広告は purpose = continue で計測する（復活の revival と分ける）")
    func measuresAsContinue() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: ["mahjong4"], now: { Date(timeIntervalSince1970: 0) }
        )
        let (model, _) = makeModel(rewardEarned: true, analytics: analytics)
        finishLastRound(model, scores: lastPlaceScores)

        _ = await model.extendAfterAd()

        let purposes = spy.events.compactMap { event -> RewardPurpose? in
            if case let .rewardAd(_, purpose) = event { return purpose } else { return nil }
        }
        #expect(purposes == [.continue])
    }

    @Test("広告を見ているあいだに新規対局を始めたら、延長は新しい対局に乗らない")
    func doesNotLandOnTheNewGame() async {
        let name = "mahjong.extend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let log = PlayLog(defaults: defaults)
        let (model, ads) = makeModel(rewardEarned: true, playLog: log)
        finishLastRound(model, scores: lastPlaceScores)
        #expect(log.record(gameID: "mahjong4")?.losses == 1)

        ads.duringAd = { model.startGame() }
        let outcome = await model.extendAfterAd()

        #expect(outcome == .unavailable, "見終えたのに適用しなかったので「視聴しなかった」ではない")
        #expect(log.record(gameID: "mahjong4")?.losses == 1, "記録済みの前局の負けが取り消されない")
        #expect(model.roundNumber == 1, "新しく始めた対局はそのまま続く")
        #expect(model.roundLimit == 4)
    }

    @Test("広告を見ているあいだにハブへ戻って開き直したら、古いモデルの延長は適用されない")
    func doesNotLandAfterLeavingTheScreen() async {
        let name = "mahjong.extend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let log = PlayLog(defaults: defaults)
        let ads = ExtensionAdStub(rewardEarned: true)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: ads, playLog: log)
        let left = MahjongModel(services: services, cpuDelay: .zero, seed: 2026)
        left.startGame()
        finishLastRound(left, scores: lastPlaceScores)
        #expect(left.canExtendAfterLastPlace)

        var reopened: MahjongModel?
        ads.duringAd = {
            services.gameDidLeave(gameID: "mahjong4")
            let next = MahjongModel(services: services, cpuDelay: .zero, seed: 7)
            next.startGame()
            reopened = next
        }
        let outcome = await left.extendAfterAd()

        #expect(outcome == .unavailable)
        #expect(left.phase == .gameResult, "捨てられたモデルに東 5 局が配られている")
        #expect(log.record(gameID: "mahjong4")?.losses == 1, "いま遊んでいる対局の負けが取り消されている")
        #expect(reopened?.phase == .playing)
    }

    @Test("延長の鍵が無かった頃の中断データも読めて、延長なしの東風戦として再開する")
    func legacySnapshotResumesWithoutExtension() {
        let store = RawMemoryStore()
        let (model, _) = makeModel(rewardEarned: true, store: store)
        #expect(store.exists(for: "mahjong4"))
        store.removeKey("hasExtendedGame", for: "mahjong4")
        _ = model

        let resumed = MahjongModel(
            services: GameServices(snapshots: store, ads: ExtensionAdStub(rewardEarned: true)), cpuDelay: .zero
        )
        #expect(resumed.phase == .playing, "鍵が増えても旧データが読めなくなってはいけない")
        #expect(resumed.roundLimit == 4)
    }
}
