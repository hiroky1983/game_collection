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

/// 復活を使い切ったセッションで、ボーナスルールの勝ち（＝ダブルアップの提示）まで進めた局面（#1104）。
///
/// - Parameter deckRanks: ダブルアップで使う山札のランク。先頭が見せ札、次がめくり札になる。
@MainActor
private func makeRevivedWinAwaitingDoubleUp(
    deckRanks: [Int],
    analytics: GameAnalytics? = nil
) -> (PokerModel, MemorySnapshotStore, GameServices) {
    var nextID = 0
    func card(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        defer { nextID += 1 }
        return PokerCard(id: nextID, suit: suit, rank: rank)
    }
    // プレイヤーはツーペア（役ボーナス +10）、CPU は役なし。CPU は役が無ければチェックで受ける。
    let playerHand = [card(5, .spades), card(5, .hearts),
                      card(9, .clubs), card(9, .diamonds), card(2, .spades)]
    let cpuHand = [card(3, .clubs), card(4, .diamonds), card(6, .hearts),
                   card(8, .spades), card(12, .clubs)]
    let deck = deckRanks.map { card($0, .diamonds) }
    let store = MemorySnapshotStore()
    let snap = PokerSnapshot(
        playerHand: playerHand, cpuHand: cpuHand, deck: deck,
        playerChips: 100, cpuChips: 100, pot: 40,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "", rules: .bonus,
        hasRevivedThisSession: true
    )
    try? store.save(snap, for: "poker")
    let services = GameServices(
        snapshots: store, ads: StubAdService(rewardEarned: true), analytics: analytics
    )
    let model = PokerModel(services: services)
    // 中断から復元したモデルは `init` でプレイを数えない（#158）ので、局を始めた体にしてから
    // 決着させる。解析の「進行中のプレイ」が無いと、離脱と休憩の差が観測できない。
    services.gameDidRestart(gameID: "poker")
    services.gameDidProgress(gameID: "poker")
    model.bet2Action(.check)
    #expect(model.awaitsDoubleUp, "勝ってダブルアップの提示に入っている")
    return (model, store, services)
}

