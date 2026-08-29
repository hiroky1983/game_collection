import Testing
import Foundation
import SwiftUI
import Core
@testable import GameDaifugo

// MARK: - Mocks

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

@MainActor
private func makeModel(
    seed: UInt64? = 42,
    store: SnapshotStore = MemorySnapshotStore()
) -> (DaifugoModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    // テストでは CPU の間合いを取らない（待たずに最後まで進める）。
    return (DaifugoModel(services: services, cpuDelay: .zero, seed: seed), services)
}

/// 人間の手番を貪欲法で自動消化しながら、決着するまで進める。
@MainActor
private func playToFinish(_ model: DaifugoModel, maxTurns: Int = 500) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing else { break }
        guard model.isPlayerTurn else { continue }
        if let play = DaifugoRules.greedyPlay(
            hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
        ) {
            for card in play { model.toggleSelection(card) }
            model.playSelected()
        } else {
            model.pass()
        }
    }
    return model.phase == .result
}

// MARK: - 進行

@Suite("大富豪の進行")
@MainActor
struct DaifugoModelTests {

    @Test("配ったカードは54枚すべてが4人に行き渡る")
    func dealsWholeDeck() {
        let (model, _) = makeModel()
        model.startGame()

        let all = model.hands.flatMap { $0 }
        #expect(all.count == 54, "52枚 + ジョーカー2枚")
        #expect(Set(all.map(\.id)).count == 54, "同じ札が2人に配られない")
        #expect(model.hands.allSatisfy { $0.count >= 13 })
        #expect(model.phase == .playing)
    }

    @Test("8切りで場が流れ、出した本人が続けて親になる")
    func eightClearsFieldAndKeepsLead() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(8), card(3)],
                [card(13), card(4)],
                [card(12), card(5)],
                [card(11), card(6)],
            ],
            field: [card(6)],
            fieldOwner: 3,
            currentPlayer: 0
        )

        model.toggleSelection(card(8))
        model.playSelected()

        #expect(model.field.isEmpty, "8切りで場が流れる")
        #expect(model.currentPlayer == 0, "出した本人がそのまま親")
        #expect(model.playerHand.map(\.rank) == [3])
    }

    @Test("全員がパスすると場が流れ、最後に出した人が親に戻る")
    func fieldClearsWhenEveryonePasses() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3), card(4)],
                [card(5), card(6)],
                [card(7), card(9)],
                [card(10), card(11)],
            ],
            field: [card(1)],      // A。誰も超えられない
            fieldOwner: 0,
            currentPlayer: 1
        )

        await model.runCPUTurnsIfNeeded()

        #expect(model.field.isEmpty, "3人が出せずパスしたら場が流れる")
        #expect(model.currentPlayer == 0, "最後に出した人（場の持ち主）が親に戻る")
        #expect(model.isPlayerTurn)
    }

    @Test("一度パスした人はその場では出せない（場が流れるまで復帰しない）")
    func passedPlayerStaysOutUntilFieldClears() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3), card(4)],
                [card(13), card(5)],
                [card(12), card(6)],
                [card(11), card(7)],
            ],
            field: [card(9)],
            fieldOwner: 3,
            currentPlayer: 0
        )

        model.pass()

        #expect(model.currentPlayer == 1, "パスした人を飛ばして次へ")
        #expect(!model.isPlayerTurn)
    }

    @Test("親（場が空）のときはパスできない")
    func cannotPassAsLeader() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(3)], [card(4)], [card(5)], [card(6)]],
            field: [],
            currentPlayer: 0
        )
        #expect(!model.canPass)
        model.pass()
        #expect(model.currentPlayer == 0, "パスは無効なので手番が動かない")
    }

    @Test("場より弱い組は出せず、手札も減らない")
    func rejectsWeakPlay() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(4)], [card(5)], [card(6)], [card(7)]],
            field: [card(13)],
            fieldOwner: 3,
            currentPlayer: 0
        )

        model.toggleSelection(card(3))
        #expect(!model.canPlaySelection)
        model.playSelected()

        #expect(model.playerHand.count == 2, "手札は減らない")
        #expect(model.currentPlayer == 0, "手番も動かない")
    }

    @Test("同ランク4枚で革命が起き、もう一度で戻る")
    func revolutionTogglesStrength() {
        let (model, _) = makeModel()
        let four = [card(5), card(5, .hearts), card(5, .diamonds), card(5, .clubs)]
        model.configureForTesting(
            hands: [four + [card(3)], [card(13)], [card(12)], [card(11)]],
            field: [],
            currentPlayer: 0
        )

        for c in four { model.toggleSelection(c) }
        model.playSelected()

        #expect(model.isRevolution, "4枚出しで革命")
    }
}

