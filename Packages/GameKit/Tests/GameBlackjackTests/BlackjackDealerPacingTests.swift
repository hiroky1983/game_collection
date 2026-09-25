import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

// MARK: - Mocks

// MARK: - 局面の組み立て

/// 「あなた 18 対 ディーラー 12（伏せ札あり）」でスタンド直前の中断データ。
/// 山札は 2 → 2 → 3 の順なので、ディーラーは 14 → 16 → 19 と 3 枚引いて止まり、プレイヤーが負ける。
/// 1 枚ずつ引く途中の状態を順に確かめられるよう、引く枚数が 2 枚以上になる手にしてある。
@MainActor
private func makeStandingModel(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    dealerDrawInterval: Duration
) -> (BlackjackModel, SpyFeedbackService, MemorySnapshotStore) {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make([10, 8])
    let snapshot = BlackjackSnapshot(
        playerHand: playerCards,
        dealerHand: make([10, 2]),
        deck: make([2, 2, 3, 10]),
        chips: 1000,
        bet: 100,
        phase: .playerTurn,
        hands: [BlackjackHand(id: 0, cards: playerCards, bet: 100)],
        activeHandIndex: 0,
        hasRevivedThisSession: false
    )
    try? store.save(snapshot, for: "blackjack")
    let spy = SpyFeedbackService()
    let model = BlackjackModel(
        services: GameServices(
            snapshots: store, ads: NoopAdService(), feedback: spy,
            playLog: PlayLog(defaults: UserDefaults(suiteName: "bj-pacing-\(UUID().uuidString)")!)
        ),
        dealerDrawInterval: dealerDrawInterval
    )
    return (model, spy, store)
}

/// 途中で止めずに引き切ったときのディーラーの手（10, 2, 2, 2, 3 = 19）。
private let expectedDealerRanks = [10, 2, 2, 2, 3]

// MARK: - Tests

@Suite("ブラックジャック: ディーラーを1枚ずつ引く間（#667）")
@MainActor
struct BlackjackDealerPacingTests {

    @Test("間が 0 なら従来どおりスタンドした瞬間に引き切って精算する")
    func zeroIntervalResolvesImmediately() {
        let (model, spy, store) = makeStandingModel(dealerDrawInterval: .zero)

        model.stand()

        #expect(model.phase == .result)
        #expect(model.dealerHand.map(\.rank) == expectedDealerRanks)
        #expect(model.outcome == .lose)
        #expect(model.dealerTask == nil)
        #expect(spy.notices == [.error])
        #expect(!store.exists(for: "blackjack"))
    }

    @Test("間があればスタンド直後はディーラーの番に留まり、記録も勝敗の触覚もまだ出ない")
    func standWaitsBeforeDrawing() async {
        let (model, spy, store) = makeStandingModel(dealerDrawInterval: .milliseconds(1))

        model.stand()

        #expect(model.phase == .dealerTurn)
        #expect(model.dealerHand.count == 2, "1 枚目を引く前に間がある")
        #expect(model.recordResult == nil, "引き終わる前に記録を確定していない")
        #expect(spy.notices.isEmpty, "引き終わる前に勝敗が伝わっていない")
        #expect(store.exists(for: "blackjack"), "引いている途中も中断データが残る")

        let task = model.dealerTask
        #expect(task != nil)
        await task?.value

        #expect(model.phase == .result)
        #expect(model.dealerHand.map(\.rank) == expectedDealerRanks, "待っても引く札は変わらない")
        #expect(model.outcome == .lose)
        #expect(model.chips == 900)
        #expect(model.recordResult != nil, "精算で記録が確定する")
        #expect(spy.notices == [.error], "勝敗の触覚は精算で 1 回だけ")
        #expect(spy.impacts.isEmpty, "ディーラー（CPU）の引きでは鳴らさない")
        #expect(!store.exists(for: "blackjack"))
        #expect(model.dealerTask == nil)
    }

