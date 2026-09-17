import Testing
import Foundation
import SwiftUI
import Core
import GameKitTestSupport
@testable import GamePoker
import CoreTestSupport

// MARK: - Mocks

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
) -> (PokerModel, StubAdService, MemorySnapshotStore) {
    let store = MemorySnapshotStore()
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

/// 局を始めてはフォールドし続け、アンティで手持ちを削ってチップ切れまで進める。
/// チェックには CPU が必ずチェックで返し、交換後の 2 巡目でフォールドすれば必ず決着する
/// （`PokerReviveLeaderboardTests.finishRound` と同じ最短の進め方）。
@MainActor
private func playFoldUntilBust(_ model: PokerModel, maxRounds: Int = 20) {
    for _ in 0..<maxRounds {
        guard model.canStartRound else { return }
        model.startGame()
        model.bet1Action(.check)
        model.confirmExchange()
        model.bet2Action(.fold)
    }
}

// MARK: - Tests

@Suite("チップ切れ復活のリワード広告（#499）")
@MainActor
struct PokerRewardedAdTests {

    @Test("視聴完了なら自分 150 枚・CPU 100 枚で復活する（#523）")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.playerChips == 150, "会長決裁 C 案の枚数（#523）")
        #expect(model.playerChips == PokerModel.reviveChips)
        #expect(model.cpuChips == 100, "CPU は卓の設定値へ戻す（勝ち越したぶんを残さない）")
        #expect(model.cpuChips == PokerModel.initialChips)
        #expect(!model.sessionOver)
        #expect(model.sessionWinner == nil)
        #expect(model.canStartRound, "復活後は次の局を始められる")
        #expect(ads.rewardedCount == 1)
    }

    /// 広告を見る理由を「チップが増える」で作る（#523）。将来どちらかの定数を触っても逆転させない。
    @Test("復活のチップは、無料でもう一度はじめるより必ず多い")
    func reviveGivesMoreChipsThanFreeRestart() async {
        #expect(PokerModel.reviveChips > PokerModel.initialChips)

        // 定数の比較だけでなく、実際の 2 つの導線を通した結果でも比べる。
        let (revived, _, _) = makeBustedModel()
        #expect(await revived.recoverChipsAfterAd())
        let (restarted, _, _) = makeBustedModel()
        restarted.restartSession()
        #expect(restarted.playerChips == PokerModel.initialChips, "無料のやり直しは満額のまま")
        #expect(restarted.cpuChips == PokerModel.initialChips)
        #expect(revived.playerChips > restarted.playerChips)
        #expect(revived.cpuChips == restarted.cpuChips, "CPU 側はどちらの導線でも同じ")
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

    /// 広告のロード中は同じ画面の「もう一度はじめる」も押せる（#728）。画面の世代（#653）は
    /// 同じ画面の中の入れ替わりでは進まないので、セッションの通し番号で照合する。
    @Test("広告中に restartSession したら復活を適用しない")
    func doesNotReviveSessionRestartedDuringAd() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = { model.restartSession() }

        let outcome = await model.reviveAfterAd()

        #expect(outcome == .unavailable, "見終えたのに適用できなかったことを、視聴しなかったことと分けて返す")
        #expect(model.playerChips == PokerModel.initialChips, "新しいセッションの手持ちが復活の枚数に書き換えられている")
        #expect(model.cpuChips == PokerModel.initialChips)
        #expect(!model.sessionOver)
        #expect(model.phase == .idle, "開始シートを出したままの新しいセッション")
        #expect(ads.rewardedCount == 1)

        // 新しいセッションの復活権（= 順位表資格）が、前のセッションで見た広告で消えていない。
        playFoldUntilBust(model)
        #expect(model.sessionOver)
        #expect(model.sessionWinner == .cpu)
        #expect(model.canReviveAfterBust, "新しいセッションの復活権を消費している")
    }

    /// やり直したセッションも広告のあいだにチップが尽きると、`canReviveAfterBust` だけの照合は
    /// 素通りする。前のセッションで見た広告を新しいセッションの復活に使わせない（#728）。
    @Test("広告中にやり直したセッションもチップが尽きていたら、前のセッションの復活は乗せない")
    func doesNotReviveRestartedSessionThatAlsoBustedDuringAd() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = {
            model.restartSession()
            playFoldUntilBust(model)
        }

        let outcome = await model.reviveAfterAd()

        #expect(outcome == .unavailable)
        #expect(model.sessionOver, "やり直したセッションのチップ切れはそのまま")
        #expect(model.playerChips == 0)
        #expect(model.canReviveAfterBust, "新しいセッションの復活権を、前のセッションで見た広告で消費している")
    }

    @Test("視聴しなかったときは notEarned、視聴して適用できたら granted を返す")
    func reviveOutcomeSeparatesNotEarnedFromGranted() async {
        let (notEarned, _, _) = makeBustedModel(rewardEarned: false)
        #expect(await notEarned.reviveAfterAd() == .notEarned)
        #expect(notEarned.canReviveAfterBust, "失敗した視聴で1回ぶんを失わない")

        let (granted, _, _) = makeBustedModel()
        #expect(await granted.reviveAfterAd() == .granted)
        #expect(granted.playerChips == PokerModel.reviveChips)
    }

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（#728）。
    /// 範囲をやり直しボタンから先に絞るのは、手前の復活ボタンにも同じ `.disabled` があり、
    /// ファイル全体を探すとそちらに当たって空振りするため。
    @Test("視聴中は「もう一度はじめる」を押せない")
    func restartButtonIsDisabledWhileWatching() throws {
        let source = try SourceScan.moduleSources("GamePoker")
        let start = try #require(source.range(of: "                model.restartSession()\n"),
                                 "やり直しボタンの定義が見つからない（走査が空振りしている）")
        let end = try #require(source.range(of: "private func actionButton(", range: start.upperBound..<source.endIndex))
        let restartButton = source[start.upperBound..<end.lowerBound]
        #expect(restartButton.contains("\n            .disabled(reviveRescue.isWatching)"),
                "広告のロード〜視聴中に「もう一度はじめる」が押せる")
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
        let model = PokerModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: ads))
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
        let store = MemorySnapshotStore()
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
        let store = MemorySnapshotStore()
        store.inject(try encodingWithoutKey(modern, key: "hasRevivedThisSession"), for: "poker")

        let model = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        model.bet2Action(.fold)

        #expect(model.sessionOver)
        #expect(model.sessionWinner == .cpu)
        #expect(model.canReviveAfterBust, "旧データは「まだ使っていない」に倒す")
    }
}

