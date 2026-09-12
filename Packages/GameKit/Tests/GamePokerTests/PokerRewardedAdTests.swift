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

    /// 旧バージョンが書いた JSON をそのまま流し込む（鍵を1つ落とした形を作るのに使う）。
    func saveRaw(_ json: Data, for gameID: String) { store[gameID] = json }
}

/// `PokerSnapshot` を符号化してから指定の鍵を落とし、旧バージョンが書いた JSON を作る。
private func encodingWithoutKey(_ snapshot: PokerSnapshot, key: String) throws -> Data {
    let data = try JSONEncoder().encode(snapshot)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: key)
    #expect(object[key] == nil)
    return try JSONSerialization.data(withJSONObject: object)
}

/// 視聴完了・未完了を制御できる広告スタブ。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    private(set) var interstitialCount = 0
    /// 視聴のあいだに起きること（ハブへ戻る等）。広告のロード中も画面は操作できる（#653）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async { interstitialCount += 1 }
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
    /// 「ここから先の送信だけを見たい」ための仕切り直し。
    func reset() { scores.removeAll() }
}

/// アンティを払って手持ち 0 になった 2 巡目の局面を中断データで作り、フォールドさせて
/// セッション敗北（＝自分のチップ切れ）まで進める（`PokerSessionOverTests` と同じ手口）。
///
/// - Parameter hasRevived: 中断データに書かれている「復活を使い切ったか」。
@MainActor
private func makeBustedModel(
    rewardEarned: Bool = true,
    hasRevived: Bool = false,
    gameCenter: GameCenterReporter? = nil,
    playLog: PlayLog? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration()
) -> (PokerModel, StubAdService, MockSnapshotStore) {
    let store = MockSnapshotStore()
    // 役の強さは判定に影響しない（フォールドは無条件に CPU の勝ち）ため、重複しない札を機械的に配る。
    let playerHand = (0..<5).map { PokerCard(id: $0, suit: .spades, rank: $0 + 2) }
    let cpuHand = (0..<5).map { PokerCard(id: $0 + 13, suit: .hearts, rank: $0 + 7) }
    let deck = (0..<10).map { PokerCard(id: $0 + 26, suit: .clubs, rank: $0 % 13 + 2) }
    let snap = PokerSnapshot(
        playerHand: playerHand, cpuHand: cpuHand, deck: deck,
        playerChips: 0, cpuChips: 90, pot: 20,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "",
        hasRevivedThisSession: hasRevived
    )
    try? store.save(snap, for: "poker")
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = PokerModel(
        services: GameServices(
            snapshots: store, ads: ads, playLog: playLog, gameCenter: gameCenter,
            screenGeneration: screenGeneration
        )
    )
    model.bet2Action(.fold)
    #expect(model.sessionOver, "手持ち 0 < アンティ 10 なのでセッションは終了する")
    #expect(model.sessionWinner == .cpu, "自分のチップが尽きて終わった")
    return (model, ads, store)
}

// MARK: - Tests

@Suite("チップ切れ復活のリワード広告（#499）")
@MainActor
struct PokerRewardedAdTests {

