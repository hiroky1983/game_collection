import Testing
import Foundation
import SwiftUI
import Core
@testable import GameSevens
import CoreTestSupport

// MARK: - Mocks

@MainActor
private func makeModel(
    seed: UInt64? = 42,
    store: SnapshotStore = MemorySnapshotStore()
) -> (SevensModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (SevensModel(services: services, cpuDelay: .zero, seed: seed), services)
}

private func card(_ suit: SevensSuit, _ rank: Int, id: Int = 0) -> SevensCard {
    SevensCard(id: id, suit: suit, rank: rank)
}

/// 人間の手番を貪欲法で自動消化しながら、決着するまで進める。
@MainActor
private func playToFinish(_ model: SevensModel, maxTurns: Int = 500) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing else { break }
        guard model.isPlayerTurn else { continue }
        if let play = SevensRules.greedyPlay(hand: model.playerHand, board: model.board) {
            model.play(play)
        } else {
            model.pass()
        }
    }
    return model.phase == .result
}

// MARK: - 進行

@Suite("七並べの進行")
@MainActor
struct SevensModelTests {

    @Test("配ったカードは52枚すべてが4人に13枚ずつ行き渡る")
    func dealsWholeDeck() {
        let (model, _) = makeModel()
        model.startGame()

        let all = model.hands.flatMap { $0 }
        #expect(all.count == 52)
        #expect(Set(all.map(\.id)).count == 52, "同じ札が2人に配られない")
        #expect(model.hands.allSatisfy { $0.count == 13 })
        #expect(model.phase == .playing)
    }

    @Test("開始プレイヤーはダイヤの7を持つ人")
    func startsWithDiamondSevenHolder() {
        let (model, _) = makeModel()
        model.startGame()

        let holder = model.hands.firstIndex { $0.contains { $0.suit == .diamonds && $0.rank == 7 } }
        #expect(model.currentPlayer == holder)
    }

    @Test("出せる札を出すと場が更新され、次の手番に進む")
    func playingCardAdvancesTurn() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.diamonds, 7, id: 0), card(.spades, 2, id: 1)],
                [card(.hearts, 3, id: 2)],
                [card(.clubs, 4, id: 3)],
                [card(.spades, 5, id: 4)],
            ],
            currentPlayer: 0
        )

        model.play(card(.diamonds, 7, id: 0))

        #expect(model.board[SevensSuit.diamonds.rawValue] == SevensSuitRange(low: 7, high: 7))
        #expect(model.playerHand.map(\.id) == [1])
        #expect(model.currentPlayer == 1)
    }

    @Test("出せない札は何も起きない")
    func playingIllegalCardDoesNothing() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.diamonds, 3, id: 0)],
                [card(.hearts, 3, id: 1)],
                [card(.clubs, 4, id: 2)],
                [card(.spades, 5, id: 3)],
            ],
            currentPlayer: 0
        )

        model.play(card(.diamonds, 3, id: 0))

        #expect(model.playerHand.map(\.id) == [0], "手札は減らない")
        #expect(model.currentPlayer == 0, "手番も進まない")
    }

    @Test("出せる手があるうちはパスできない")
    func cannotPassWhilePlayable() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.diamonds, 7, id: 0)],
                [card(.hearts, 3, id: 1)],
                [card(.clubs, 4, id: 2)],
                [card(.spades, 5, id: 3)],
            ],
            currentPlayer: 0
        )

        model.pass()

        #expect(model.currentPlayer == 0, "出せる手があるのでパスは通らない")
    }

    @Test("出せる手が無いときはパスして次の手番に進む")
    func passAdvancesWhenNothingPlayable() {
        let (model, _) = makeModel()
        var board = SevensRules.emptyBoard()
        board[SevensSuit.diamonds.rawValue] = SevensSuitRange(low: 7, high: 7)
        model.configureForTesting(
            hands: [
                [card(.spades, 2, id: 0)],   // スペードはまだ7が出ていないので出せない
                [card(.hearts, 3, id: 1)],
                [card(.clubs, 4, id: 2)],
                [card(.spades, 5, id: 3)],
            ],
            board: board,
            currentPlayer: 0
        )

        model.pass()

        #expect(model.currentPlayer == 1)
        #expect(model.playerHand.map(\.id) == [0], "パスでは手札は減らない")
    }

    @Test("最後の1枚を出すと決着し、出した人が勝者になる")
    func lastCardEndsGameWithWinner() {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.diamonds, 7, id: 0)],
                [card(.hearts, 3, id: 1)],
                [card(.clubs, 4, id: 2)],
                [card(.spades, 5, id: 3)],
            ],
            currentPlayer: 0
        )

        model.play(card(.diamonds, 7, id: 0))

        #expect(model.phase == .result)
        #expect(model.winner == 0)
        #expect(model.didPlayerWin)
        #expect(model.reviewOutcome == .win)
    }

    @Test("CPU が上がって負けても reviewOutcome は loss")
    func cpuWinIsLossForPlayer() async {
        let (model, _) = makeModel()
        model.configureForTesting(
            hands: [
                [card(.spades, 3, id: 0)],   // 出せない
                [card(.diamonds, 7, id: 1)], // 1手で上がる
                [card(.clubs, 4, id: 2)],
                [card(.hearts, 5, id: 3)],
            ],
            currentPlayer: 1
        )

        await model.runCPUTurnsIfNeeded()

        #expect(model.phase == .result)
        #expect(model.winner == 1)
        #expect(model.reviewOutcome == .loss)
    }

    @Test("ランダムな配りから自動対戦しても必ず決着する")
    func randomGamesAlwaysFinish() async {
        for seed in UInt64(0)..<10 {
            let (model, _) = makeModel(seed: seed)
            model.startGame()
            let finished = await playToFinish(model)
            #expect(finished, "seed \(seed) で決着しなかった")
            #expect(model.winner != nil)
        }
    }

    @Test("中断データから対局を復元できる")
    func resumesFromSnapshot() {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        model.configureForTesting(
            hands: [
                [card(.diamonds, 7, id: 0), card(.spades, 2, id: 1)],
                [card(.hearts, 3, id: 2)],
                [card(.clubs, 4, id: 3)],
                [card(.spades, 5, id: 4)],
            ],
            currentPlayer: 0
        )
        model.play(card(.diamonds, 7, id: 0))

        let (restored, _) = makeModel(store: store)
        #expect(restored.phase == .playing)
        #expect(restored.playerHand.map(\.id) == [1])
        #expect(restored.currentPlayer == 1)
        #expect(restored.board[SevensSuit.diamonds.rawValue] == SevensSuitRange(low: 7, high: 7))
    }

    @Test("配ったばかりの局は保存されない")
    func untouchedDealIsNotPersisted() {
        let store = MemorySnapshotStore()
        let (model, _) = makeModel(store: store)
        model.startGame()

        #expect(!store.exists(for: "sevens"))
    }
}
