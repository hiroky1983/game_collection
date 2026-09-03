import Testing
import Foundation
import SwiftUI
import Core
@testable import GameBlackjack

// MARK: - Fixtures

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

    /// 生の JSON を書き込む（旧形式のスナップショットを再現する用）。
    func write(raw: Data, for gameID: String) { store[gameID] = raw }
}

private final class SilentAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 地雷や配札と同じで、ブラックジャックも配りが乱数なので**狙った手札を作れない**。
/// 中断スナップショットを自作して注入し、山札の先頭も決め打ちする（#439）。
/// これで「同ランク2枚」「ダブルダウンでちょうどバスト」といった局面を再現できる。
@MainActor
private func makeModel(
    player: [Int],
    dealer: [Int],
    deck: [Int],
    chips: Int = 1000,
    bet: Int = 100,
    hands: [BlackjackHand]? = nil,
    activeHandIndex: Int = 0
) -> (BlackjackModel, MemorySnapshotStore) {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make(player)
    let store = MemorySnapshotStore()
    let restored = hands ?? [BlackjackHand(id: 0, cards: playerCards, bet: bet)]
    let snapshot = BlackjackSnapshot(
        playerHand: playerCards,
        dealerHand: make(dealer),
        deck: make(deck),
        chips: chips,
        bet: restored.reduce(0) { $0 + $1.bet },
        phase: .playerTurn,
        hands: restored,
        activeHandIndex: activeHandIndex
    )
    try? store.save(snapshot, for: "blackjack")
    let services = GameServices(snapshots: store, ads: SilentAdService())
    return (BlackjackModel(services: services), store)
}

/// スプリット用に、同ランク2枚の手をスナップショットから作る。
@MainActor
private func makeSplitReadyModel(
    rank: Int,
    dealer: [Int],
    deck: [Int],
    chips: Int = 1000,
    bet: Int = 100
) -> BlackjackModel {
    makeModel(player: [rank, rank], dealer: dealer, deck: deck, chips: chips, bet: bet).0
}

// MARK: - Double Down

@Suite("ブラックジャックのダブルダウン")
@MainActor
struct BlackjackDoubleDownTests {

    @Test("最初の2枚のときだけ選べる")
    func onlyOnFirstTwoCards() {
        let (model, _) = makeModel(player: [5, 6], dealer: [10, 7], deck: [3, 9])
        #expect(model.isDoubleDownApplicable)
        #expect(model.canDoubleDown)

        model.hit()  // 3枚目を引くと形が崩れる
        #expect(model.playerHand.count == 3)
        #expect(!model.isDoubleDownApplicable)
        #expect(!model.canDoubleDown)
    }

    @Test("3枚目以降に呼んでも何も起きない")
    func ignoredAfterHit() {
        let (model, _) = makeModel(player: [5, 6], dealer: [10, 7], deck: [3, 9, 9])
        model.hit()
        let before = model.playerHand.count

        model.doubleDown()

        #expect(model.playerHand.count == before, "札が増えていない")
        #expect(model.bet == 100, "ベットも倍になっていない")
        #expect(model.phase == .playerTurn)
    }

    @Test("チップが足りなければ選べない（残高ちょうどの全額ベット）")
    func disabledWhenChipsInsufficient() {
        // 残高 100・ベット 100 = 追加で賭けられる余力が 0
        let (model, _) = makeModel(player: [5, 6], dealer: [10, 7], deck: [9], chips: 100, bet: 100)
        #expect(model.isDoubleDownApplicable, "形としては最初の2枚なのでボタン自体は出る")
        #expect(!model.canDoubleDown)

        model.doubleDown()

        #expect(model.bet == 100)
        #expect(model.playerHand.count == 2)
        #expect(model.phase == .playerTurn)
    }

    @Test("ベットが倍になり、1枚だけ引いて強制スタンドする")
    func doublesBetDrawsOneAndStands() {
        // プレイヤー 11 → 9 を引いて 20。ディーラーは 18 で止まる。
        let (model, _) = makeModel(player: [5, 6], dealer: [10, 8], deck: [9, 5])

        model.doubleDown()

        #expect(model.playerHand.count == 3, "引くのは1枚だけ")
        #expect(model.playerValue == 20)
        #expect(model.phase == .result, "自分では止められず、そのままディーラーの番へ進む")
        #expect(model.outcome == .win)
        #expect(model.chips == 1200, "勝てば倍額（200枚）が入る")
    }

    @Test("負ければ倍額を失う")
    func losesDoubleStake() {
        // プレイヤー 11 → 5 を引いて 16。ディーラーは 20。
        let (model, _) = makeModel(player: [5, 6], dealer: [10, 10], deck: [5])

        model.doubleDown()

        #expect(model.outcome == .lose)
        #expect(model.chips == 800)
    }

