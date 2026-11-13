import Testing
import Core
import CoreTestSupport
@testable import GameGo

/// 一手も打っていない対局は「続きから」に出さない（#1847）。
@Suite("囲碁の「続きから」判定（#1847）")
@MainActor
struct GoResumableSnapshotTests {
    @Test("黒番は、新規対局の直後は続きではなく、一手打つと続きになる")
    func blackUntouchedIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = GoModule()
        let model = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(row: 4, col: 4)
        #expect(module.hasResumableSnapshot(in: store), "一手打った盤（対照）")
    }

    @Test("白番は、CPU の初手だけでは続きではなく、自分が打つと続きになる")
    func whiteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = GoModule()
        let model = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount >= 1, "CPU が初手を打った（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        let point = (0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.state.illegalReason(for: .play(row: $0.0, col: $0.1)) == nil }
        if let point { model.tap(row: point.0, col: point.1) }
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
    }

    @Test("人間が黒で置き石ありのとき、CPU（白）の初手だけでは続きではなく手つかず（#2508）")
    func handicapBlackAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = GoModule()
        let model = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .black, handicap: 2)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount >= 1, "CPU が初手を打った（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        let point = (0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.state.illegalReason(for: .play(row: $0.0, col: $0.1)) == nil }
        if let point { model.tap(row: point.0, col: point.1) }
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない（#3042）")
    func cpuOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["go"]),
            isResumable: { _, snapshots in GoModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "go")
        let model = GoModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "go")
        #expect(spy.quits.isEmpty, "CPU が指しただけでは離脱に数えない")
    }

    @Test("自分が指した後に離れると途中離脱に数える（対照・上のテストが空振りでない証拠・#3042）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["go"]),
            isResumable: { _, snapshots in GoModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "go")
        let model = GoModel(services: services)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        let point = (0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.state.illegalReason(for: .play(row: $0.0, col: $0.1)) == nil }
        if let point { model.tap(row: point.0, col: point.1) }
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "go", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["go"], "自分が指した後は従来どおり数える（対照）")
    }

    @Test("「待った」で開始局面まで戻したら中断データを消し、離脱に数えない（#3200）")
    func undoToStartClearsSnapshot() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["go"]),
            isResumable: { _, snapshots in GoModule().hasResumableSnapshot(in: snapshots) }
        )
        services.gameDidStart(gameID: "go")
        let model = GoModel(services: services)
        model.newGame()
        model.tap(row: 4, col: 4)
        await model.performAIMoveIfNeeded()
        #expect(store.exists(for: "go"), "前提: 1 往復指すと保存される")
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(model.moveCount == 0, "前提: 開始局面まで戻った")
        #expect(!store.exists(for: "go"))
        #expect(GoModule().hasUntouchedSnapshot(in: store) == false)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "go", isResumable: false)
        #expect(spy.quits.isEmpty, "手つかずの局は離脱に数えない")
    }

    @Test("「待った」で戻しても開始局面でなければ従来どおり保存し、続きとして残す（#3200）")
    func undoToMidGameKeepsSnapshot() async {
        let store = MemorySnapshotStore()
        let model = GoModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame()
        model.tap(row: 4, col: 4)
        await model.performAIMoveIfNeeded()
        let point = (0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.state.illegalReason(for: .play(row: $0.0, col: $0.1)) == nil }
        if let point { model.tap(row: point.0, col: point.1) }
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 待ったを押せる")
        model.undoLastExchange()
        #expect(GoModule().hasResumableSnapshot(in: store))
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490）。
@Suite("囲碁 CPU 先手の局の新規対局確認（#3490）")
@MainActor
struct GoCPUOpeningProgressTests {
    private func firstLegalPoint(_ model: GoModel) -> (Int, Int)? {
        (0..<9).lazy.flatMap { r in (0..<9).map { (r, $0) } }
            .first { model.state.illegalReason(for: .play(row: $0.0, col: $0.1)) == nil }
    }

    @Test("人間が白のとき、CPU の初手だけでは失う進行は無く、自分が打つと進行になる")
    func whiteAfterCPUOpening() async throws {
        let model = GoModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount >= 1, "前提: CPU が初手を打った")
        #expect(!model.hasProgressToLose)
        let point = try #require(firstLegalPoint(model))
        model.tap(row: point.0, col: point.1)
        #expect(model.hasProgressToLose)
    }

    @Test("人間が黒で置き石ありのとき、CPU（白）の初手だけでは失う進行は無い")
    func handicapBlackAfterCPUOpening() async throws {
        let model = GoModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame(humanSide: .black, handicap: 2)
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount >= 1, "前提: CPU が初手を打った")
        #expect(!model.hasProgressToLose)
    }

    @Test("人間が黒の通常対局は、新規直後は無く、1 手打つと進行になる（対照）")
    func blackFirst() {
        let model = GoModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()))
        model.newGame()
        #expect(!model.hasProgressToLose)
        model.tap(row: 4, col: 4)
        #expect(model.hasProgressToLose)
    }
}