    @Test("視聴完了なら初期チップの半分で復活する")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.playerChips == 50, "初期チップ 100 の半分")
        #expect(model.playerChips == PokerModel.initialChips / 2)
        #expect(model.cpuChips == PokerModel.initialChips, "CPU は卓の設定値へ戻す（対等な卓に戻す）")
        #expect(!model.sessionOver)
        #expect(model.sessionWinner == nil)
        #expect(model.canStartRound, "復活後は次の局を始められる")
        #expect(ads.rewardedCount == 1)
    }

    /// 広告のロード中はハブへ戻れる。戻ると Model は捨てられ、次に開くと別の Model が動くが、
    /// 広告の完了を待つ `Task` は古い Model を強参照したまま生き残る（#653）。
    /// 世代を進めるのは `GameServices.gameDidLeave`（配線の検証は `RewardedRescueTests`）。
    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルにチップは戻らない")
    func doesNotRecoverAfterLeavingTheScreen() async {
        let generation = GameScreenGeneration()
        let (model, ads, _) = makeBustedModel(screenGeneration: generation)
        let chipsBefore = model.playerChips
        ads.duringAd = { generation.advance() }

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered, "捨てられたモデルに復活を適用している")
        #expect(model.playerChips == chipsBefore, "画面に無いモデルのチップが増えている")
        #expect(model.sessionOver, "セッション終了のまま")
        #expect(ads.rewardedCount == 1, "広告そのものは出ている（計測は従来どおり付く）")
    }

    @Test("視聴未完了・ロード失敗ならチップは回復しない")
    func doesNotRecoverChipsWhenRewardNotEarned() async {
        let (model, ads, _) = makeBustedModel(rewardEarned: false)
        let playerBefore = model.playerChips
        let cpuBefore = model.cpuChips

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.playerChips == playerBefore, "報酬なしなのでチップは1枚も増えない")
        #expect(model.cpuChips == cpuBefore)
        #expect(model.sessionOver, "セッション終了のまま")
        #expect(model.canReviveAfterBust, "失敗した視聴で1回ぶんを失わない")
        #expect(ads.rewardedCount == 1)
    }

    @Test("報酬付きの回復にインタースティシャルは使わない")
    func doesNotUseInterstitialForReward() async {
        let (model, ads, _) = makeBustedModel()

        _ = await model.recoverChipsAfterAd()

        #expect(ads.interstitialCount == 0)
    }

    // MARK: 出す場面を絞る

    @Test("チップが残っているうちは復活できず、広告も出さない")
    func doesNotShowAdWhileChipsRemain() async {
        let ads = StubAdService(rewardEarned: true)
        let model = PokerModel(services: GameServices(snapshots: MockSnapshotStore(), ads: ads))
        model.startGame()
        #expect(!model.sessionOver)
        #expect(!model.canReviveAfterBust)

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.playerChips == 90, "アンティを引いた残高のまま動かない")
        #expect(ads.rewardedCount == 0, "いつでも押せる増量ボタンにはしない")
    }

    @Test("CPU のチップが尽きた（＝こちらの勝ち）回には復活を出さない")
    func doesNotOfferReviveWhenPlayerWonTheSession() async {
        // CPU 側がアンティ未満で終わる局面。プレイヤーには十分な残高がある。
        // ポットを 0 にしてあるので、フォールドで CPU が回収しても 0 のままセッションが終わる。
        let store = MockSnapshotStore()
        let playerHand = (0..<5).map { PokerCard(id: $0, suit: .spades, rank: $0 + 2) }
        let cpuHand = (0..<5).map { PokerCard(id: $0 + 13, suit: .hearts, rank: $0 + 7) }
        let deck = (0..<10).map { PokerCard(id: $0 + 26, suit: .clubs, rank: $0 % 13 + 2) }
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            playerChips: 80, cpuChips: 0, pot: 0,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: ""
        )
        try? store.save(snap, for: "poker")
        let ads = StubAdService(rewardEarned: true)
        let model = PokerModel(services: GameServices(snapshots: store, ads: ads))
        model.bet2Action(.fold)

        #expect(model.sessionOver)
        #expect(model.sessionWinner == .player, "尽きたのは CPU のほう")
        #expect(!model.canReviveAfterBust, "自分は生き残っているので復活の動機が無い")
        #expect(await model.recoverChipsAfterAd() == false)
        #expect(ads.rewardedCount == 0)
    }

    // MARK: 1 セッション 1 回まで

    @Test("同じセッションで2回目の復活はできず、広告も出さない")
    func revivesOnlyOncePerSession() async {
        // 中断データが「復活を使い切った」状態。再開してもう一度チップが尽きた局面。
        let (model, ads, _) = makeBustedModel(hasRevived: true)

        #expect(!model.canReviveAfterBust, "使い切っているので導線は出ない")
        let second = await model.recoverChipsAfterAd()

        #expect(!second)
        #expect(model.playerChips == 0, "残高は動かない")
        #expect(ads.rewardedCount == 0, "2本目の広告は出さない")
    }

    @Test("中断から戻っても復活の回数は戻らない")
    func reviveBudgetSurvivesSuspend() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())

        // 復活後の1局を始めると、そこで中断データが書かれる。
        model.startGame()
        #expect(model.phase == .betting1)
        let saved = store.load(PokerSnapshot.self, for: "poker")
        #expect(saved?.hasRevivedThisSession == true, "使用済みの旗が中断データに乗る")

        // アプリを起動し直した想定。**保存されていた旗をそのまま引き継いで**、
        // もう一度チップが尽きる局面を作り直す（旗を書き直さないのが要点）。
        let resumed = PokerSnapshot(
            playerHand: saved!.playerHand, cpuHand: saved!.cpuHand, deck: saved!.deck,
            playerChips: 0, cpuChips: 90, pot: 20,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "",
            rules: saved!.rules,
            hasRevivedThisSession: saved!.hasRevivedThisSession
        )
        try? store.save(resumed, for: "poker")
        let restored = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        restored.bet2Action(.fold)

        #expect(restored.sessionOver)
        #expect(restored.sessionWinner == .cpu)
        #expect(!restored.canReviveAfterBust, "再起動で回数が復活しない")
    }

    @Test("最初からやり直すと復活の回数も戻る")
    func restartRestoresReviveBudget() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(!model.canReviveAfterBust)

        model.restartSession()
        #expect(model.playerChips == PokerModel.initialChips)
        #expect(model.cpuChips == PokerModel.initialChips)

        // 新しいセッションの1局目を始めると、中断データの旗も未使用に戻っている。
        model.startGame()
        let saved = store.load(PokerSnapshot.self, for: "poker")
        #expect(saved?.hasRevivedThisSession == false, "やり直しで回数が戻る")
    }

    // MARK: 旧データとの互換

    @Test("復活の鍵が無い旧スナップショットも読める")
    func decodesLegacySnapshotWithoutReviveKey() throws {
        // #499 以前に保存された形（`hasRevivedThisSession` が無い JSON）。
        let legacy = """
        {"playerHand":[],"cpuHand":[],"deck":[],"playerChips":40,"cpuChips":60,"pot":20,\
        "phase":"betting2","currentBet":0,"playerBetInRound":0,"cpuBetInRound":0,\
        "cpuFolded":false,"cpuAction":""}
        """
        let snap = try JSONDecoder().decode(PokerSnapshot.self, from: Data(legacy.utf8))
        #expect(snap.playerChips == 40)
        #expect(snap.hasRevivedThisSession == nil, "鍵が無くてもデコードは通る")
    }

    @Test("鍵が無い旧データから再開したセッションでも、1回目の復活は使える")
    func legacySnapshotStartsWithReviveAvailable() throws {
        // v1.1.3 以前から中断を持ち越したプレイヤーを、既定値の取り違えで
        // 「もう使い切った」扱いにしないことを、モデルまで通して確かめる。
        // （デコード結果が nil であることだけを見るテストでは、既定値を反転させても気づけない）
        let playerHand = (0..<5).map { PokerCard(id: $0, suit: .spades, rank: $0 + 2) }
        let cpuHand = (0..<5).map { PokerCard(id: $0 + 13, suit: .hearts, rank: $0 + 7) }
        let deck = (0..<10).map { PokerCard(id: $0 + 26, suit: .clubs, rank: $0 % 13 + 2) }
        let modern = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            playerChips: 0, cpuChips: 90, pot: 20,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "",
            hasRevivedThisSession: nil
        )
        let store = MockSnapshotStore()
        store.saveRaw(try encodingWithoutKey(modern, key: "hasRevivedThisSession"), for: "poker")

        let model = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        model.bet2Action(.fold)

        #expect(model.sessionOver)
        #expect(model.sessionWinner == .cpu)
        #expect(model.canReviveAfterBust, "旧データは「まだ使っていない」に倒す")
    }
}

