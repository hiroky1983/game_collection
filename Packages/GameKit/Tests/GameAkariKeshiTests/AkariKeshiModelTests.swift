import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameAkariKeshi

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [AkariKeshiModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.akarikeshi.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 最短の解を押して消し切る。
@MainActor
private func solve(_ model: AkariKeshiModel) {
    let shortest = AkariKeshiLogic.solutions(model.board).min { $0.count < $1.count } ?? []
    for index in shortest.sorted() { model.press(at: index) }
}

@MainActor
@Suite("明かり消しパズルの Model")
struct AkariKeshiModelTests {
    @Test("中断データが無ければ盤を作らずに待ち、何も数えない")
    func idleWithoutSnapshot() {
        let spy = SpyAnalyticsService()
        let model = AkariKeshiModel(services: makeServices(analytics: spy), seed: 1)
        #expect(model.state == .idle)
        #expect(!model.hasPuzzle)
        #expect(!model.hasProgressToLose)
        model.press(at: 12)
        #expect(model.moves == 0, "盤が無いあいだは押せない")
        #expect(spy.starts.isEmpty)
    }

    @Test("始めると最短の手数どおりの解ける盤が出て、game_start に難易度が載る")
    func newGameStarts() {
        let spy = SpyAnalyticsService()
        let model = AkariKeshiModel(services: makeServices(analytics: spy), seed: 2)
        model.newGame(difficulty: .normal)
        #expect(model.state == .playing)
        #expect(model.par == 7)
        #expect(model.moves == 0)
        #expect(AkariKeshiLogic.minimumPresses(model.board) == 7)
        #expect(spy.starts == [AkariKeshiModel.gameID])
        #expect(spy.startLevels == [.normal])
        model.pauseTimer()
    }

    @Test("開いただけの盤は保存しない。1 回押すと保存され、開き直すと続きから")
    func untouchedBoardIsNotSaved() {
        let store = MemorySnapshotStore()
        let model = AkariKeshiModel(services: makeServices(store: store), seed: 3)
        model.newGame(difficulty: .easy)
        #expect(!store.exists(for: AkariKeshiModel.gameID), "手つかずの盤を保存した（#1847）")
        let first = AkariKeshiLogic.solutions(model.board).min { $0.count < $1.count }!.sorted()[0]
        model.press(at: first)
        model.pauseTimer()
        #expect(store.exists(for: AkariKeshiModel.gameID))
        #expect(AkariKeshiModule().hasResumableSnapshot(in: store))

        let restored = AkariKeshiModel(services: makeServices(store: store), seed: 99)
        #expect(restored.state == .playing)
        #expect(restored.board == model.board)
        #expect(restored.moves == 1)
        #expect(restored.par == model.par)
        #expect(restored.difficulty == .easy)
        restored.pauseTimer()
    }

    @Test("押しかけの盤から新しい盤を始めると、前の中断データは消える")
    func newGameClearsOldSnapshot() {
        let store = MemorySnapshotStore()
        let model = AkariKeshiModel(services: makeServices(store: store), seed: 4)
        model.newGame(difficulty: .easy)
        model.press(at: 0)
        #expect(model.hasProgressToLose)
        model.newGame(difficulty: .hard)
        #expect(!store.exists(for: AkariKeshiModel.gameID))
        #expect(model.moves == 0)
        #expect(model.par == 10)
        model.pauseTimer()
    }

    @Test("全部消すとクリア。記録は手数とタイム（難易度ごと）、中断データは消え、game_end は win")
    func clearRecordsAndReports() {
        let store = MemorySnapshotStore()
        let spy = SpyAnalyticsService()
        let feedback = SpyFeedbackService()
        let log = makeLog("clear")
        let clock = ManualClock()
        let model = AkariKeshiModel(services: makeServices(store: store, log: log, analytics: spy, feedback: feedback), seed: 5)
        model.clockNow = clock.now
        model.newGame(difficulty: .easy)
        clock.advance(by: .seconds(12))
        solve(model)
        #expect(model.state == .cleared)
        #expect(model.moves == 4)
        #expect(model.elapsedSeconds == 12)
        #expect(!model.isTimerRunning, "クリアで計時を止める")
        #expect(!store.exists(for: AkariKeshiModel.gameID))
        #expect(feedback.notices(of: .success) == 1)
        #expect(spy.outcomes == [.win])
        let record = log.record(gameID: AkariKeshiModel.gameID, variant: "easy")
        #expect(record?.fewestMoves == 4)
        #expect(record?.bestSeconds == 12)
        #expect(record?.variantLabel == "かんたん")
        #expect(model.recordResult != nil)

        // 決着後は押しても何も変わらない（記録を 2 回つけない）。
        model.press(at: 0)
        #expect(model.moves == 4)
        #expect(spy.outcomes == [.win])
    }

    @Test("遠回りして消しても手数はそのまま記録する")
    func longerSolutionCountsEveryPress() {
        let board = AkariKeshiLogic.board(pressing: [12])
        let model = AkariKeshiModel(services: makeServices(), board: board, par: 1)
        model.press(at: 0)
        model.press(at: 0)
        model.press(at: 12)
        #expect(model.state == .cleared)
        #expect(model.moves == 3)
    }

    @Test("壊れた・消し終えた・解けない・手つかずの中断データは読まない")
    func rejectsBadSnapshots() {
        let solvable = AkariKeshiLogic.board(pressing: [1, 2])
        var unsolvable = AkariKeshiLogic.cleared
        unsolvable[0] = true
        let bad = [
            AkariKeshiSnapshot(board: [true], moves: 1, difficulty: .easy, par: 4, elapsedSeconds: 0),
            AkariKeshiSnapshot(board: AkariKeshiLogic.cleared, moves: 1, difficulty: .easy, par: 4, elapsedSeconds: 0),
            AkariKeshiSnapshot(board: unsolvable, moves: 1, difficulty: .easy, par: 4, elapsedSeconds: 0),
            AkariKeshiSnapshot(board: solvable, moves: 0, difficulty: .easy, par: 4, elapsedSeconds: 0),
            AkariKeshiSnapshot(board: solvable, moves: 1, difficulty: .easy, par: 0, elapsedSeconds: 0),
            AkariKeshiSnapshot(board: solvable, moves: 1, difficulty: .easy, par: 4, elapsedSeconds: -1),
        ]
        for snap in bad {
            let store = MemorySnapshotStore()
            try? store.save(snap, for: AkariKeshiModel.gameID)
            #expect(AkariKeshiModel(services: makeServices(store: store)).state == .idle)
        }
        let store = MemorySnapshotStore()
        try? store.save(AkariKeshiSnapshot(board: solvable, moves: 3, difficulty: .normal, par: 7, elapsedSeconds: 40),
                        for: AkariKeshiModel.gameID)
        let model = AkariKeshiModel(services: makeServices(store: store))
        #expect(model.state == .playing)
        #expect(model.elapsedSeconds == 40)
    }

    @Test("押すと途中離脱として数える盤になり、新しい盤では前の局を quit で閉じる")
    func progressAndQuit() {
        let spy = SpyAnalyticsService()
        let model = AkariKeshiModel(services: makeServices(analytics: spy), seed: 6)
        model.newGame(difficulty: .easy)
        model.press(at: 0)
        model.newGame(difficulty: .easy)
        #expect(spy.outcomes == [.quit])
        #expect(spy.starts.count == 2)
        model.pauseTimer()
    }

    @Test("画面を離れると計時を止め、戻ると続きから数える")
    func timerPauseAndResume() {
        let clock = ManualClock()
        let model = AkariKeshiModel(services: makeServices(), seed: 7)
        model.clockNow = clock.now
        model.newGame(difficulty: .easy)
        #expect(model.isTimerRunning)
        clock.advance(by: .seconds(5))
        model.pauseTimer()
        #expect(!model.isTimerRunning)
        #expect(model.elapsedSeconds == 5)
        clock.advance(by: .seconds(100))
        model.resumeTimerIfNeeded()
        clock.advance(by: .seconds(3))
        model.syncElapsed()
        #expect(model.elapsedSeconds == 8, "離れていた時間は数えない")
        model.pauseTimer()
    }
}