/// 送信されたイベントをそのまま溜めるスパイ（`AnalyticsTests` の同名の型と同じ形）。
@MainActor
private final class SpyAnalyticsService: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []
    func log(_ event: AnalyticsEvent) { events.append(event) }

    var quits: Int {
        events.filter {
            if case let .gameEnd(_, result, _, _, _) = $0 { return result == .quit } else { return false }
        }.count
    }
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

    /// #523 で復活の枚数を初期額より多くしたため、広告を見た直後に離れると損をする向きに反転した（#1104）。
    /// 復活した直後は `.result` のままで局を持たないので、以前は `persist()` が中断データごと捨てていた。
    @Test("復活したあと次の局を始める前に離れても、残高と復活の使用済みが残る（#1104）")
    func keepsRevivedChipsWhenLeavingBeforeNextRound() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())

        let saved = store.load(PokerSnapshot.self, for: "poker")
        #expect(saved?.playerChips == PokerModel.reviveChips, "復活後の残高が書かれていない")
        #expect(saved?.cpuChips == PokerModel.initialChips)
        #expect(saved?.hasRevivedThisSession == true, "使用済みの旗が中断データに乗る")
        #expect(saved?.phase == .idle, "決着の画は持ち越さない（画面は開始シートを出す）")

        // ここで次の局を始めずにハブへ戻り、開き直す（引き継ぐのは中断データだけ）。
        let reopened = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        #expect(reopened.playerChips == 150, "見た広告のぶんが消えている")
        #expect(reopened.cpuChips == 100)
        #expect(!reopened.sessionOver)
        #expect(reopened.canStartRound, "次の局を始められない")

        // 復活権も戻らない（#523 受け入れ条件 B）。もう一度チップが尽きても 2 回目は出ない。
        playFoldUntilBust(reopened)
        #expect(reopened.sessionOver)
        #expect(reopened.sessionWinner == .cpu)
        #expect(!reopened.canReviveAfterBust, "中断を挟んで復活の回数が戻っている")
    }

    /// 復活したセッションは、局の決着（`.result`）で離れても残高を持ち越す（#1104）。
    @Test("復活したセッションは局の決着で離れても残高が残る（#1104）")
    func keepsRevivedChipsWhenLeavingAtResult() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())

        model.startGame()
        model.bet1Action(.check)
        model.confirmExchange()
        model.bet2Action(.fold)
        #expect(model.phase == .result, "1 局は決着している")
        let settled = model.playerChips
        #expect(settled < PokerModel.reviveChips, "アンティのぶん減っている")

        let reopened = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        #expect(reopened.playerChips == settled, "精算後の残高が初期額へ戻っている")
        #expect(!reopened.canReviveAfterBust)
    }

    /// 復活したセッションが**もう一度**チップ切れになったら、中断データは残さない（#1104）。
    /// 残すと、次に開いたとき遊べない残高の死んだセッションが復元される。
    @Test("復活したセッションが再度チップ切れになったら中断データは消える（#1104）")
    func clearsSnapshotWhenRevivedSessionBustsAgain() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "poker"))

        playFoldUntilBust(model)
        #expect(model.sessionOver)
        #expect(!store.exists(for: "poker"), "遊べない残高のセッションが中断データに残っている")
    }

    /// ダブルアップ（#496）の各操作は `persist()` を呼ばない。復活したセッションでは
    /// ショーダウン直後の残高が中断データに残るため、局を閉じるところで書き直す（#1104）。
    @Test("復活したセッションのダブルアップの結果が中断データに乗る（#1104）")
    func persistsDoubleUpSettlement() {
        // 外したとき: 賭け金は戻らない。その残高が保存されている。
        let (lost, lostStore, _) = makeRevivedWinAwaitingDoubleUp(deckRanks: [13, 3])
        let beforeLoss = lost.playerChips
        lost.startDoubleUp()
        lost.guessDoubleUp(.high)          // K より上を予想して 3 が出る＝失敗
        #expect(lost.doubleUp?.result == .failure)
        #expect(lost.playerChips < beforeLoss)
        #expect(lostStore.load(PokerSnapshot.self, for: "poker")?.playerChips == lost.playerChips,
                "外した賭け金が中断データでは戻っている")

        // 受け取ったとき: 倍になった賭け金を含む残高が保存されている。
        let (won, wonStore, _) = makeRevivedWinAwaitingDoubleUp(deckRanks: [5, 13])
        won.startDoubleUp()
        won.guessDoubleUp(.high)           // 5 より上を予想して K が出る＝成功
        won.takeDoubleUpWinnings()
        #expect(!won.awaitsDoubleUp)
        #expect(wonStore.load(PokerSnapshot.self, for: "poker")?.playerChips == won.playerChips,
                "受け取った勝ち分が中断データに乗っていない")
    }

    /// 挑戦の経過は中断データに持たないので、途中で離れたら賭ける前の残高で戻す（#1104）。
    @Test("ダブルアップに挑戦中に離れたら、賭け金は預けたままにならない（#1104）")
    func returnsStakeWhenLeavingDuringDoubleUp() {
        let (model, store, _) = makeRevivedWinAwaitingDoubleUp(deckRanks: [5, 13])
        let beforeChallenge = model.playerChips
        model.startDoubleUp()
        #expect(model.playerChips < beforeChallenge, "賭け金は手持ちから引かれている")

        let reopened = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        #expect(reopened.playerChips == beforeChallenge, "預けた賭け金が消えている")
    }

    /// 局を持たない中断データは「続きから戻れる」ではない（#1104。CodeRabbit の Major 指摘）。
    /// `GameServices.gameDidLeave` は中断データの有無だけで休憩と離脱を分けるので、伝えないと
    /// ダブルアップの決着待ちで捨てた局が「休憩」のまま残り、次の局の `game_end` の
    /// `duration_sec` にハブ滞在時間が混ざる。
    @Test("局を持たない中断データを書いたあとに離れたら、休憩ではなく離脱として数える（#1104）")
    func leavingWithRoundWaitingSnapshotCountsAsQuit() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: ["poker"], now: { Date(timeIntervalSince1970: 0) }
        )
        let (model, store, services) = makeRevivedWinAwaitingDoubleUp(
            deckRanks: [5, 13], analytics: analytics
        )
        #expect(model.awaitsDoubleUp)
        #expect(store.exists(for: "poker"), "復活したセッションなので中断データは在る")

        services.gameDidLeave(gameID: "poker")
        #expect(spy.quits == 1, "続きの無い局が休憩として数えられている")
    }

    /// 復活の中断データ（#1104）が「もう一度はじめる」の初期化を邪魔しないこと。
    @Test("復活したあと最初からやり直すと、中断データは消えて初期額に戻る（#1104）")
    func restartClearsRevivedSnapshot() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "poker"), "復活の中断データが書かれている")

        model.restartSession()
        #expect(!store.exists(for: "poker"), "やり直しで中断データが消えていない")

        let reopened = PokerModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        #expect(reopened.playerChips == PokerModel.initialChips)
        playFoldUntilBust(reopened)
        #expect(reopened.canReviveAfterBust, "新しいセッションの復活権が消えている")
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

    /// ボーナスルールのダブルアップは手持ちから賭け金を引く（`startDoubleUp`）ので、片側だけ多い卓でも
    /// 引きすぎないことを見る。配りは乱数で勝ちを狙って作れないため、復活直後に 1 局目のアンティを
    /// 払った状態（150 - 10 = 140 対 90）を中断データで作り、札を決め打ちする。
    @Test("ボーナスルールのダブルアップも、復活後の手持ちで計算が崩れない")
    func doubleUpWorksOnRevivedTable() async {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["poker"])
        let suiteName = "asobiba.poker.revive.uneven.doubleup"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = MemorySnapshotStore()
        // 自分はツーペア（K・9）、CPU はハイカード。CPU はツーペア未満なのでチェックに返し、ショーダウンで自分が勝つ。
        let playerHand = [
            PokerCard(id: 11, suit: .spades, rank: 13), PokerCard(id: 24, suit: .hearts, rank: 13),
            PokerCard(id: 33, suit: .diamonds, rank: 9), PokerCard(id: 46, suit: .clubs, rank: 9),
            PokerCard(id: 3, suit: .spades, rank: 5),
        ]
        let cpuHand = [
            PokerCard(id: 27, suit: .diamonds, rank: 3), PokerCard(id: 15, suit: .hearts, rank: 4),
            PokerCard(id: 4, suit: .spades, rank: 6), PokerCard(id: 34, suit: .diamonds, rank: 10),
            PokerCard(id: 22, suit: .hearts, rank: 11),
        ]
        // 見せ札 5 → めくり札 10（ハイで当たり）。
        let deck = [PokerCard(id: 16, suit: .hearts, rank: 5), PokerCard(id: 8, suit: .spades, rank: 10)]
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            playerChips: PokerModel.reviveChips - 10, cpuChips: PokerModel.initialChips - 10, pot: 20,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "",
            rules: .bonus,
            hasRevivedThisSession: true
        )
        try? store.save(snap, for: "poker")
        let model = PokerModel(services: GameServices(
            snapshots: store, ads: StubAdService(rewardEarned: true),
            playLog: PlayLog(defaults: defaults), gameCenter: reporter
        ))

        model.bet2Action(.check)
        #expect(model.winner == .player)
        let bonus = PokerBonusTable.chips(for: .twoPair)
        let winnings = 20 + bonus
        #expect(model.pendingWinnings == winnings)
        #expect(model.canStartDoubleUp, "ダブルアップの提示まで進んでいる")

        let beforeDoubleUp = model.playerChips
        model.startDoubleUp()
        #expect(model.playerChips == beforeDoubleUp - winnings, "賭けるのはこの局で得た分だけ")
        #expect(model.playerChips == PokerModel.reviveChips - 10, "復活後の手持ちには手を付けない")

        model.guessDoubleUp(.high)
        #expect(model.doubleUp?.result == .success)
        model.takeDoubleUpWinnings()

        #expect(model.playerChips == PokerModel.reviveChips - 10 + winnings * 2)
        #expect(model.cpuChips == PokerModel.initialChips - 10, "CPU 側の手持ちは動かない")
        #expect(!model.sessionOver)
        #expect(model.canStartRound, "次の局へ進める")
        #expect(model.recordResult != nil, "ダブルアップの後に記録を確定する")
        #expect(spy.scores.isEmpty, "復活したセッションは、ボーナスルールでも順位表へ送らない")
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