    @Test("ダブルダウンでバストしても倍額の負けで、ディーラーは引かない")
    func bustOnDoubleLosesDoubleStake() {
        // プレイヤー 20 → 10 を引いて 30。ディーラーは 12 のままで止まる（引かない）。
        let (model, _) = makeModel(player: [10, 10], dealer: [8, 4], deck: [10, 5])

        model.doubleDown()

        #expect(model.outcome == .bust)
        #expect(model.chips == 800)
        #expect(model.dealerHand.count == 2, "全滅したラウンドでディーラーは引かない")
    }

    @Test("ダブルダウンは決着すると場のベットを残さない")
    func clearsBetAfterSettlement() {
        let (model, store) = makeModel(player: [5, 6], dealer: [10, 8], deck: [9])
        model.doubleDown()
        #expect(model.bet == 0)
        #expect(!store.exists(for: "blackjack"), "決着したら中断データは消える")
    }
}

// MARK: - Split

@Suite("ブラックジャックのスプリット")
@MainActor
struct BlackjackSplitTests {

    @Test("同ランク2枚のときだけ選べる")
    func onlyOnSameRankPair() {
        let pair = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9])
        #expect(pair.isSplitApplicable)
        #expect(pair.canSplit)

        // 10 と K は同じ 10 点だがランクが違うので割れない（標準ルール）
        let (sameValue, _) = makeModel(player: [10, 13], dealer: [10, 7], deck: [3, 9])
        #expect(!sameValue.isSplitApplicable)
        #expect(!sameValue.canSplit)
    }

    @Test("チップが足りなければ選べない")
    func disabledWhenChipsInsufficient() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9], chips: 100, bet: 100)
        #expect(model.isSplitApplicable)
        #expect(!model.canSplit)

        model.split()

        #expect(model.hands.count == 1, "割れていない")
        #expect(model.bet == 100)
    }

    @Test("2ハンドに分かれ、それぞれに同額を賭けて1枚ずつ配る")
    func splitsIntoTwoBettedHands() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9])

        model.split()

        #expect(model.hands.count == 2)
        #expect(model.hands.allSatisfy { $0.cards.count == 2 })
        #expect(model.hands.allSatisfy { $0.bet == 100 })
        #expect(model.bet == 200, "場に出ている総額は倍になる")
        #expect(model.hands[0].cards[1].rank == 3, "山札の先頭から順に配られる")
        #expect(model.hands[1].cards[1].rank == 9)
        #expect(model.activeHandIndex == 0, "1つ目の手から操作する")
        #expect(model.phase == .playerTurn)
    }

    @Test("再スプリットはできない")
    func cannotResplit() {
        // 8,8 を割った後、1つ目の手が 8,8 になる配り
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [8, 9])
        model.split()

        #expect(model.hands[0].cards.map(\.rank) == [8, 8])
        #expect(!model.isSplitApplicable, "同ランク2枚でも2手目以降は割れない")
        model.split()
        #expect(model.hands.count == 2)
    }

    @Test("2ハンドが順に進行する")
    func playsHandsInOrder() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9, 10, 2])
        model.split()

        #expect(model.activeHandIndex == 0)
        #expect(model.playerHand.map(\.rank) == [8, 3], "playerHand は操作中の手を指す")

        model.hit()  // ハンド1（8+3=11）に 10 → 21
        #expect(model.activeHandIndex == 0, "バストしない限り同じ手を続ける")
        #expect(model.playerValue == 21)

        model.stand()
        #expect(model.activeHandIndex == 1, "スタンドで次の手へ移る")
        #expect(model.playerHand.map(\.rank) == [8, 9])
        #expect(model.phase == .playerTurn, "2つ目が残っているのでまだ決着しない")

        model.stand()
        #expect(model.phase == .result, "両方終わればディーラーの番を経て決着する")
    }

    @Test("独立に精算される（片方勝ち・片方負けなら収支ゼロ）")
    func settlesEachHandIndependently() {
        // 8,8 を割り、1つ目は 8+10=18、2つ目は 8+3=11 のまま止める。ディーラーは 17。
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [10, 3])
        model.split()
        model.stand()   // ハンド1 = 18（勝ち）
        model.stand()   // ハンド2 = 11（負け）

        #expect(model.dealerValue == 17)
        #expect(model.hands[0].outcome == .win)
        #expect(model.hands[1].outcome == .lose)
        #expect(model.chips == 1000, "+100 と -100 で相殺される")
        #expect(model.outcome == .push, "まとめの表示は収支で決める")
        #expect(model.reviewOutcome == .draw)
    }

    @Test("両方勝てば2倍もらえる")
    func winningBothPaysTwice() {
        // 10,10 を割り、それぞれ 10+9=19 / 10+9=19。ディーラーは 17。
        let model = makeSplitReadyModel(rank: 10, dealer: [10, 7], deck: [9, 9])
        model.split()
        model.stand()
        model.stand()

        #expect(model.hands.allSatisfy { $0.outcome == .win })
        #expect(model.chips == 1200)
        #expect(model.outcome == .win)
    }

    @Test("スプリットで作った21はナチュラルとして精算しない")
    func splitTwentyOneIsNotNatural() {
        // A,A を割ると各手が A + 10 = 21 になるが、1.5倍払いにはしない。
        // ディーラーは 20 なので、ナチュラルなら +150×2、通常勝ちなら +100×2。
        let model = makeSplitReadyModel(rank: 1, dealer: [10, 10], deck: [13, 12])

        model.split()

        #expect(model.hands.allSatisfy { $0.value == 21 })
        #expect(model.hands.allSatisfy { $0.outcome == .win }, "ブラックジャックではなく通常の勝ち")
        #expect(model.hands.allSatisfy { $0.outcome != .playerBlackjack })
        #expect(model.chips == 1200, "1.5倍払い（1300）にはならない")
    }

    @Test("スプリットしたAは1枚ずつで強制スタンドする")
    func splitAcesDrawOnlyOneCard() {
        let model = makeSplitReadyModel(rank: 1, dealer: [10, 7], deck: [5, 5, 9, 9])

        model.split()

        #expect(model.hands.allSatisfy { $0.cards.count == 2 }, "Aに追加で引けない")
        #expect(model.hands.allSatisfy { $0.isDone })
        #expect(model.phase == .result, "操作を挟まずディーラーの番へ進む")
    }

    @Test("片方だけバストしても、もう片方は続く")
    func oneBustedHandDoesNotEndTheRound() {
        // 10,10 を割り、1つ目に 5 → 25 でバスト。2つ目は 10+9=19 で勝つ。
        let model = makeSplitReadyModel(rank: 10, dealer: [10, 7], deck: [10, 9, 5])
        model.split()

        model.hit()  // ハンド1 に 5 → 25
        #expect(model.hands[0].isBusted)
        #expect(model.phase == .playerTurn, "ラウンドはまだ終わらない")
        #expect(model.activeHandIndex == 1)

        model.stand()
        #expect(model.hands[0].outcome == .bust)
        #expect(model.hands[1].outcome == .win)
        #expect(model.chips == 1000, "-100 と +100 で相殺")
    }

    @Test("両方バストならディーラーは引かない")
    func dealerStaysWhenAllHandsBust() {
        // 10,10 を割り、両方に 10 を足して 30 にする。ディーラーは 12（本来なら引く手）。
        let model = makeSplitReadyModel(rank: 10, dealer: [8, 4], deck: [10, 10, 10, 10, 5])
        model.split()
        model.hit()
        model.hit()

        #expect(model.hands.allSatisfy { $0.isBusted })
        #expect(model.dealerHand.count == 2, "全滅したのでディーラーは引かない")
        #expect(model.chips == 800)
        #expect(model.outcome == .lose)
    }

    @Test("分けた手でもダブルダウンできる")
    func canDoubleAfterSplit() {
        // 8,8 を割り、1つ目が 8+3=11 になったところでダブルダウン。
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9, 10])
        model.split()

        #expect(model.isDoubleDownApplicable)
        model.doubleDown()

        #expect(model.hands[0].bet == 200)
        #expect(model.hands[0].value == 21)
        #expect(model.activeHandIndex == 1, "ダブルは強制スタンドなので次の手へ移る")
        #expect(model.bet == 300, "場の総額は 200 + 100")
    }

    @Test("スプリットしたラウンドでもチップが尽きればセッション終了になる")
    func sessionEndsWhenChipsRunOut() {
        // 残高 200・各手 100 で両方負ける
        let model = makeSplitReadyModel(rank: 10, dealer: [10, 10], deck: [2, 2], chips: 200)
        model.split()
        model.stand()
        model.stand()

        #expect(model.chips == 0)
        #expect(model.sessionOver)
    }
}

