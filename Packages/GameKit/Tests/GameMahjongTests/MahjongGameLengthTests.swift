import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong

// MARK: - ヘルパー

/// 中身の JSON を読み書きできる中断データ置き場。旧形式（一局戦が無かった頃の中断データ）を
/// 作るために、保存済みの JSON から鍵を 1 つ落とす経路が要る。
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

    /// 保存済みの JSON から鍵を 1 つ落とす（= その鍵が無かった頃のデータにする）。
    func removeKey(_ key: String, for gameID: String) {
        guard let data = store[gameID],
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        object.removeValue(forKey: key)
        store[gameID] = try? JSONSerialization.data(withJSONObject: object)
    }
}

/// 何を切っても和了に絡まない手（`MahjongModelTests` の同名の関数と同じ意図）。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

/// 親（自分）の聴牌形。流局すると連荘の条件を満たす。
@MainActor
private func dealerTenpaiHand() -> MahjongHand { MahjongNotation.hand("123m456m789m123p1s") }

@MainActor
private func makeModel(
    length: MahjongGameLength,
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

/// 記録の増え方を見るための、テストごとに独立した UserDefaults。
@MainActor
private func makeIsolatedPlayLog() -> (PlayLog, UserDefaults, String) {
    let name = "mahjong.length.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 指定した持ち点で流局させ、対局を終局まで進める。
@MainActor
private func concludeByExhaustiveDraw(
    _ model: MahjongModel,
    hands: [MahjongHand]? = nil,
    dealer: Int = 0,
    scores: [Int]? = nil,
    roundNumber: Int = 1
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

@Suite("対局の長さ（一局戦・#639）")
@MainActor
struct MahjongGameLengthTests {

    @Test("一局戦は東1局が終わったら終局する")
    func singleHandEndsAfterTheFirstHand() {
        let model = makeModel(length: .singleHand)
        concludeByExhaustiveDraw(model)

        #expect(model.phase == .gameResult)
        #expect(model.gameEndReason == .completedAllRounds)
        #expect(model.ranking.count == MahjongModel.playerCount, "順位が出ている")
    }

    @Test("一局戦は親が聴牌で流局しても連荘しない")
    func singleHandDoesNotRepeatDealer() {
        let model = makeModel(length: .singleHand)
        model.configureForTesting(
            hands: [dealerTenpaiHand(), junkHand(), junkHand(), junkHand()],
            wall: [],
            dealer: 0
        )
        model.exhaustWallForTesting()
        #expect(model.handResult?.tenpaiPlayers.contains(0) == true, "連荘の条件自体は満たしている")
        #expect(model.honba == 0, "本場は増えない")

        model.advanceToNextHand()
        #expect(model.phase == .gameResult, "連荘せずそのまま終局する")
        #expect(model.gameEndReason == .completedAllRounds, "アガリやめではない")
    }

    @Test("東風戦は従来どおり親の聴牌で連荘する（既定の退行防止）")
    func tonpuuStillRepeatsDealer() {
        let model = makeModel(length: .tonpuu)
        model.configureForTesting(
            hands: [dealerTenpaiHand(), junkHand(), junkHand(), junkHand()],
            wall: [],
            dealer: 0
        )
        model.exhaustWallForTesting()
        model.advanceToNextHand()

        #expect(model.phase == .playing)
        #expect(model.dealer == 0)
        #expect(model.honba == 1)
        #expect(model.roundNumber == 1)
    }

    @Test("東風戦は東1局が終わっても続く（既定の退行防止）")
    func tonpuuContinuesAfterTheFirstHand() {
        let model = makeModel(length: .tonpuu)
        concludeByExhaustiveDraw(model)

        #expect(model.phase == .playing)
        #expect(model.roundNumber == 2)
    }

    @Test("リザルトのボタンは、その先が終局なら「次の局へ」ではない")
    func knowsWhetherTheResultLeadsToTheEnd() {
        let single = makeModel(length: .singleHand)
        single.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: [],
            dealer: 0
        )
        single.exhaustWallForTesting()
        #expect(single.phase == .handResult)
        #expect(single.concludesAfterCurrentResult, "一局戦は必ずこの局で終わる")

        let tonpuu = makeModel(length: .tonpuu)
        tonpuu.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: [],
            dealer: 0
        )
        tonpuu.exhaustWallForTesting()
        #expect(!tonpuu.concludesAfterCurrentResult, "東1局のあとにはまだ局がある")
    }

    @Test("一局戦の成績は東風戦と別枠で数える")
    func recordsAreKeptSeparately() {
        let (playLog, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }

        let model = makeModel(length: .singleHand, playLog: playLog)
        concludeByExhaustiveDraw(model, scores: [40_000, 20_000, 20_000, 20_000])
        #expect(model.phase == .gameResult)

        #expect(playLog.record(gameID: "mahjong4") == nil, "東風戦の通算成績は増えない")
        let record = playLog.record(gameID: "mahjong4", variant: "singleHand")
        #expect(record?.plays == 1)
        #expect(record?.variantLabel == "一局戦", "ハブの記録行に区分名が出る")
    }

    @Test("東風戦の記録は区分を持たず、これまでの保存先に入り続ける")
    func tonpuuKeepsUsingTheOriginalRecordKey() {
        let (playLog, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }

        let model = makeModel(length: .tonpuu, playLog: playLog)
        concludeByExhaustiveDraw(
            model, dealer: 3, scores: [40_000, 20_000, 20_000, 20_000], roundNumber: 4
        )
        #expect(model.phase == .gameResult)

        let record = playLog.record(gameID: "mahjong4")
        #expect(record?.plays == 1)
        #expect(record?.variantLabel == nil)
        #expect(playLog.record(gameID: "mahjong4", variant: "tonpuu") == nil,
                "区分キーを付けると過去の記録がどこからも参照されなくなる")
    }

    @Test("中断して再開しても一局戦のまま")
    func snapshotCarriesTheLength() {
        let store = RawMemoryStore()
        let model = makeModel(length: .singleHand, store: store)
        #expect(model.phase == .playing)

        let resumed = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero
        )
        #expect(resumed.gameLength == .singleHand)
        #expect(resumed.phase == .playing)
    }

    @Test("一局戦が無かった頃の中断データは東風戦として再開する")
    func legacySnapshotResumesAsTonpuu() {
        let store = RawMemoryStore()
        _ = makeModel(length: .singleHand, store: store)
        store.removeKey("gameLength", for: "mahjong4")

        let resumed = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero
        )
        #expect(resumed.phase == .playing, "鍵が増えても旧データが読めなくなってはいけない")
        #expect(resumed.gameLength == .tonpuu)
    }

    @Test("一局戦ではトビても復活を提示しない")
    func singleHandDoesNotOfferRevive() {
        let single = makeModel(length: .singleHand)
        concludeByExhaustiveDraw(single, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(single.phase == .gameResult)
        #expect(!single.canReviveAfterBust, "復活しても続ける局が無い")

        let tonpuu = makeModel(length: .tonpuu)
        concludeByExhaustiveDraw(tonpuu, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(tonpuu.canReviveAfterBust, "東風戦の途中なら従来どおり提示する")
    }

    @Test("長さを指定しない開始は直前の対局と同じ長さで始まる")
    func startGameKeepsTheLengthWhenUnspecified() {
        let model = makeModel(length: .singleHand)
        model.startGame()
        #expect(model.gameLength == .singleHand)

        model.startGame(length: .tonpuu)
        model.startGame()
        #expect(model.gameLength == .tonpuu)
    }

    @Test("東風戦は区分キーを持たず、順位表の対象から外れない")
    func onlyTonpuuIsLeaderboardEligible() {
        #expect(MahjongGameLength.tonpuu.recordVariant == nil)
        #expect(MahjongGameLength.tonpuu.isLeaderboardEligible)
        #expect(MahjongGameLength.singleHand.recordVariant == "singleHand")
        #expect(!MahjongGameLength.singleHand.isLeaderboardEligible)
        #expect(MahjongGameLength.singleHand.roundCount == 1)
        #expect(MahjongGameLength.tonpuu.roundCount == 4)
    }
}