// MARK: - 反則上がりと階級

@Suite("反則上がりと階級")
@MainActor
struct DaifugoFoulTests {

    @Test("ジョーカーで上がると反則になり最下位に落ちる")
    func foulFinishDropsToLast() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [joker()],                                  // 人間: ジョーカー1枚で上がる（反則）
                [card(3)], [card(4)], [card(5)],
            ],
            field: [],
            currentPlayer: 0
        )

        model.toggleSelection(joker())
        model.playSelected()
        _ = await playToFinish(model)

        #expect(model.phase == .result)
        #expect(model.fouls.contains(DaifugoModel.humanIndex))
        #expect(model.ranking.last == DaifugoModel.humanIndex, "1着で上がっても大貧民")
        #expect(model.playerTitle == "大貧民")
        #expect(model.reviewOutcome == .loss)
    }

    @Test("普通に1着で上がれば大富豪になる")
    func cleanFinishBecomesTop() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3)],                                  // 人間: 3 で上がる（反則にならない）
                [card(4)], [card(5)], [card(6)],
            ],
            field: [],
            currentPlayer: 0
        )

        model.toggleSelection(card(3))
        model.playSelected()
        _ = await playToFinish(model)

        #expect(model.ranking.first == DaifugoModel.humanIndex)
        #expect(model.playerTitle == "大富豪")
        #expect(model.reviewOutcome == .win)
    }
}

// MARK: - 決着まで成立するか（受け入れ条件）

@Suite("CPU3人との対戦が最後まで成立する")
@MainActor
struct DaifugoFullGameTests {

    @Test("いろいろな配りで必ず決着し、4人に階級が付く", arguments: [1, 7, 42, 1234, 98765] as [UInt64])
    func finishesWithRanking(seed: UInt64) async {
        let (model, _) = makeModel(seed: seed)
        model.startGame()

        let finished = await playToFinish(model)

        #expect(finished, "決着せずに手詰まりしない")
        #expect(model.ranking.count == DaifugoModel.playerCount)
        #expect(Set(model.ranking).count == DaifugoModel.playerCount, "同じ人が2つの階級に入らない")
        #expect(model.hands.allSatisfy { $0.isEmpty }, "全員の手札が尽きている")
        #expect(!model.playerTitle.isEmpty)
    }

    @Test("2ゲーム目は前ゲームの階級どおりにカードが交換される")
    func secondGameExchangesCards() async {
        let (model, _) = makeModel(seed: 42)
        model.startGame()
        _ = await playToFinish(model)
        let firstRanking = model.ranking

        model.startGame()

        #expect(model.gameNumber == 2)
        #expect(model.lastTransfers.count == 4, "大富豪⇔大貧民・富豪⇔貧民 の4方向")
        let toTop = model.lastTransfers.first { $0.to == firstRanking[0] }
        #expect(toTop?.cards.count == 2)
        #expect(toTop?.from == firstRanking[3])
        let toSecond = model.lastTransfers.first { $0.to == firstRanking[1] }
        #expect(toSecond?.cards.count == 1)
        #expect(toSecond?.from == firstRanking[2])
        #expect(model.hands.flatMap { $0 }.count == 54, "交換で札が増減しない")
        #expect(model.currentPlayer == firstRanking[3], "前回の大貧民が親")
    }
}

// MARK: - 中断・再開

@Suite("中断と再開")
@MainActor
struct DaifugoResumeTests {

