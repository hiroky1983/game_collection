import Testing
import Foundation
import SwiftUI
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

// MARK: - Mocks

/// `BlackjackSnapshot` を符号化してから指定の鍵を落とし、旧バージョンが書いた JSON を作る。
private func encodingWithoutKey(_ snapshot: BlackjackSnapshot, key: String) throws -> Data {
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

/// 配りが乱数のブラックジャックでは破産局面を狙って作れないので、中断データを注入して
/// 「全額を賭けた 15 対 ディーラー 20」を再現する（#439 と同じ手口）。`stand()` すれば必ず破産する。
///
/// - Parameters:
///   - chips: 破産させたい残高。この額を丸ごと賭けた手が入っている状態から始まる。
///   - hasRevived: 中断データに書かれている「復活を使い切ったか」。再開後の 2 回目を試すのに使う。
///   - seed: 復活後に遊ぶラウンドの配りを決定的にする種。
@MainActor
private func makeBustedModel(
    rewardEarned: Bool = true,
    chips: Int = 100,
    hasRevived: Bool = false,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    gameCenter: GameCenterReporter? = nil,
    playLog: PlayLog? = nil,
    seed: UInt64 = 20260909,
    screenGeneration: GameScreenGeneration = GameScreenGeneration()
) -> (BlackjackModel, StubAdService, MemorySnapshotStore) {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make([10, 5])
    let snapshot = BlackjackSnapshot(
        playerHand: playerCards,
        dealerHand: make([10, 10]),
        deck: make([2, 2]),
        chips: chips,
        bet: chips,
        phase: .playerTurn,
        hands: [BlackjackHand(id: 0, cards: playerCards, bet: chips)],
        activeHandIndex: 0,
        hasRevivedThisSession: hasRevived
    )
    try? store.save(snapshot, for: "blackjack")
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = BlackjackModel(
        services: GameServices(
            snapshots: store, ads: ads, playLog: playLog, gameCenter: gameCenter,
            screenGeneration: screenGeneration
        ),
        seed: seed
    )
    model.stand()
    #expect(model.chips == 0)
    #expect(model.sessionOver, "全額を失ったのでセッションは終了している")
    return (model, ads, store)
}

/// 残高を全額賭け続けて、負けた時点で破産させる。1 回でも負ければ残高 0 になるので必ず止まる。
@MainActor
private func playAllInUntilBust(_ model: BlackjackModel, maxRounds: Int = 40) {
    for _ in 0..<maxRounds {
        // 中断から復元した直後は手が進行中なので、まずその手を決着させる。
        while model.phase == .playerTurn { model.stand() }
        if model.sessionOver { return }
        if model.phase == .result { model.nextRound() }
        guard model.phase == .betting, model.chips > 0 else { return }
        model.placeBet(model.chips)
    }
}

// MARK: - Tests

@Suite("チップ切れ復活のリワード広告（#499）")
@MainActor
struct BlackjackRewardedAdTests {

    @Test("視聴完了なら 2000 枚で復活する（#523）")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.chips == 2000, "会長決裁 C 案の枚数（#523）")
        #expect(model.chips == BlackjackModel.reviveChips)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(ads.rewardedCount == 1)
    }

    /// 広告を見る理由を「チップが増える」で作る（#523）。将来どちらかの定数を触っても逆転させない。
    @Test("復活のチップは、無料で最初からやり直すより必ず多い")
    func reviveGivesMoreChipsThanFreeRestart() async {
        #expect(BlackjackModel.reviveChips > BlackjackModel.initialChips)

        // 定数の比較だけでなく、実際の 2 つの導線を通した結果でも比べる。
        let (revived, _, _) = makeBustedModel()
        #expect(await revived.recoverChipsAfterAd())
        let (restarted, _, _) = makeBustedModel()
        restarted.restartSession()
        #expect(restarted.chips == BlackjackModel.initialChips, "無料のやり直しは満額のまま")
        #expect(revived.chips > restarted.chips)
    }

    /// 広告のロード中はハブへ戻れる。戻ると Model は捨てられ、次に開くと別の Model が動くが、
    /// 広告の完了を待つ `Task` は古い Model を強参照したまま生き残る（#653）。
    /// 世代を進めるのは `GameServices.gameDidLeave`（配線の検証は `RewardedRescueTests`）。
    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルにチップは戻らない")
    func doesNotRecoverAfterLeavingTheScreen() async {
        let generation = GameScreenGeneration()
        let (model, ads, _) = makeBustedModel(screenGeneration: generation)
        ads.duringAd = { generation.advance() }

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered, "捨てられたモデルに復活を適用している")
        #expect(model.chips == 0, "画面に無いモデルのチップが増えている")
        #expect(model.sessionOver, "セッション終了のまま")
        #expect(ads.rewardedCount == 1, "広告そのものは出ている（計測は従来どおり付く）")
    }

    /// 広告のロード中は同じ画面の「最初からやり直す」も押せる（#727）。画面の世代（#653）は
    /// 同じ画面の中の入れ替わりでは進まないので、セッションの通し番号で照合する。
    @Test("広告中にセッションを作り直したら復活を適用しない")
    func doesNotReviveSessionRestartedDuringAd() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = { model.restartSession() }

        let outcome = await model.reviveAfterAd()

        #expect(outcome == .unavailable, "見終えたのに適用できなかったことを、視聴しなかったことと分けて返す")
        #expect(model.chips == BlackjackModel.initialChips, "新しいセッションの残高が復活の枚数に書き換えられている")
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(ads.rewardedCount == 1)

        // 新しいセッションの復活権（= 順位表資格）が、前のセッションで見た広告で消えていない。
        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust, "新しいセッションの復活権を消費している")
    }

    /// やり直したセッションも広告のあいだにチップが尽きると、`canReviveAfterBust` だけの照合は
    /// 素通りする。前のセッションで見た広告を新しいセッションの復活に使わせない（#727）。
    @Test("広告中にやり直したセッションもチップが尽きていたら、前のセッションの復活は乗せない")
    func doesNotReviveRestartedSessionThatAlsoBustedDuringAd() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = {
            model.restartSession()
            playAllInUntilBust(model)
        }

        let outcome = await model.reviveAfterAd()

        #expect(outcome == .unavailable)
        #expect(model.sessionOver, "やり直したセッションのチップ切れはそのまま")
        #expect(model.canReviveAfterBust, "新しいセッションの復活権を、前のセッションで見た広告で消費している")
    }

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（#727）。
    /// 範囲をやり直しボタンから先に絞るのは、手前の復活ボタンにも同じ `.disabled` があり、
    /// ファイル全体を探すとそちらに当たって空振りするため。
    @Test("視聴中は「最初からやり直す」を押せない")
    func restartButtonIsDisabledWhileWatching() throws {
        let source = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
        let start = try #require(source.range(of: "Button { model.restartSession() } label: {"),
                                 "やり直しボタンの定義が見つからない（走査が空振りしている）")
        let end = try #require(source.range(of: "// MARK: - Helper", range: start.upperBound..<source.endIndex))
        let restartButton = source[start.upperBound..<end.lowerBound]
        #expect(restartButton.contains("\n            .disabled(reviveRescue.isWatching)"),
                "広告のロード〜視聴中に「最初からやり直す」が押せる")
    }

    @Test("視聴未完了・ロード失敗ならチップは回復しない")
    func doesNotRecoverChipsWhenRewardNotEarned() async {
        let (model, ads, _) = makeBustedModel(rewardEarned: false)

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.chips == 0, "報酬なしなのでチップは1枚も増えない")
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

    // MARK: 1 セッション 1 回まで

    @Test("チップが残っているうちは復活できず、広告も出さない")
    func doesNotShowAdWhileChipsRemain() async {
        let ads = StubAdService(rewardEarned: true)
        let model = BlackjackModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: ads))
        #expect(!model.sessionOver)
        #expect(!model.canReviveAfterBust)

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.chips == BlackjackModel.initialChips, "残高は動かない")
        #expect(ads.rewardedCount == 0, "いつでも押せる増量ボタンにはしない")
    }

    @Test("同じセッションで2回目の復活はできず、広告も出さない")
    func revivesOnlyOncePerSession() async {
        // 中断データが「復活を使い切った」状態。再開してもう一度破産させた局面。
        let (model, ads, _) = makeBustedModel(hasRevived: true)

        #expect(!model.canReviveAfterBust, "使い切っているので導線は出ない")
        let second = await model.recoverChipsAfterAd()

        #expect(!second)
        #expect(model.chips == 0, "残高は動かない")
        #expect(ads.rewardedCount == 0, "2本目の広告は出さない")
    }

    @Test("中断から戻っても復活の回数は戻らない")
    func reviveBudgetSurvivesSuspend() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())

        // 復活後の1手を playerTurn まで進めると、そこで中断データが書かれる。
        model.placeBet(100)
        #expect(model.phase == .playerTurn, "この種では初手ブラックジャックにならない")
        let saved = store.load(BlackjackSnapshot.self, for: "blackjack")
        #expect(saved?.hasRevivedThisSession == true, "使用済みの旗が中断データに乗る")

        // アプリを起動し直した想定で、同じ中断データから作り直す。
        let restored = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        playAllInUntilBust(restored)
        #expect(restored.sessionOver)
        #expect(!restored.canReviveAfterBust, "再起動で回数が復活しない")
    }

    /// #523 で復活の枚数を初期額より多くしたため、広告を見た直後に離れると損をする向きに反転した（#1104）。
    /// 賭ける前の局面は局を持たないので、以前は `persist()` が中断データごと捨てていた。
    @Test("復活したあと賭ける前に離れても、残高と復活の使用済みが残る（#1104）")
    func keepsRevivedChipsWhenLeavingBeforeBetting() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(model.phase == .betting, "賭ける前で止まっている")

        // ここで何も賭けずにハブへ戻り、開き直す（引き継ぐのは中断データだけ）。
        let saved = store.load(BlackjackSnapshot.self, for: "blackjack")
        #expect(saved?.chips == BlackjackModel.reviveChips, "復活後の残高が書かれていない")
        #expect(saved?.hasRevivedThisSession == true, "使用済みの旗が中断データに乗る")

        let reopened = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true)),
            seed: 20260918
        )
        #expect(reopened.chips == 2000, "見た広告のぶんが消えている")
        #expect(reopened.phase == .betting)
        #expect(!reopened.sessionOver)

        // 復活権も戻らない（#523 受け入れ条件 B）。もう一度破産させても 2 回目は出ない。
        playAllInUntilBust(reopened)
        #expect(reopened.sessionOver)
        #expect(!reopened.canReviveAfterBust, "中断を挟んで復活の回数が戻っている")
    }

    /// 復活したセッションは、ラウンドの決着（`.result`）で離れても残高を持ち越す（#1104）。
    @Test("復活したセッションはラウンドの決着で離れても残高が残る（#1104）")
    func keepsRevivedChipsWhenLeavingAtResult() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())

        model.placeBet(100)
        while model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result, "1 ラウンドは決着している")
        let settled = model.chips

        let reopened = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true)),
            seed: 20260918
        )
        #expect(reopened.chips == settled, "精算後の残高が初期額へ戻っている")
        #expect(reopened.phase == .betting, "決着の画は持ち越さず賭け待ちへ戻す")
        #expect(!reopened.canReviveAfterBust)
    }

    /// 復活の中断データ（#1104）が「最初からやり直す」の初期化を邪魔しないこと。
    @Test("復活したあと最初からやり直すと、中断データは消えて初期額に戻る（#1104）")
    func restartClearsRevivedSnapshot() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "blackjack"), "復活の中断データが書かれている")

        model.restartSession()
        #expect(!store.exists(for: "blackjack"), "やり直しで中断データが消えていない")

        let reopened = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        #expect(reopened.chips == BlackjackModel.initialChips)
        playAllInUntilBust(reopened)
        #expect(reopened.canReviveAfterBust, "新しいセッションの復活権が消えている")
    }

    /// 復活したセッションが**もう一度**破産したら、中断データは残さない（#1104）。
    /// 残すと、次に開いたとき遊べない残高の死んだセッションが復元される。
    @Test("復活したセッションが再度破産したら中断データは消える（#1104）")
    func clearsSnapshotWhenRevivedSessionBustsAgain() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "blackjack"))

        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(!store.exists(for: "blackjack"), "遊べない残高のセッションが中断データに残っている")
    }

    @Test("最初からやり直すと復活の回数も戻る")
    func restartRestoresReviveBudget() async {
        let (model, _, _) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(!model.canReviveAfterBust)

        model.restartSession()
        #expect(model.chips == BlackjackModel.initialChips)

        // 新しいセッションで破産させ直すと、また復活できる。
        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust)
    }

    // MARK: 旧データとの互換

    @Test("復活の鍵が無い旧スナップショットも読める")
    func decodesLegacySnapshotWithoutReviveKey() throws {
        // #499 以前に保存された形（`hasRevivedThisSession` が無い JSON）。
        let legacy = """
        {"playerHand":[],"dealerHand":[],"deck":[],"chips":700,"bet":100,"phase":"playerTurn",\
        "hands":[],"activeHandIndex":0}
        """
        let snap = try JSONDecoder().decode(BlackjackSnapshot.self, from: Data(legacy.utf8))
        #expect(snap.chips == 700)
        #expect(snap.hasRevivedThisSession == nil, "鍵が無くてもデコードは通る")
    }

    @Test("鍵が無い旧データから再開したセッションでも、1回目の復活は使える")
    func legacySnapshotStartsWithReviveAvailable() throws {
        // v1.1.3 以前から中断を持ち越したプレイヤーを、既定値の取り違えで
        // 「もう使い切った」扱いにしないことを、モデルまで通して確かめる。
        // （デコード結果が nil であることだけを見るテストでは、既定値を反転させても気づけない）
        var nextID = 0
        func make(_ ranks: [Int]) -> [BlackjackCard] {
            ranks.map { rank in
                defer { nextID += 1 }
                return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
            }
        }
        let playerCards = make([10, 5])
        let modern = BlackjackSnapshot(
            playerHand: playerCards,
            dealerHand: make([10, 10]),
            deck: make([2, 2]),
            chips: 100,
            bet: 100,
            phase: .playerTurn,
            hands: [BlackjackHand(id: 0, cards: playerCards, bet: 100)],
            activeHandIndex: 0,
            hasRevivedThisSession: nil
        )
        let store = MemorySnapshotStore()
        store.inject(try encodingWithoutKey(modern, key: "hasRevivedThisSession"), for: "blackjack")

        let model = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        model.stand()

        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust, "旧データは「まだ使っていない」に倒す")
    }
}

