import Testing
import Foundation
import Core
import SwiftUI
import MahjongTiles
@testable import GameMahjong

// MARK: - ヘルパー

private final class MemoryStore: SnapshotStore, @unchecked Sendable {
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

/// 送信されたイベントをそのまま溜めるスパイ（`AnalyticsTests` の同名の型と同じ形）。
@MainActor
private final class SpyAnalyticsService: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []
    func log(_ event: AnalyticsEvent) { events.append(event) }

    var starts: Int {
        events.filter { if case .gameStart = $0 { return true } else { return false } }.count
    }
    var quits: Int {
        events.filter {
            if case let .gameEnd(_, result, _) = $0 { return result == .quit } else { return false }
        }.count
    }
}

/// 何を切っても和了に絡まない手（`MahjongModelTests` の `junkHand` と同じ意図）。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

@MainActor
private func makeModel(
    store: SnapshotStore = MemoryStore(),
    playLog: PlayLog? = nil,
    analytics: GameAnalytics? = nil
) -> MahjongModel {
    MahjongModel(
        services: GameServices(
            snapshots: store, ads: NoopAdService(), playLog: playLog, analytics: analytics
        ),
        cpuDelay: .zero,
        seed: 2026
    )
}

/// 視聴の**途中で**割り込みを起こせる広告スタブ。
///
/// 広告のロード〜視聴のあいだ画面は操作できるので、そこで「新規対局」を押された状況を作る。
private final class InterruptingAdService: AdService, @unchecked Sendable {
    /// 広告を見ているあいだに起きること（= ユーザーの割り込み）。
    var duringAd: (@MainActor () -> Void)?

    init() {}

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        duringAd?()
        return true
    }
}

