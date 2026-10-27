import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameShogi

/// 達人（#2698）に初めて勝ったときの専用の演出と Game Center の実績（#2991）。
@MainActor
@Suite("将棋 達人への初勝利（#2991）")
struct ShogiMasterFirstWinTests {
    private final class SpyGameCenter: GameCenterService {
        var reported: [[GameCenterAchievement]] = []
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
            reported.append(achievements)
            completion(true)
        }
    }

    private struct Rig {
        let model: ShogiGameModel
        let spy: SpyFeedbackService
        let center: SpyGameCenter
        let log: PlayLog
    }

    /// ▲5c5b で後手玉が詰む局面（人間が先手）から始める。`aiLevel` が達人なら達人戦。
    private func makeRig(aiLevel: Int?, suite: String, sente: PlayerKind = .human, gote: PlayerKind = .ai) throws -> Rig {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        try store.save(
            ShogiSnapshot(
                initialSfen: "4k4/9/3GGG3/9/9/9/9/9/8K b - 1",
                moves: [], phase: .playing, reviewPly: nil,
                sente: sente, gote: gote, aiLevel: aiLevel,
                startedAt: Date(), undoUsed: false
            ),
            for: "shogi"
        )
        let spy = SpyFeedbackService()
        let center = SpyGameCenter()
        let reporter = GameCenterReporter(service: center, allowedGameIDs: ["shogi"])
        let services = GameServices(snapshots: store, ads: NoopAdService(), feedback: spy, playLog: log, gameCenter: reporter)
        return Rig(model: ShogiGameModel(services: services), spy: spy, center: center, log: log)
    }

    private func winByMate(_ model: ShogiGameModel) throws {
        let mate = try #require(Move.fromUSI("5c5b"))
        model.apply(mate)
        #expect(model.endVerdict == .win)
    }

    @Test("達人に初めて勝つと、専用の見出し・強い触覚・実績の解除")
    func firstWinAgainstMaster() throws {
        let rig = try makeRig(aiLevel: ShogiMasterEngine.level, suite: "asobiba.shogi.masterfirst.1")
        try winByMate(rig.model)
        #expect(rig.model.isMasterFirstWin)
        #expect(rig.spy.notices == [.milestone])
        #expect(rig.spy.impacts == [.rigid])
        #expect(rig.center.reported == [[GameCenterAchievement(achievementID: GameCenterAchievements.shogiMaster, percentComplete: 100)]])
    }

    @Test("2 回目以降の勝ちは通常の演出で、実績も送り直さない")
    func secondWinIsNormal() throws {
        let rig = try makeRig(aiLevel: ShogiMasterEngine.level, suite: "asobiba.shogi.masterfirst.2")
        // 過去に達人（駒落ち）で 1 勝している。
        _ = rig.log.recordResult(gameID: "shogi", outcome: .win,
                                 score: GameScore(variant: "master-rook-player"))
        try winByMate(rig.model)
        #expect(!rig.model.isMasterFirstWin)
        #expect(rig.spy.notices == [.success])
        #expect(rig.spy.impacts.isEmpty)
        #expect(rig.center.reported.isEmpty)
    }

    @Test("達人以外の段に勝っても専用の演出は出ない")
    func otherLevelIsNormal() throws {
        let rig = try makeRig(aiLevel: 1, suite: "asobiba.shogi.masterfirst.3")
        try winByMate(rig.model)
        #expect(!rig.model.isMasterFirstWin)
        #expect(rig.spy.notices == [.success])
        #expect(rig.center.reported.isEmpty)
    }

    @Test("人間同士の対局は達人の勝ちに数えない")
    func humanVersusHumanIsNormal() throws {
        let rig = try makeRig(aiLevel: ShogiMasterEngine.level, suite: "asobiba.shogi.masterfirst.4", gote: .human)
        try winByMate(rig.model)
        #expect(!rig.model.isMasterFirstWin)
        #expect(rig.center.reported.isEmpty)
    }

    @Test("負けは実績にならず、次の対局へ持ち越さない")
    func lossDoesNotCelebrate() throws {
        let rig = try makeRig(aiLevel: ShogiMasterEngine.level, suite: "asobiba.shogi.masterfirst.5")
        rig.model.resign()
        #expect(!rig.model.isMasterFirstWin)
        #expect(rig.spy.notices == [.error])
        #expect(rig.center.reported.isEmpty)
    }

    @Test("実績 ID は ハブの道しるべ（allIDs）に混ぜない")
    func achievementIDIsGameSpecific() {
        #expect(GameCenterAchievements.shogiMaster == "asobiba.shogi.achievement.master")
        #expect(!GameCenterAchievements.allIDs.contains(GameCenterAchievements.shogiMaster))
    }
}
