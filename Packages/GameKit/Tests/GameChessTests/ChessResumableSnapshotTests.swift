import Testing
import Core
import CoreTestSupport
@testable import GameChess

/// 一手も指していない局は「続きから」に出さない（#1599。#1572 の取りこぼし）。
@Suite("チェスの「続きから」判定（#1599）")
@MainActor
struct ChessResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手指すと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ChessModule()
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        let move = ChessMove.fromUCI("e2e4")!
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        #expect(module.hasResumableSnapshot(in: store), "一手指した局（対照）")
    }

    @Test("人間が黒のとき、CPU の初手だけでは続きではなく手つかず。自分が指すと続きになる（#2508）")
    func blackAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ChessModule()
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .black)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        let reply = model.legalMovesCache.first!
        model.tapSquare(reply.from)
        model.tapSquare(reply.to)
        #expect(module.hasResumableSnapshot(in: store), "自分が指した局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない（#3042）")
    func cpuOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["chess"]),
            isResumable: { _, snapshots in ChessModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "chess")
        let model = ChessGameModel(services: services)
        model.newGame(humanSide: .black)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "chess")
        #expect(spy.quits.isEmpty, "CPU が指しただけでは離脱に数えない")
    }

    @Test("自分が指した後に離れると途中離脱に数える（対照・上のテストが空振りでない証拠・#3042）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["chess"]),
            isResumable: { _, snapshots in ChessModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "chess")
        let model = ChessGameModel(services: services)
        model.newGame(humanSide: .black)
        await model.performAIMoveIfNeeded()
        let reply = model.legalMovesCache.first!
        model.tapSquare(reply.from)
        model.tapSquare(reply.to)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "chess", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["chess"], "自分が指した後は従来どおり数える（対照）")
    }
}