// MARK: - Game Center への送信ゲート

@Suite("復活したセッションは順位表へ送らない（#499）")
@MainActor
struct BlackjackReviveLeaderboardTests {

    /// 破産 →（復活 or やり直し）→ 1 ラウンド決着、までを走らせて送信内容を集める。
    ///
    /// - Parameter suiteName: ローカル記録の保存先。テストごとに分けて汚染を避ける。
    private func finishRound(
        usingRevive: Bool, suiteName: String
    ) async -> (SpyGameCenterService, BlackjackModel) {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["blackjack"])
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let (model, _, _) = makeBustedModel(
            gameCenter: reporter, playLog: PlayLog(defaults: defaults)
        )
        // 破産したラウンド自体も1件送っている（復活前なので対象）。ここから先だけを見たい。
        spy.reset()

        if usingRevive {
            #expect(await model.recoverChipsAfterAd())
        } else {
            model.restartSession()
        }
        model.placeBet(100)
        while model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result, "1 ラウンドは決着している")
        return (spy, model)
    }

    @Test("復活を使わずに終えたラウンドはチップを送る")
    func submitsCleanSession() async {
        let (spy, _) = await finishRound(
            usingRevive: false, suiteName: "asobiba.blackjack.revive.clean"
        )
        #expect(spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.blackjackChips])
    }

    @Test("復活を使ったセッションのラウンドは何も送らない")
    func skipsRevivedSession() async {
        let (spy, _) = await finishRound(
            usingRevive: true, suiteName: "asobiba.blackjack.revive.assisted"
        )
        #expect(spy.scores.isEmpty)
    }

    @Test("送らなくてもローカルの自己ベストには残る")
    func keepsLocalRecordEvenWhenNotSubmitted() async {
        let (spy, model) = await finishRound(
            usingRevive: true, suiteName: "asobiba.blackjack.revive.local"
        )
        #expect(spy.scores.isEmpty, "順位表へは送っていない")
        #expect(model.recordResult != nil, "順位表から外すだけで、手元の記録は残す（#397）")
    }
}