    @Test("「結果まで進める」で待たずに引き切り、止めた Task は後から札を足さない")
    func skipResolvesAtOnce() async {
        let (model, spy, store) = makeStandingModel(dealerDrawInterval: .seconds(3600))
        model.stand()
        #expect(model.phase == .dealerTurn)
        let task = model.dealerTask

        model.skipDealerDraws()

        #expect(model.phase == .result)
        #expect(model.dealerHand.map(\.rank) == expectedDealerRanks, "飛ばしても結果は変わらない")
        #expect(model.chips == 900)
        #expect(spy.notices == [.error])
        #expect(!store.exists(for: "blackjack"))

        // 1 時間の待ちは取り消しで即座に終わる。終わったあとに札も精算も増えていない。
        await task?.value
        #expect(model.dealerHand.map(\.rank) == expectedDealerRanks)
        #expect(model.chips == 900, "二重に精算していない")
        #expect(spy.notices == [.error])
    }

    @Test("ディーラーの番でなければ「結果まで進める」は何もしない")
    func skipOutsideDealerTurnIsIgnored() {
        let (model, spy, _) = makeStandingModel(dealerDrawInterval: .seconds(3600))

        model.skipDealerDraws()

        #expect(model.phase == .playerTurn)
        #expect(model.dealerHand.count == 2)
        #expect(spy.notices.isEmpty)
    }

    @Test("引いている途中で中断したら、スタンド前へ戻さず続きから引いて精算する")
    func restoringMidDrawFinishesTheDealerTurn() async {
        let store = MemorySnapshotStore()
        let (interrupted, _, _) = makeStandingModel(store: store, dealerDrawInterval: .seconds(3600))
        interrupted.stand()
        #expect(interrupted.phase == .dealerTurn)
        let saved = store.load(BlackjackSnapshot.self, for: "blackjack")
        #expect(saved?.phase == .dealerTurn, "スタンド前の中断データが残っていると選び直せてしまう")

        // 途中で落ちた前提。新しい画面は同じ中断データから始まる。
        let reopened = BlackjackModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            dealerDrawInterval: .zero
        )

        #expect(reopened.phase == .result)
        #expect(reopened.dealerHand.map(\.rank) == expectedDealerRanks)
        #expect(reopened.chips == 900)
        #expect(!store.exists(for: "blackjack"))

        let task = interrupted.dealerTask
        task?.cancel()
        await task?.value
    }

    @Test("引いている途中でやり直したら、新しいセッションの卓に前の局の札が足されない")
    func restartCancelsTheDraws() async {
        let (model, spy, _) = makeStandingModel(dealerDrawInterval: .milliseconds(1))
        model.stand()
        let task = model.dealerTask

        model.restartSession()
        await task?.value

        #expect(model.phase == .betting)
        #expect(model.dealerHand.isEmpty)
        #expect(model.chips == BlackjackModel.initialChips)
        #expect(model.recordResult == nil)
        #expect(spy.notices.isEmpty)
    }

    // MARK: - 定数と結線

    @Test("引きの間は伏せカードが返りきるより長く、Model へ渡す Duration と一致する")
    func drawIntervalOutlastsTheHoleCardFlip() {
        #expect(BlackjackMotion.dealerDrawDelay > BlackjackMotion.holeCardFlipDuration)
        #expect(BlackjackMotion.dealerDrawInterval == .milliseconds(350))
        // 1 枚ごとに待たせすぎると、毎ラウンドの結果待ちが重くなる。
        #expect(BlackjackMotion.dealerDrawDelay <= 0.5)
    }

    @Test("画面が引きの間を Model へ渡し、ディーラーの番に「結果まで進める」を出す")
    func viewIsWiredToThePacing() throws {
        let source = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")

        #expect(source.contains("var dealerDrawInterval = BlackjackMotion.dealerDrawInterval"))
        #expect(source.contains("BlackjackModel(services: services, dealerDrawInterval: dealerDrawInterval)"))
        #expect(source.contains("case .dealerTurn:\n            dealerTurnView"))
        #expect(source.contains("model.skipDealerDraws()"))
    }
}
