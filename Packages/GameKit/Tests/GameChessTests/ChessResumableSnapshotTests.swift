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

    @Test("「待った」で開始局面まで戻したら中断データを消し、離脱に数えない（#3200）")
    func undoToStartClearsSnapshot() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["chess"]),
            isResumable: { _, snapshots in ChessModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "chess")
        let model = ChessGameModel(services: services)
        model.newGame()
        let move = ChessMove.fromUCI("e2e4")!
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
        #expect(store.exists(for: "chess"), "前提: 1 往復指すと保存される")
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(model.moves.isEmpty, "前提: 開始局面まで戻った")
        #expect(!store.exists(for: "chess"))
        #expect(ChessModule().hasUntouchedSnapshot(in: store) == false)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "chess", isResumable: false)
        #expect(spy.quits.isEmpty, "手つかずの局は離脱に数えない")
    }

    @Test("「待った」で戻しても開始局面でなければ従来どおり保存し、続きとして残す（#3200）")
    func undoToMidGameKeepsSnapshot() async {
        let store = MemorySnapshotStore()
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        let move = ChessMove.fromUCI("e2e4")!
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
        let next = model.legalMovesCache.first!
        model.tapSquare(next.from)
        model.tapSquare(next.to)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(ChessModule().hasResumableSnapshot(in: store))
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490）。
@Suite("チェス CPU 先手の局の新規対局確認（#3490）")
@MainActor
struct ChessCPUOpeningProgressTests {
    @Test("人間が黒のとき、CPU の初手だけでは失う進行は無く、自分が指すと進行になる")
    func blackAfterCPUOpening() async throws {
        let model = ChessGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(humanSide: .black)
        await model.performAIMoveIfNeeded()
        try #require(!model.moves.isEmpty, "前提: CPU が初手を指した")
        #expect(!model.hasProgressToLose)
        let reply = try #require(model.legalMovesCache.first)
        model.tapSquare(reply.from)
        model.tapSquare(reply.to)
        #expect(model.hasProgressToLose)
    }

    @Test("人間が白のとき、新規直後は無く、1 手指すと進行になる（対照）")
    func whiteFirst() {
        let model = ChessGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame()
        #expect(!model.hasProgressToLose)
        let move = ChessMove.fromUCI("e2e4")!
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        #expect(model.hasProgressToLose)
    }
}