    @Test("対局中の状態が保存され、開き直すと続きから遊べる")
    func resumesFromSnapshot() {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(seed: 7, store: store)
        model.configureForTesting(
            hands: [
                [card(3), card(9)],
                [card(13), card(4)],
                [card(12), card(5)],
                [card(11), card(6)],
            ],
            field: [card(7)],
            fieldOwner: 3,
            currentPlayer: 0,
            isRevolution: true,
            gameNumber: 3
        )
        // 革命中なので 3 が 7 に勝つ（復元後もこの反転が効いていることを見る）。
        model.toggleSelection(card(3))
        model.playSelected()
        let expectedHand = model.playerHand
        let expectedTurn = model.currentPlayer

        #expect(store.exists(for: "daifugo"), "対局中はスナップショットが残る")

        // アプリを開き直した状態を再現する。
        let resumed = DaifugoModel(services: services, cpuDelay: .zero)

        #expect(resumed.phase == .playing)
        #expect(resumed.playerHand == expectedHand)
        #expect(resumed.currentPlayer == expectedTurn)
        #expect(resumed.field.map(\.id) == [card(3).id])
        #expect(resumed.isRevolution)
        #expect(resumed.gameNumber == 3)
    }

    @Test("決着したらスナップショットは消える（次回は最初から）")
    func clearsSnapshotOnResult() async {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(seed: 7, store: store)
        model.startGame()
        #expect(store.exists(for: "daifugo"))

        _ = await playToFinish(model)

        #expect(model.phase == .result)
        #expect(!store.exists(for: "daifugo"))
    }
}

// MARK: - ヒント表示（#190）

@Suite("手札ヒント")
@MainActor
struct DaifugoHandHintTests {

    /// テストごとに使い捨ての UserDefaults を作り、標準の設定を汚さない。
    private func makeHints(_ name: String, enabled: Bool) -> FeedbackPreference {
        let suite = "DaifugoHintTests.\(name)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let pref = FeedbackPreference(key: "hintsEnabled_v1", defaults: UserDefaults(suiteName: suite)!)
        pref.isEnabled = enabled
        return pref
    }

    private func makeModel(hintsEnabled: Bool = true, name: String = #function) -> DaifugoModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        return DaifugoModel(
            services: services, cpuDelay: .zero, seed: 42,
            hints: makeHints(name, enabled: hintsEnabled)
        )
    }

    @Test("出せない札があるときだけ、出せる / 出せないに振り分ける")
    func splitsHandWhenSomeCardsAreUnplayable() {
        let model = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(9), card(13)], [card(4)], [card(5)], [card(6)]],
            field: [card(9, .hearts)],
            fieldOwner: 1
        )
        let hint = try! #require(model.handHint)
        #expect(hint.playable == [card(13).id])
        #expect(hint.unplayable == [card(3).id, card(9).id])
        #expect(hint.state(for: card(13).id) == .playable)
        #expect(hint.state(for: card(3).id) == .unplayable)
    }

    @Test("手札すべてが出せるときは強調しない（場が流れている）")
    func noHintWhenEverythingIsPlayable() {
        let model = makeModel()
        model.configureForTesting(hands: [[card(3), card(9)], [card(4)], [card(5)], [card(6)]])
        #expect(model.handHint == nil)
    }

    @Test("1枚も出せないときは全札を「出せない」にしてパスを促す")
    func allUnplayable() {
        let model = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(4)], [card(5)], [card(6)], [card(7)]],
            field: [card(2)],
            fieldOwner: 1
        )
        let hint = try! #require(model.handHint)
        #expect(hint.playable.isEmpty)
        #expect(hint.unplayable == [card(3).id, card(4).id])
    }

    @Test("CPU の手番ではヒントを出さない")
    func noHintOnCPUTurn() {
        let model = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(9), card(13)], [card(4)], [card(5)], [card(6)]],
            field: [card(9, .hearts)],
            fieldOwner: 1,
            currentPlayer: 1
        )
        #expect(model.handHint == nil)
        #expect(model.selectionIssue == nil)
    }

    @Test("設定でオフにするとヒントも理由も出ない")
    func settingTurnsHintsOff() {
        let model = makeModel(hintsEnabled: false)
        model.configureForTesting(
            hands: [[card(3), card(9), card(13)], [card(4)], [card(5)], [card(6)]],
            field: [card(9, .hearts)],
            fieldOwner: 1
        )
        #expect(model.handHint == nil)
        model.toggleSelection(card(3))
        #expect(model.canPlaySelection == false, "設定に関わらず出せないことは変わらない")
        #expect(model.selectionIssue == nil)
    }

    @Test("出せない組を選ぶと理由が出て、出せる組に変えると消える")
    func selectionIssueFollowsSelection() {
        let model = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(9), card(13)], [card(4)], [card(5)], [card(6)]],
            field: [card(9, .hearts)],
            fieldOwner: 1
        )
        #expect(model.selectionIssue == nil, "未選択のうちは出さない")

        model.toggleSelection(card(3))
        #expect(model.selectionIssue == "場の 9 より強い数字が必要です")

        model.toggleSelection(card(3))
        model.toggleSelection(card(13))
        #expect(model.selectionIssue == nil)
        #expect(model.canPlaySelection)
    }
}