// MARK: - 局を持たない中断データの扱い（#1104）

/// お知らせの予約先のスパイ。`ResumeReminderTests` のものは許諾と競合まで見るが、ここで要るのは
/// 「予約が入ったか」だけなので最小限にする。
@MainActor
private final class SpyReminderScheduler: ResumeReminderScheduler {
    private(set) var reminders: [String: ResumeReminder] = [:]

    func authorization() async -> ReminderAuthorization { .provisional }
    func requestProvisionalAuthorization() async -> ReminderAuthorization { .provisional }
    func pendingReminders() async -> [ResumeReminder] { Array(reminders.values) }
    func schedule(_ reminder: ResumeReminder, title: String, body: String) async {
        reminders[reminder.gameID] = reminder
    }
    func cancel(gameIDs: [String]) { gameIDs.forEach { reminders[$0] = nil } }
    func cancelAll() { reminders.removeAll() }
}

/// アプリを起動し直した状態（決着済みの印を覚えていない新しいサービス）を作る。
@MainActor
private func makeRelaunchedServices(
    store: MemorySnapshotStore
) -> (GameServices, ResumeReminderService, SpyReminderScheduler) {
    let spy = SpyReminderScheduler()
    let reminders = ResumeReminderService(
        scheduler: spy,
        isEnabled: { true },
        isSuppressed: false,
        reminderTitle: { $0 == "poker" ? "ポーカー" : nil }
    )
    let services = GameServices(
        snapshots: store, ads: StubAdService(rewardEarned: true), reminders: reminders
    )
    return (services, reminders, spy)
}