// MARK: - 局を持たない中断データの扱い（#1104）

@Suite("復活のチップだけを持つ中断データ（#1104）")
@MainActor
struct BlackjackRevivedSnapshotTests {

    @Test("ハブの「続きから」には数えない")
    func betWaitingSnapshotIsNotResumable() throws {
        let store = MemorySnapshotStore()
        let module = BlackjackModule()
        #expect(!module.hasResumableSnapshot(in: store), "中断データが無い")

        let waiting = BlackjackSnapshot(
            playerHand: [], dealerHand: [], deck: [],
            chips: 2000, bet: 0, phase: .betting,
            hands: [], activeHandIndex: 0, hasRevivedThisSession: true
        )
        try store.save(waiting, for: "blackjack")
        #expect(!module.hasResumableSnapshot(in: store), "戻った先は賭け待ちで続きではない")

        let cards = [BlackjackCard(id: 0, suit: .spades, rank: 10),
                     BlackjackCard(id: 1, suit: .hearts, rank: 5)]
        let inRound = BlackjackSnapshot(
            playerHand: cards, dealerHand: cards, deck: [],
            chips: 900, bet: 100, phase: .playerTurn,
            hands: [BlackjackHand(id: 0, cards: cards, bet: 100)], activeHandIndex: 0
        )
        try store.save(inRound, for: "blackjack")
        #expect(module.hasResumableSnapshot(in: store), "進行中の手が続きから外れている")

        // 旧形式（#439 以前・`hands` が無い）も続きとして扱う。
        let legacy = BlackjackSnapshot(
            playerHand: cards, dealerHand: cards, deck: [],
            chips: 900, bet: 100, phase: .playerTurn,
            hands: nil, activeHandIndex: nil
        )
        try store.save(legacy, for: "blackjack")
        #expect(module.hasResumableSnapshot(in: store), "旧形式の中断が続きから外れている")
    }
}