// MARK: - 消化試合の早送り（#191）

/// 人間が上がって CPU 同士の消化試合に入るところまで貪欲法で進める。
/// 人間が最後まで残った配りでは `false` を返す（早送りの対象にならない）。
@MainActor
private func playUntilPlayerFinishes(_ model: DaifugoModel, maxTurns: Int = 500) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing, model.isPlayerTurn else { break }
        if let play = DaifugoRules.greedyPlay(
            hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
        ) {
            for card in play { model.toggleSelection(card) }
            model.playSelected()
        } else {
            model.pass()
        }
        // 上がった直後に抜ける。ここで `runCPUTurnsIfNeeded` を回すと決着まで走り切ってしまう。
        if model.phase == .playing, model.isPlayerFinished { return true }
    }
    return false
}

@Suite("上がった後の消化試合")
@MainActor
struct DaifugoFastForwardTests {

    @Test("上がった後だけ「結果まで進める」を出す")
    func skipIsOfferedOnlyAfterFinishing() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(3)], [card(4), card(5)], [card(6), card(7)], [card(9), card(10)]]
        )
        #expect(model.canSkipToResult == false, "自分の手札が残っているうちは出さない")

        model.skipToResult()
        #expect(model.isSkippingToResult == false, "手番中に呼ばれても無視する")

        model.toggleSelection(card(3))
        model.playSelected()

        #expect(model.isPlayerFinished)
        #expect(model.canSkipToResult, "上がった直後・決着前は出す")
        model.skipToResult()
        #expect(model.isSkippingToResult)
    }

    @Test("早送りしても順位・記録は通常進行と変わらない")
    func skipKeepsRankingIdentical() async {
        let (plain, _)   = makeModel(seed: 42)
        let (skipped, _) = makeModel(seed: 42)
        plain.startGame()
        skipped.startGame()

        #expect(await playUntilPlayerFinishes(skipped), "seed 42 は人間が先に上がる配り")
        skipped.skipToResult()
        await skipped.runCPUTurnsIfNeeded()
        #expect(await playToFinish(plain))

        #expect(skipped.phase == .result)
        #expect(skipped.ranking == plain.ranking, "早送りは見せ方だけを変える")
        #expect(skipped.finishOrder == plain.finishOrder)
        #expect(skipped.playerTitle == plain.playerTitle)
        #expect(skipped.fouls == plain.fouls)
    }

    @Test("早送りは次のゲームに持ち越さない")
    func skipResetsOnNextGame() async {
        let (model, _) = makeModel(seed: 42)
        model.startGame()
        #expect(await playUntilPlayerFinishes(model))
        model.skipToResult()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)

        model.startGame()
        #expect(model.isSkippingToResult == false)
        #expect(model.canSkipToResult == false)
        #expect(model.cpuTurnsAfterPlayerFinished == 0)
    }

    /// 受け入れ条件「実測の待ち時間が10秒以内」。早送りを**押さずに**眺めた場合の待ち時間を
    /// 「消化試合の手番数 × 短縮した間合い」で見積もる（実時間で待つとテストがフレークするため）。
    @Test("早送りを押さなくても消化試合は10秒以内に終わる")
    func remainingTurnsFitInTenSeconds() async {
        var measured = 0
        var worstTurns = 0
        for seed in (1...60).map(UInt64.init) {
            let (model, _) = makeModel(seed: seed)
            model.startGame()
            guard await playUntilPlayerFinishes(model) else { continue }
            await model.runCPUTurnsIfNeeded()
            #expect(model.phase == .result)
            measured += 1
            worstTurns = max(worstTurns, model.cpuTurnsAfterPlayerFinished)
        }

        #expect(measured >= 20, "人間が先に上がる配りを十分に含むこと（実測 \(measured) 件）")
        let wait = DaifugoModel.finishedCPUDelay * worstTurns
        #expect(wait <= .seconds(10), "最長 \(worstTurns) 手番 = \(wait)")
    }

    /// #157 の計測局面（人間が上がった直後・CPU 13/13/14枚）をそのまま注入して見積もる。
    /// 変更前は 650ms × 手番数 で 30〜35 秒かかっていた区間。
    @Test("#157 の計測局面でも10秒以内に終わる")
    func mostCardsLeftStillFitsInTenSeconds() async {
        let (model, _) = makeModel(seed: 2026)
        var deck = DaifugoCard.makeDeck()
        deck.shuffle(using: &SeededGeneratorBox.shared)
        model.configureForTesting(
            hands: [[], Array(deck[0..<13]), Array(deck[13..<26]), Array(deck[26..<40])],
            currentPlayer: 1,
            finishOrder: [DaifugoModel.humanIndex]
        )
        #expect(model.canSkipToResult, "上がった直後は早送りを出せる")

        await model.runCPUTurnsIfNeeded()

        #expect(model.phase == .result)
        #expect(model.ranking.count == DaifugoModel.playerCount)
        #expect(model.playerPlace == 0, "最初に上がった人は大富豪のまま")
        let wait = DaifugoModel.finishedCPUDelay * model.cpuTurnsAfterPlayerFinished
        #expect(wait <= .seconds(10), "\(model.cpuTurnsAfterPlayerFinished) 手番 = \(wait)")
    }
}