// MARK: - 片側だけ多い卓（#523）

@Suite("復活後の 150 対 100 の卓でもルールが破綻しない（#523）")
@MainActor
struct PokerReviveUnevenTableTests {

    /// 配りは乱数なので勝敗は決めず、どの局でも成り立つべき不変条件だけを見る。
    /// 賭けは毎回できる限り 20 枚ずつ入れ、手持ちの差が効く経路（CPU の `min` での受け、
    /// CPU のベットへのコール）を通す。
    @Test("局を重ねてもチップの総量が保たれ、どちらも負にならない")
    func chipsStayConsistentAcrossRounds() async {
        let (model, _, _) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        let total = PokerModel.reviveChips + PokerModel.initialChips
        #expect(model.playerChips + model.cpuChips == total)

        var rounds = 0
        while model.canStartRound, rounds < 60 {
            rounds += 1
            model.startGame()
            #expect(model.phase == .betting1)
            #expect(model.playerChips + model.cpuChips + model.pot == total, "アンティで総量が変わった")

            model.bet1Action(model.playerChips >= 20 ? .bet(20) : .check)
            if model.phase == .exchange { model.confirmExchange() }
            if model.phase == .betting2 {
                model.bet2Action(model.playerChips >= 20 ? .bet(20) : .check)
            }
            // こちらのチェックに CPU がベットで返したら受ける（手持ちが足りなければ持っている分だけ）。
            if model.phase == .betting2, model.currentBet > 0 { model.callCPUBet() }

            #expect(model.phase == .result, "\(rounds) 局目が決着していない")
            #expect(model.pot == 0)
            #expect(model.playerChips >= 0 && model.cpuChips >= 0)
            #expect(model.playerChips + model.cpuChips == total, "\(rounds) 局目でチップが増減した")
        }

        #expect(rounds > 0, "復活直後に 1 局も始められない")
        if model.sessionOver {
            // どちらが尽きても、復活はもう使えない（1 セッション 1 回）。
            #expect(!model.canReviveAfterBust)
            switch model.sessionWinner {
            case .cpu:    #expect(model.playerChips < 10)
            case .player: #expect(model.cpuChips < 10)
            default:      Issue.record("片側だけ尽きるはずの卓で相打ちになった")
            }
        }
    }

    @Test("復活したセッションで自分が勝ち切っても、決着・記録・次のセッションは今と同じ")
    func revivedSessionWonByPlayerConcludesAsBefore() async {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["poker"])
        let suiteName = "asobiba.poker.revive.uneven.win"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // 復活を使ったセッションで、CPU がアンティ未満まで減った局面（中断データの旗は使用済み）。
        let store = MemorySnapshotStore()
        let playerHand = (0..<5).map { PokerCard(id: $0, suit: .spades, rank: $0 + 2) }
        let cpuHand = (0..<5).map { PokerCard(id: $0 + 13, suit: .hearts, rank: $0 + 7) }
        let deck = (0..<10).map { PokerCard(id: $0 + 26, suit: .clubs, rank: $0 % 13 + 2) }
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            playerChips: 250, cpuChips: 0, pot: 0,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "",
            hasRevivedThisSession: true
        )
        try? store.save(snap, for: "poker")
        let model = PokerModel(services: GameServices(
            snapshots: store, ads: StubAdService(rewardEarned: true),
            playLog: PlayLog(defaults: defaults), gameCenter: reporter
        ))
        model.bet2Action(.fold)

        #expect(model.sessionOver)
        #expect(model.sessionWinner == .player)
        #expect(!model.canReviveAfterBust, "勝ち切った回に復活は出さない")
        #expect(model.recordResult != nil, "ローカルの記録は残す")
        #expect(spy.scores.isEmpty, "復活したセッションは順位表へ送らない")

        model.restartSession()
        #expect(model.playerChips == PokerModel.initialChips)
        #expect(model.cpuChips == PokerModel.initialChips)
        #expect(model.canStartRound)
        model.startGame()
        let saved = store.load(PokerSnapshot.self, for: "poker")
        #expect(saved?.hasRevivedThisSession == false, "次のセッションは復活も順位表の資格も戻る")
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