/// 記録の増え方を見るための、テストごとに独立した UserDefaults。
@MainActor
private func makeIsolatedPlayLog() -> (PlayLog, UserDefaults, String) {
    let name = "mahjong.newgame.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 人の手番から 1 枚切って、対局を「捨てたら離脱に数える」状態まで進める。
@MainActor
private func discardOnce(_ model: MahjongModel) {
    model.configureForTesting(
        hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
        wall: Array(repeating: .characters(5), count: 20),
        currentPlayer: MahjongModel.humanIndex,
        drawnTile: .characters(9)
    )
    model.discardForTesting(.characters(9), by: MahjongModel.humanIndex)
}

// MARK: - 破棄できるか

@Suite("新規対局（対局の破棄）")
@MainActor
struct MahjongNewGameTests {

    @Test("開始前と決着後は失うものが無いので確認を挟まない")
    func noConfirmationWhenNothingToLose() {
        let model = makeModel()
        #expect(model.phase == .idle)
        #expect(!model.hasGameInProgress, "開始シートを出している段階では捨てる対局が無い")

        model.startGame()
        #expect(model.hasGameInProgress, "配られたら失うものがある")

        model.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: [],
            dealer: 3,
            scores: [20_000, 30_000, 25_000, 25_000],
            roundNumber: 4
        )
        model.exhaustWallForTesting()
        model.advanceToNextHand()
        #expect(model.phase == .gameResult)
        #expect(!model.hasGameInProgress, "終わった対局は捨てるも何も無い")
    }

    @Test("局が進んでいても新規対局で東1局・25000点持ちに戻る")
    func restartResetsToFirstHand() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: Array(repeating: .characters(5), count: 20),
            dealer: 2,
            scores: [12_300, 31_000, 29_700, 27_000],
            roundNumber: 3
        )
        #expect(model.roundNumber == 3)

        model.startGame()

        #expect(model.roundNumber == 1)
        #expect(model.dealer == 0)
        #expect(model.honba == 0)
        #expect(model.riichiSticks == 0)
        #expect(model.scores == Array(repeating: MahjongModel.startingScore,
                                      count: MahjongModel.playerCount))
        #expect(model.discards.allSatisfy { $0.isEmpty }, "河は空に戻る")
        #expect(model.melds.allSatisfy { $0.isEmpty })
        #expect(model.phase == .playing)
    }

    @Test("局のリザルトを見ている途中でも新規対局で配り直せる")
    func restartWorksDuringHandResult() {
        let model = makeModel()
        model.startGame()
        model.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: [],
            dealer: 1,
            scores: [20_000, 30_000, 25_000, 25_000],
            roundNumber: 2
        )
        model.exhaustWallForTesting()
        #expect(model.phase == .handResult)
        #expect(model.hasGameInProgress, "東風戦はまだ終わっていないので捨てるものがある")

        model.startGame()

        #expect(model.phase == .playing)
        #expect(model.roundNumber == 1)
        #expect(model.handResult == nil, "前の局の決着表示は残らない")
    }

    @Test("破棄した東風戦は戦績に載らない")
    func abandonedGameIsNotRecorded() {
        let (playLog, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeModel(playLog: playLog)
        model.startGame()
        discardOnce(model)

        model.startGame()

        #expect(playLog.record(gameID: "mahjong4") == nil,
                "打ち切った対局は勝ちにも負けにも数えない")
    }

    @Test("破棄した局面は中断データから復元できない")
    func abandonedSnapshotIsOverwritten() {
        let store = MemoryStore()
        let model = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: Array(repeating: .characters(5), count: 20),
            dealer: 2,
            scores: [12_300, 31_000, 29_700, 27_000],
            roundNumber: 3
        )
        model.discardForTesting(model.playerHand.tiles[0], by: MahjongModel.humanIndex)
        #expect(store.load(MahjongSnapshot.self, for: "mahjong4")?.roundNumber == 3)

        model.startGame()

        let restored = makeModel(store: store)
        #expect(restored.roundNumber == 1, "残っているのは新しい配牌のほうだけ")
        #expect(restored.scores == Array(repeating: MahjongModel.startingScore,
                                         count: MahjongModel.playerCount))
    }

    @Test("1枚でも切っていれば離脱として game_end(quit) を付けてから次の game_start を送る")
    func abandonSendsQuitThenNewStart() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: ["mahjong4"], now: { Date(timeIntervalSince1970: 0) }
        )
        let model = makeModel(analytics: analytics)
        model.startGame()
        #expect(spy.starts == 1)
        #expect(spy.quits == 0)

        discardOnce(model)
        model.startGame()

        #expect(spy.quits == 1, "捨てた対局の game_end が先に出る")
        #expect(spy.starts == 2, "そのあと新しい対局の game_start が出る")
    }

    @Test("配っただけで切らずに捨てた対局は離脱に数えない")
    func discardlessAbandonIsNotCountedAsQuit() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: ["mahjong4"], now: { Date(timeIntervalSince1970: 0) }
        )
        let model = makeModel(analytics: analytics)
        model.startGame()

        model.startGame()

        #expect(spy.quits == 0)
        #expect(spy.starts == 2)
    }

    /// トビ復活の広告を見ているあいだに「新規対局」を押されたら、**新しい対局に復活を乗せない**。
    ///
    /// 乗ると (1) 始めたばかりの対局の手牌が配り直され、(2) 正しく記録済みの前局の負けが
    /// `cancelLoss` で取り消される。`RewardedRescue` が「#480 → #509 → #511 と 3 回続けて
    /// 空いた穴」と呼んでいるものが、麻雀にも残っていた（#638 でボタンを増やすので塞ぐ）。
    @Test("広告を見ているあいだに新規対局を始めたら、復活は新しい対局に乗らない")
    func reviveDoesNotLandOnTheNewGame() async {
        let (playLog, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let ads = InterruptingAdService()
        let model = MahjongModel(
            services: GameServices(snapshots: MemoryStore(), ads: ads, playLog: playLog),
            cpuDelay: .zero,
            seed: 2026
        )
        model.startGame()
        // 自分がトビて終局させる（= 復活が提示される状態）。
        model.configureForTesting(
            hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
            wall: [],
            scores: [-1_000, 30_000, 35_000, 36_000]
        )
        model.exhaustWallForTesting()
        model.advanceToNextHand()
        #expect(model.phase == .gameResult)
        #expect(model.canReviveAfterBust)
        let lossesAfterBust = playLog.record(gameID: "mahjong4")?.losses
        #expect(lossesAfterBust == 1, "トビの負けはこの時点で正しく記録されている")

        // 広告を見ているあいだに「新規対局」で配り直す。
        ads.duringAd = { model.startGame() }
        let revived = await model.reviveAfterAd()

        #expect(!revived, "入れ替わったあとの対局には復活を適用しない")
        #expect(playLog.record(gameID: "mahjong4")?.losses == lossesAfterBust,
                "記録済みの前局の負けが取り消されない")
        #expect(model.roundNumber == 1, "新しく始めた対局はそのまま続く")
        #expect(model.scores == Array(repeating: MahjongModel.startingScore,
                                      count: MahjongModel.playerCount))
    }
}