// MARK: - 投了（#194）

@Suite("投了")
@MainActor
struct DaifugoResignTests {

    @Test("対局中だけ投了でき、上がった後は出せない")
    func resignIsOfferedOnlyWhilePlaying() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(3)], [card(4), card(5)], [card(6), card(7)], [card(9), card(10)]]
        )
        #expect(model.canResign, "手札が残っているうちは投了できる")

        model.toggleSelection(card(3))
        model.playSelected()

        #expect(model.isPlayerFinished)
        #expect(model.canResign == false, "上がった後は勝ち取った階級を捨てる操作になるので出さない")
    }

    @Test("投了するとその場で決着し、大貧民・負けとして記録される")
    func resignEndsGameAsLastPlace() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3), card(4)],                  // 人間
                [card(5), card(6), card(7)],         // CPU1: 残り3枚
                [card(9)],                           // CPU2: 残り1枚
                [card(10), card(11)],                // CPU3: 残り2枚
            ],
            currentPlayer: 0
        )

        model.resign()

        #expect(model.phase == .result)
        #expect(model.resigned.contains(DaifugoModel.humanIndex))
        #expect(model.ranking == [2, 3, 1, DaifugoModel.humanIndex],
                "残った CPU は手札の少ない順、投了した自分は最下位")
        #expect(model.playerTitle == "大貧民")
        #expect(model.reviewOutcome == .loss)
    }

    @Test("既に上がった人の順位は投了しても保たれる")
    func resignKeepsAlreadyFinishedPlaces() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3), card(4)],                  // 人間
                [],                                  // CPU1: 上がり済み
                [card(9)],                           // CPU2: 残り1枚
                [card(10), card(11)],                // CPU3: 残り2枚
            ],
            currentPlayer: 0,
            finishOrder: [1]
        )

        model.resign()

        #expect(model.ranking == [1, 2, 3, DaifugoModel.humanIndex])
        #expect(model.playerTitle == "大貧民")
    }

    @Test("反則上がりした CPU がいても、投了した自分が大貧民になる")
    func resignDropsBelowFoulFinisher() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(3), card(4)],                  // 人間
                [joker()],                           // CPU1: ジョーカーで反則上がり
                [card(9)],                           // CPU2: ジョーカーに勝てずパス
                [card(10), card(11)],                // CPU3: 同上
            ],
            currentPlayer: 1
        )
        await model.runCPUTurnsIfNeeded()
        #expect(model.fouls.contains(1), "CPU1 は反則上がりしている")
        #expect(model.isPlayerTurn, "残り3人はジョーカーに勝てず自分の手番に戻る")

        model.resign()

        #expect(model.ranking == [2, 3, 1, DaifugoModel.humanIndex],
                "反則上がりより下に落ちるのは投了した自分")
        #expect(model.playerTitle == "大貧民")
        #expect(model.reviewOutcome == .loss)
    }

    @Test("投了すると中断データが消え、次回は続きからにならない（#194 の主目的）")
    func resignClearsSnapshot() {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.configureForTesting(
            hands: [[card(3), card(4)], [card(5)], [card(9)], [card(10)]],
            currentPlayer: 0
        )
        #expect(store.exists(for: "daifugo"), "対局中はスナップショットが残る")

        model.resign()

        #expect(!store.exists(for: "daifugo"))
        let reopened = DaifugoModel(services: services, cpuDelay: .zero)
        #expect(reopened.phase == .idle, "開き直すとスタートシートから始まる")
    }

    @Test("投了で決まった階級が次のゲームのカード交換に引き継がれる")
    func resignedRankCarriesToNextGame() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [[card(3), card(4)], [card(5)], [card(9)], [card(10)]],
            currentPlayer: 0
        )
        model.resign()
        let ranking = model.ranking

        model.startGame()

        #expect(model.lastRanking == ranking)
        #expect(model.lastTransfers.isEmpty == false, "大貧民として強い札を差し出す")
        #expect(model.resigned.isEmpty, "投了は次のゲームに持ち越さない")
        #expect(model.phase == .playing)
    }
}

