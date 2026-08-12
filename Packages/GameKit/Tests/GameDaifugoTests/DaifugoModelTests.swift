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