// MARK: - 中断と復帰

@Suite("ブラックジャックの中断データ")
@MainActor
struct BlackjackSnapshotTests {

    @Test("スプリット中に中断しても2つの手が戻る")
    func restoresSplitHands() {
        let model = makeSplitReadyModel(rank: 8, dealer: [10, 7], deck: [3, 9, 5])
        model.split()
        model.stand()  // ハンド2 を操作中の状態で中断する

        // 同じ保存領域から作り直す = アプリを開き直した状態
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: SilentAdService())
        let saving = BlackjackModel(services: services)
        #expect(saving.phase == .betting, "空の保存領域からは通常どおり賭けから始まる")

        // 実際の保存内容で復帰させる
        let reopened = reopen(model)
        #expect(reopened.hands.count == 2)
        #expect(reopened.activeHandIndex == 1)
        #expect(reopened.bet == 200)
        #expect(reopened.hands.map { $0.cards.map(\.rank) } == [[8, 3], [8, 9]])
        #expect(reopened.hands[0].isDone)
    }

    @Test("#439 以前の中断データ（hands が無い）からも復帰できる")
    func restoresLegacySnapshot() {
        // 旧形式のキーだけを持つ JSON を直接置く
        let legacy = """
        {
          "playerHand": [
            {"id": 0, "suit": 0, "rank": 10},
            {"id": 1, "suit": 1, "rank": 6}
          ],
          "dealerHand": [
            {"id": 2, "suit": 2, "rank": 9},
            {"id": 3, "suit": 3, "rank": 7}
          ],
          "deck": [{"id": 4, "suit": 0, "rank": 5}],
          "chips": 900,
          "bet": 200,
          "phase": "playerTurn"
        }
        """
        let store = MemorySnapshotStore()
        store.write(raw: Data(legacy.utf8), for: "blackjack")
        let services = GameServices(snapshots: store, ads: SilentAdService())

        let model = BlackjackModel(services: services)

        #expect(model.phase == .playerTurn)
        #expect(model.hands.count == 1)
        #expect(model.playerHand.map(\.rank) == [10, 6])
        #expect(model.hands[0].bet == 200, "総ベット額がそのままその手の賭け金になる")
        #expect(model.chips == 900)

        // 旧データからでも新しい操作が普通に効く
        model.stand()
        #expect(model.phase == .result)
        #expect(model.chips == 700, "16 対 ディーラー 16→21 で負け")
    }

    /// 保存済みの中断データから作り直したモデル。
    @MainActor
    private func reopen(_ model: BlackjackModel) -> BlackjackModel {
        // `makeModel` が渡した store をモデル自身が持っているため、
        // ここでは同じ内容をもう一度書き戻して復帰させる。
        let store = MemorySnapshotStore()
        let snapshot = BlackjackSnapshot(
            playerHand: model.playerHand,
            dealerHand: model.dealerHand,
            deck: [],
            chips: model.chips,
            bet: model.bet,
            phase: model.phase,
            hands: model.hands,
            activeHandIndex: model.activeHandIndex
        )
        try? store.save(snapshot, for: "blackjack")
        return BlackjackModel(services: GameServices(snapshots: store, ads: SilentAdService()))
    }
}