/// 上の局面注入で使う決定的な乱数。配りを固定してテストを再現可能にするだけの用途。
private enum SeededGeneratorBox {
    @MainActor static var shared = SeededGenerator(seed: 191)
}

// MARK: - CPU 進行のキャンセル（#287）

@Suite("CPU 進行のキャンセル")
@MainActor
struct DaifugoCancelTests {

    /// 対局中に画面を離れると `.task` のキャンセルが走るが、`try? await Task.sleep(for:)` は
    /// キャンセル時に**即座に**返るため、キャンセル後のループが間合いを一切取らずに残りの
    /// 手番を最後まで走り抜けてしまう（#287）。待ち時間の経過ではなく「キャンセル済みの
    /// タスクが手番を進めないこと」で検証するので、実時間に依存せず安定する。
    @Test("キャンセルされたら間合いを飛ばして打ち続けない")
    func cancelledLoopDoesNotFastForward() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        // キャンセルが効かなければ、この長さを無視して手番が進んでしまう。
        let model = DaifugoModel(services: services, cpuDelay: .seconds(60), seed: 42)
        model.configureForTesting(
            hands: [
                [card(3), card(4)],
                [card(13), card(5)],
                [card(12), card(6)],
                [card(11), card(7)],
            ],
            currentPlayer: 1
        )
        let before = model.hands.map(\.count)

        // MainActor 上なので、この Task の本体は `await` で手放すまで動かない。
        // したがって cancel() は必ず本体の実行より先に確定する（実時間に依存しない）。
        let task = Task { await model.runCPUTurnsIfNeeded() }
        task.cancel()
        await task.value

        #expect(
            model.hands.map(\.count) == before,
            "キャンセル済みのタスクが間合いを無視して手番を進めた"
        )
    }

    /// 先行タスクが `isRunningCPUTurns` を握ったまま suspend している間に新タスクが走ると、
    /// 「新タスクが即リターン → 先行タスクがキャンセルで抜ける」の順で走者が誰もいなくなり
    /// 手番が止まる（麻雀 #311 と同じレース）。新タスクは先行タスクの終了を待って引き継ぐこと。
    @Test("差し替え後の新タスクが先行タスクの終了を待って引き継ぐ（走者不在で止まらない）")
    func replacementTaskTakesOverAfterCancelledPredecessor() async {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = DaifugoModel(services: services, cpuDelay: .milliseconds(30), seed: 42)
        model.configureForTesting(
            hands: [
                [card(3), card(4)],
                [card(13), card(5)],
                [card(12), card(6)],
                [card(11), card(7)],
            ],
            currentPlayer: 1
        )

        // 先行タスク A を起動し、yield で「フラグを立てて sleep に入る」ところまで進める
        // （MainActor は投入順に実行されるため、この yield で A は最初の suspend まで走る）。
        let taskA = Task { await model.runCPUTurnsIfNeeded() }
        await Task.yield()
        // 差し替えを再現する: 新タスク B を起動してから A をキャンセルする。
        let taskB = Task { await model.runCPUTurnsIfNeeded() }
        taskA.cancel()
        await taskA.value
        await taskB.value

        // B が引き継いでいれば CPU の手番では止まらない（人間の手番か決着まで進む）。
        #expect(
            model.phase != .playing || model.currentPlayer == DaifugoModel.humanIndex,
            "走者不在で CPU の手番が止まった"
        )
    }
}
