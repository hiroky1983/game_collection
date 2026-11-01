import Testing
import Core
import CoreTestSupport
@testable import GameOthello

/// 一手も打っていない盤は「続きから」に出さない（#1572）。
@Suite("オセロの「続きから」判定（#1572）")
@MainActor
struct OthelloResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手打つと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = OthelloModule()
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(row: 2, col: 3)
        #expect(module.hasResumableSnapshot(in: store), "一手打った盤（対照）")
    }

    @Test("人間が白のとき、CPU の初手だけでは続きではなく手つかず。自分が打つと続きになる（#2508）")
    func whiteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = OthelloModule()
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.isAITurn, "CPU が初手を打った（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        if let point = model.board.validMoves(for: .white).first { model.tap(row: point.0, col: point.1) }
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない（#3042）")
    func cpuOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["othello"]),
            isResumable: { _, snapshots in OthelloModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "othello")
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "othello")
        #expect(spy.quits.isEmpty, "CPU が指しただけでは離脱に数えない")
    }

    @Test("自分が指した後に離れると途中離脱に数える（対照・上のテストが空振りでない証拠・#3042）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["othello"]),
            isResumable: { _, snapshots in OthelloModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "othello")
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        if let point = model.board.validMoves(for: .white).first { model.tap(row: point.0, col: point.1) }
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "othello", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["othello"], "自分が指した後は従来どおり数える（対照）")
    }

    @Test("「待った」で開始局面まで戻したら中断データを消し、離脱に数えない（#3200）")
    func undoToStartClearsSnapshot() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["othello"]),
            isResumable: { _, snapshots in OthelloModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "othello")
        let model = OthelloModel(services: services)
        model.newGame()
        model.tap(row: 2, col: 3)
        await model.performAIMoveIfNeeded()
        #expect(store.exists(for: "othello"), "前提: 1 往復指すと保存される")
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(model.blackCount + model.whiteCount == 4, "前提: 開始局面まで戻った")
        #expect(!store.exists(for: "othello"))
        #expect(OthelloModule().hasUntouchedSnapshot(in: store) == false)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "othello", isResumable: false)
        #expect(spy.quits.isEmpty, "手つかずの局は離脱に数えない")
    }

    @Test("「待った」で戻しても開始局面でなければ従来どおり保存し、続きとして残す（#3200）")
    func undoToMidGameKeepsSnapshot() async {
        let store = MemorySnapshotStore()
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        model.tap(row: 2, col: 3)
        await model.performAIMoveIfNeeded()
        if let point = model.board.validMoves(for: .black).first { model.tap(row: point.0, col: point.1) }
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(OthelloModule().hasResumableSnapshot(in: store))
    }
}