// MARK: - Game Center への送信ゲート

@Suite("復活したセッションは順位表へ送らない（#499）")
@MainActor
struct PokerReviveLeaderboardTests {

    /// チップ切れ →（復活 or やり直し）→ 1 局決着、までを走らせて送信内容を集める。
    private func finishRound(
        usingRevive: Bool, suiteName: String
    ) async -> (SpyGameCenterService, PokerModel) {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["poker"])
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let (model, _, _) = makeBustedModel(
            gameCenter: reporter, playLog: PlayLog(defaults: defaults)
        )
        // チップが尽きた局自体も1件送っている（復活前なので対象）。ここから先だけを見たい。
        spy.reset()

        if usingRevive {
            #expect(await model.recoverChipsAfterAd())
        } else {
            model.restartSession()
        }
        // 1 局遊んで決着させる（勝敗は問わない。送るかどうかだけを見る）。
        // フォールドできるのは 2 巡目なので、チェック → 交換なし → フォールドで最短に進める。
        model.startGame()
        model.bet1Action(.check)
        model.confirmExchange()
        model.bet2Action(.fold)
        #expect(model.phase == .result, "1 局は決着している")
        return (spy, model)
    }

    @Test("復活を使わずに終えた局はチップを送る")
    func submitsCleanSession() async {
        let (spy, _) = await finishRound(
            usingRevive: false, suiteName: "asobiba.poker.revive.clean"
        )
        #expect(spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.pokerChips])
    }

    @Test("復活を使ったセッションの局は何も送らない")
    func skipsRevivedSession() async {
        let (spy, _) = await finishRound(
            usingRevive: true, suiteName: "asobiba.poker.revive.assisted"
        )
        #expect(spy.scores.isEmpty)
    }

    @Test("送らなくてもローカルの自己ベストには残る")
    func keepsLocalRecordEvenWhenNotSubmitted() async {
        let (spy, model) = await finishRound(
            usingRevive: true, suiteName: "asobiba.poker.revive.local"
        )
        #expect(spy.scores.isEmpty, "順位表へは送っていない")
        #expect(model.recordResult != nil, "順位表から外すだけで、手元の記録は残す（#397）")
    }
}