// MARK: - 既存の挙動が退行していないこと

@Suite("ブラックジャックの基本操作（#439 の退行防止）")
@MainActor
struct BlackjackBaselineTests {

    @Test("ヒットでバストすると即座に負けになり、ディーラーは引かない")
    func bustEndsRoundImmediately() {
        let (model, _) = makeModel(player: [10, 10], dealer: [8, 4], deck: [10])

        model.hit()

        #expect(model.outcome == .bust)
        #expect(model.chips == 900)
        #expect(model.bet == 0)
        #expect(model.phase == .result)
        #expect(model.dealerHand.count == 2)
        #expect(model.reviewOutcome == .loss)
    }

    @Test("スタンドするとディーラーが17以上まで引く（S17）")
    func dealerHitsUntilSeventeen() {
        let (model, _) = makeModel(player: [10, 8], dealer: [5, 6], deck: [5, 4, 10])

        model.stand()

        #expect(model.dealerValue == 20, "11 → 16 → 20 で止まる")
        #expect(model.dealerHand.count == 4)
        #expect(model.outcome == .lose)
    }

    @Test("次のラウンドへ進むと手も場のベットも空になる")
    func nextRoundClearsTable() {
        let (model, _) = makeModel(player: [10, 8], dealer: [10, 7], deck: [5])
        model.stand()

        model.nextRound()

        #expect(model.hands.isEmpty)
        #expect(model.playerHand.isEmpty)
        #expect(model.bet == 0)
        #expect(model.phase == .betting)
        #expect(model.outcome == nil)
    }

    @Test("ベットするとダブルダウンとスプリットの可否が手札から決まる")
    func freshDealExposesOptions() {
        let model = BlackjackModel(seed: 42)
        model.placeBet(100)
        guard model.phase == .playerTurn else { return }

        let hand = model.playerHand
        #expect(model.isDoubleDownApplicable == (hand.count == 2))
        #expect(model.isSplitApplicable == (hand.count == 2 && hand[0].rank == hand[1].rank))
    }
}
