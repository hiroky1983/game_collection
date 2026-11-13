import Testing
import Core
import CoreTestSupport
@testable import GameShogi

/// 一手も指していない局は「続きから」に出さない（#1599。#1572 の取りこぼし）。
@Suite("将棋の「続きから」判定（#1599）")
@MainActor
struct ShogiResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手指すと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(module.hasResumableSnapshot(in: store), "一手指した局（対照）")
    }

    @Test("人間が後手のとき、CPU の初手だけでは続きではなく手つかず。自分が指すと続きになる（#2508）")
    func goteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        model.apply(model.legalMovesCache.first!)
        #expect(module.hasResumableSnapshot(in: store), "自分が指した局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("駒落ちで CPU が上手（先に指す）のとき、CPU の初手だけでは続きではない（#2508）")
    func handicapCPUUpperOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(handicap: .rook, dropper: .cpu)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store))
    }

    @Test("進み具合は指した手数（#2870）")
    func resumeProgressIsMoveCount() {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(module.resumeProgress(in: store) == "\(model.moves.count)手目")
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない（#3042）")
    func cpuOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["shogi"]),
            isResumable: { _, snapshots in ShogiModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "shogi")
        let model = ShogiGameModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "shogi")
        #expect(spy.quits.isEmpty, "CPU が指しただけでは離脱に数えない")
    }

    @Test("自分が指した後に離れると途中離脱に数える（対照・上のテストが空振りでない証拠・#3042）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["shogi"]),
            isResumable: { _, snapshots in ShogiModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "shogi")
        let model = ShogiGameModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        model.apply(model.legalMovesCache.first!)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "shogi", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["shogi"], "自分が指した後は従来どおり数える（対照）")
    }

    @Test("「待った」で開始局面まで戻したら中断データを消し、離脱に数えない（#3200）")
    func undoToStartClearsSnapshot() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["shogi"]),
            isResumable: { _, snapshots in ShogiModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "shogi")
        let model = ShogiGameModel(services: services)
        model.newGame()
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        await model.performAIMoveIfNeeded()
        #expect(store.exists(for: "shogi"), "前提: 1 往復指すと保存される")
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(model.moves.isEmpty, "前提: 開始局面まで戻った")
        #expect(!store.exists(for: "shogi"))
        #expect(ShogiModule().hasUntouchedSnapshot(in: store) == false)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "shogi", isResumable: false)
        #expect(spy.quits.isEmpty, "手つかずの局は離脱に数えない")
    }

    @Test("「待った」で戻しても開始局面でなければ従来どおり保存し、続きとして残す（#3200）")
    func undoToMidGameKeepsSnapshot() async {
        let store = MemorySnapshotStore()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        await model.performAIMoveIfNeeded()
        model.apply(model.legalMovesCache.first!)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(ShogiModule().hasResumableSnapshot(in: store))
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490）。
@Suite("将棋 CPU 先手の局の新規対局確認（#3490）")
@MainActor
struct ShogiCPUOpeningProgressTests {
    @Test("人間が後手のとき、CPU の初手だけでは失う進行は無く、自分が指すと進行になる")
    func goteAfterCPUOpening() async throws {
        let model = ShogiGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        try #require(!model.moves.isEmpty, "前提: CPU が初手を指した")
        #expect(!model.hasProgressToLose)
        model.apply(try #require(model.legalMovesCache.first))
        #expect(model.hasProgressToLose)
    }

    @Test("駒落ちで CPU が上手（先に指す）のとき、CPU の初手だけでは失う進行は無い")
    func handicapCPUUpperOpening() async throws {
        let model = ShogiGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(handicap: .rook, dropper: .cpu)
        await model.performAIMoveIfNeeded()
        try #require(!model.moves.isEmpty, "前提: CPU が初手を指した")
        #expect(!model.hasProgressToLose)
    }

    @Test("人間が先手のとき、新規直後は無く、1 手指すと進行になる（対照）")
    func senteFirst() {
        let model = ShogiGameModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame()
        #expect(!model.hasProgressToLose)
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.hasProgressToLose)
    }
}