@Suite("復活のチップだけを持つ中断データ（#1104）")
@MainActor
struct PokerRevivedSnapshotTests {

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（`PokerRewardedAdTests`
    /// の「視聴中は「もう一度はじめる」を押せない」と同型）。この分岐が消えると、復活の
    /// 中断データから開いた画面は `.idle` のまま操作欄が `EmptyView` で固まる。
    @Test("局を持たない中断データから開いたら開始シートを出す")
    func showsStartSheetForRoundWaitingSnapshot() throws {
        let source = try SourceScan.moduleSources("GamePoker")
        #expect(source.contains("let waitsForNextRound = restored.phase == .idle"),
                "復元した局面が .idle かを見ていない")
        #expect(source.contains("State(initialValue: !hasSnapshot || waitsForNextRound)"),
                "開始シートの初期値が .idle の中断データを考えていない")
    }

    @Test("ハブの「続きから」には数えない")
    func roundWaitingSnapshotIsNotResumable() throws {
        let store = MemorySnapshotStore()
        let module = PokerModule()
        #expect(!module.hasResumableSnapshot(in: store), "中断データが無い")

        let waiting = PokerSnapshot(
            playerHand: [], cpuHand: [], deck: [],
            playerChips: 150, cpuChips: 100, pot: 0,
            phase: .idle, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "", rules: .standard,
            hasRevivedThisSession: true
        )
        try store.save(waiting, for: "poker")
        #expect(!module.hasResumableSnapshot(in: store), "戻った先は次の局の開始シートで続きではない")

        let inRound = PokerSnapshot(
            playerHand: [], cpuHand: [], deck: [],
            playerChips: 90, cpuChips: 90, pot: 20,
            phase: .betting1, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "", rules: .standard
        )
        try store.save(inRound, for: "poker")
        #expect(module.hasResumableSnapshot(in: store), "進行中の局が続きから外れている")
    }

    /// 保存時の通知（`notifyRoundWaitingSnapshot`）は `ResumeReminder` の**メモリ上の**決着済みの印に
    /// しか効かず、再起動で消える。復元側でも伝えないと、起動し直してから開いて戻ったときだけ
    /// 続きの無い局に「途中のままです」が予約される（#1145）。
    @Test("再起動後に開いて戻っても「途中のままです」を予約しない（#1145）")
    func revivedSnapshotSchedulesNoReminderAfterRelaunch() async {
        let (model, _, store) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(store.load(PokerSnapshot.self, for: "poker")?.phase == .idle,
                "前提が崩れた: 局を持たない中断データが残るはず")

        // アプリを終了して起動し直し、ハブから開いて次の局を始めずに戻る。
        let (services, reminders, spy) = makeRelaunchedServices(store: store)
        _ = PokerModel(services: services)
        services.gameDidLeave(gameID: "poker")
        await reminders.pendingWork?.value

        #expect(spy.reminders.isEmpty, "続きの無い局に「途中のままです」を予約した")
    }

    /// 上の対照。途中の局まで黙らせていたら、本物の中断が知らされなくなる。
    @Test("途中の局が残っているときは、再起動後でも従来どおり予約する（#1145）")
    func inRoundSnapshotStillSchedulesReminderAfterRelaunch() async throws {
        let store = MemorySnapshotStore()
        try store.save(
            PokerSnapshot(
                playerHand: [], cpuHand: [], deck: [],
                playerChips: 90, cpuChips: 90, pot: 20,
                phase: .betting1, currentBet: 0,
                playerBetInRound: 0, cpuBetInRound: 0,
                cpuFolded: false, cpuAction: "", rules: .standard
            ),
            for: "poker"
        )

        let (services, reminders, spy) = makeRelaunchedServices(store: store)
        let model = PokerModel(services: services)
        #expect(model.phase == .betting1, "前提が崩れた: 途中の局を復元しているはず")
        services.gameDidLeave(gameID: "poker")
        await reminders.pendingWork?.value

        #expect(spy.reminders["poker"] != nil, "途中の局が残っているのに予約しなかった")
    }
}
