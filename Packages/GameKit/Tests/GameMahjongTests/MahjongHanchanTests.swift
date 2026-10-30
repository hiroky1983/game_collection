import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong

// MARK: - ヘルパー

/// 中身の JSON を読み書きできる中断データ置き場（旧データの再現用に鍵を落とせる）。
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
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

@MainActor
private func dealerTenpaiHand() -> MahjongHand { MahjongNotation.hand("123m456m789m123p1s") }

@MainActor
private func makeModel(
    length: MahjongGameLength = .hanchan,
    store: SnapshotStore = RawMemoryStore(),
    playLog: PlayLog? = nil
) -> MahjongModel {
    let model = MahjongModel(
        services: GameServices(snapshots: store, ads: NoopAdService(), playLog: playLog),
        cpuDelay: .zero,
        seed: 2026
    )
    model.startGame(length: length)
    return model
}

/// 全員ノーテンの荒牌流局で `roundNumber` の局を終わらせ、リザルトから先へ進める。
@MainActor
private func drawOut(
    _ model: MahjongModel,
    roundNumber: Int,
    dealer: Int,
    hands: [MahjongHand]? = nil,
    scores: [Int]? = nil
) {
    model.configureForTesting(
        hands: hands ?? Array(repeating: junkHand(), count: MahjongModel.playerCount),
        wall: [],
        dealer: dealer,
        scores: scores,
        roundNumber: roundNumber
    )
    model.exhaustWallForTesting()
    model.advanceToNextHand()
}

// MARK: - Tests

@Suite("半荘戦（#3098）")
@MainActor
struct MahjongHanchanTests {

    @Test("並びは 一局戦・東風戦・半荘戦、局数は 1・4・8")
    func lengthsAndOrder() {
        #expect(MahjongGameLength.allCases == [.singleHand, .tonpuu, .hanchan])
        #expect(MahjongGameLength.hanchan.roundCount == 8)
        #expect(MahjongGameLength.hanchan.allowsDealerRepeat)
    }

    @Test("場は半荘戦の 5 局目から南。東風戦は延長の東 5 局でも東のまま")
    func roundWindFollowsTheRoundNumber() {
        #expect((1...4).map { MahjongGameLength.hanchan.roundWind(forRound: $0) } == [0, 0, 0, 0])
        #expect((5...8).map { MahjongGameLength.hanchan.roundWind(forRound: $0) } == [1, 1, 1, 1])
        #expect((1...5).map { MahjongGameLength.tonpuu.roundWind(forRound: $0) } == [0, 0, 0, 0, 0])
        #expect(MahjongGameLength.hanchan.roundName(forRound: 4) == "東4局")
        #expect(MahjongGameLength.hanchan.roundName(forRound: 5) == "南1局")
        #expect(MahjongGameLength.hanchan.roundName(forRound: 8) == "南4局")
        #expect(MahjongGameLength.tonpuu.roundName(forRound: 5) == "東5局")
    }

    @Test("東 4 局の次は終局せず南 1 局へ進む")
    func eastFourLeadsToSouthOne() {
        let model = makeModel()
        drawOut(model, roundNumber: 4, dealer: 3)
        #expect(model.phase == .playing)
        #expect(model.roundNumber == 5)
        #expect(model.gameLength.roundName(forRound: model.roundNumber) == "南1局")
        #expect(model.dealer == 0)
    }

    @Test("同じ東 4 局が東風戦なら終局する（退行防止）")
    func sameSpotEndsTonpuu() {
        let model = makeModel(length: .tonpuu)
        drawOut(model, roundNumber: 4, dealer: 3)
        #expect(model.phase == .gameResult)
    }

    @Test("南 4 局を終えると終局し、西入はしない")
    func southFourEndsTheGame() {
        let model = makeModel()
        drawOut(model, roundNumber: 8, dealer: 3, scores: [40_000, 20_000, 20_000, 20_000])
        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .completedAllRounds)
        #expect(model.ranking.first == 0)
    }

    @Test("南 4 局で親が聴牌流局しても、親がトップならアガリやめで終わる")
    func agariYameAtSouthFour() {
        let model = makeModel()
        drawOut(
            model, roundNumber: 8, dealer: 0,
            hands: [dealerTenpaiHand(), junkHand(), junkHand(), junkHand()],
            scores: [40_000, 20_000, 20_000, 20_000]
        )
        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .agariYame)
    }

    @Test("南 4 局で親がトップでなければ連荘して続く")
    func dealerRepeatsAtSouthFourWhenNotTop() {
        let model = makeModel()
        drawOut(
            model, roundNumber: 8, dealer: 0,
            hands: [dealerTenpaiHand(), junkHand(), junkHand(), junkHand()],
            scores: [20_000, 40_000, 20_000, 20_000]
        )
        #expect(model.phase == .playing)
        #expect(model.roundNumber == 8)
        #expect(model.honba == 1)
    }

    @Test("途中でトビたら終局し、復活を提示する（東風戦と同じ扱い）")
    func bustEndsEarlyAndOffersRevive() {
        let model = makeModel()
        drawOut(model, roundNumber: 6, dealer: 1, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .busted)
        #expect(model.canReviveAfterBust)
    }

    @Test("中断して再開すると南場の局・長さが戻る")
    func resumeRestoresTheSouthRound() {
        let store = RawMemoryStore()
        let model = makeModel(store: store)
        drawOut(model, roundNumber: 5, dealer: 0)
        #expect(model.roundNumber == 6)

        let resumed = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero
        )
        #expect(resumed.gameLength == .hanchan)
        #expect(resumed.roundNumber == 6)
        #expect(resumed.gameLength.roundWind(forRound: resumed.roundNumber) == 1)
        #expect(resumed.gameLength.roundName(forRound: resumed.roundNumber) == "南2局")
    }

    @Test("場の情報が無い旧データは東場として読む")
    func legacySnapshotIsEastRound() {
        let store = RawMemoryStore()
        let model = makeModel(length: .tonpuu, store: store)
        drawOut(model, roundNumber: 2, dealer: 1)
        store.removeKey("gameLength", for: "mahjong4")

        let resumed = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero
        )
        #expect(resumed.phase == .playing)
        #expect(resumed.gameLength == .tonpuu)
        #expect(resumed.gameLength.roundWind(forRound: resumed.roundNumber) == 0)
    }

    @Test("記録は東風戦・一局戦と別枠で、順位表には送らない")
    func recordsAreSeparateAndNotRanked() {
        let name = "mahjong.hanchan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let playLog = PlayLog(defaults: defaults)

        let model = makeModel(playLog: playLog)
        drawOut(model, roundNumber: 8, dealer: 3, scores: [40_000, 20_000, 20_000, 20_000])
        #expect(model.phase == .gameResult)

        #expect(playLog.record(gameID: "mahjong4") == nil, "東風戦の通算成績は増えない")
        #expect(playLog.record(gameID: "mahjong4", variant: "singleHand") == nil)
        let record = playLog.record(gameID: "mahjong4", variant: "hanchan")
        #expect(record?.plays == 1)
        #expect(record?.variantLabel == "半荘戦")
        #expect(MahjongGameLength.hanchan.recordVariant == "hanchan")
        #expect(!MahjongGameLength.hanchan.isLeaderboardEligible)
        #expect(MahjongGameLength.hanchan.analyticsMode == .hanchan)
    }
}
