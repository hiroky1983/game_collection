import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [CatPuzzleModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.catpuzzle.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 4×4 の見本（答えは行の順に列 1・3・0・2）。
private let sample = CatPuzzle(
    side: 4,
    rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3],
    solution: [1, 3, 0, 2]
)

/// マスに猫を置く（× → 猫 の 2 タップ）。
@MainActor
private func placeCat(_ model: CatPuzzleModel, at cell: Int) {
    model.tap(cell: cell)
    model.tap(cell: cell)
}

@Suite("おじさんの飼い猫パズルの Model")
@MainActor
struct CatPuzzleModelTests {

    @Test("開始直後は印が無く、残りは部屋の数・ミス 0・戻せない")
    func freshBoard() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), size: .easy, seed: 1)
        #expect(model.size == .easy)
        #expect(model.puzzle.side == 6)
        #expect(model.marks.allSatisfy { $0 == .empty })
        #expect(model.remainingCats == 6)
        #expect(model.mistakes == 0)
        #expect(model.hintsRemaining == CatPuzzleModel.freeHints)
        #expect(!model.canUndo)
        #expect(!model.hasProgressToLose)
        #expect(!model.isSolved)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 1)
        #expect(spy.startLevels == [.beginner])
    }

    @Test("タップで × → 猫 → 空 の順に変わる")
    func tapCycles() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.tap(cell: 1)
        #expect(model.marks[1] == .cross)
        model.tap(cell: 1)
        #expect(model.marks[1] == .cat)
        #expect(model.remainingCats == 3)
        model.tap(cell: 1)
        #expect(model.marks[1] == .empty)
        #expect(model.moves == 3)
        #expect(model.hasProgressToLose == false, "印が無くなった盤は捨ててよい")
    }

    @Test("矛盾する猫を置くとミスが増え、両方の猫に印が付く。直せば印は消える")
    func mistakesAreCounted() {
        let feedback = SpyFeedbackService()
        let model = CatPuzzleModel(services: makeServices(feedback: feedback), puzzle: sample)
        placeCat(model, at: 1)
        #expect(model.mistakes == 0)
        #expect(model.violations.isEmpty)
        placeCat(model, at: 3)
        #expect(model.mistakes == 1)
        #expect(model.violations.cells == [1, 3])
        #expect(model.violations.kinds == [.row])
        #expect(CatPuzzleAccessibility.message(for: model.violations) == "同じ行に2匹")
        // 矛盾を直す（猫 → 空）。印は消え、ミスの数は戻らない。
        model.tap(cell: 3)
        #expect(model.violations.isEmpty)
        #expect(model.mistakes == 1)
        // × を置くだけではミスにならない。
        model.tap(cell: 2)
        #expect(model.mistakes == 1)
    }

    @Test("戻すで直前の印に戻る。やり直しで印が全部消え、ミスとヒントは残る")
    func undoAndReset() {
        let store = MemorySnapshotStore()
        let model = CatPuzzleModel(services: makeServices(store: store), puzzle: sample)
        placeCat(model, at: 1)
        placeCat(model, at: 3)
        #expect(model.canUndo)
        model.undo()
        #expect(model.marks[3] == .cross)
        model.undo()
        #expect(model.marks[3] == .empty)
        #expect(model.marks[1] == .cat)
        #expect(model.violations.isEmpty)
        #expect(store.exists(for: CatPuzzleModel.gameID))

        model.useHint()
        model.reset()
        #expect(model.marks.allSatisfy { $0 == .empty })
        #expect(model.hintCell == nil)
        #expect(model.hintsUsed == 1, "ヒントの回数は引き継ぐ")
        #expect(model.mistakes == 1, "ミスは引き継ぐ")
        #expect(!model.canUndo)
        #expect(!store.exists(for: CatPuzzleModel.gameID), "印の無い盤は保存しない")
    }

    @Test("ヒントは答えの猫のマスを示し、無料ぶん 3 回で尽きる。そこに猫を置くと消える")
    func hints() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), puzzle: sample)
        let target = model.hintTarget
        #expect(target != nil && sample.solutionCells.contains(target!))
        model.useHint()
        #expect(model.hintCell == target)
        #expect(model.hintsRemaining == 2)
        #expect(!model.canHint, "出しているあいだは次のヒントを出さない")
        placeCat(model, at: target!)
        #expect(model.hintCell == nil)
        #expect(model.canHint)
        #expect(model.hintTarget != target, "置いた猫のマスはもう示さない")
        model.useHint()
        placeCat(model, at: model.hintCell!)
        model.useHint()
        #expect(model.hintsRemaining == 0)
        placeCat(model, at: model.hintCell!)
        #expect(!model.canHint, "無料ぶんを使い切った")
        #expect(spy.events.filter { if case .rewardOffer = $0 { return true } else { return false } }.isEmpty, "広告は呼ばない")
    }

    @Test("ヒントは空きの少ない部屋から出す")
    func hintPrefersNarrowRoom() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        // 部屋 2（左下 4 マス）の答え以外を × にする → 部屋 2 の空きが 1 つになる。
        for cell in [9, 12, 13] { model.tap(cell: cell) }
        #expect(model.hintTarget == 8)
    }

    @Test("全部の猫を置くとクリアし、記録はタイム（大きさごと）。中断データは消える")
    func solving() {
        let store = MemorySnapshotStore()
        let spy = SpyAnalyticsService()
        let log = makeLog("solve")
        let clock = ManualClock()
        let model = CatPuzzleModel(services: makeServices(store: store, log: log, analytics: spy), puzzle: sample, size: .easy)
        model.clockNow = clock.now
        for cell in sample.solutionCells.dropLast() { placeCat(model, at: cell) }
        #expect(store.exists(for: CatPuzzleModel.gameID))
        clock.advance(by: .seconds(65))
        model.syncElapsed()
        placeCat(model, at: sample.solutionCells.last!)
        #expect(model.isSolved)
        #expect(model.elapsedSeconds == 65)
        #expect(!model.isCounting)
        #expect(!store.exists(for: CatPuzzleModel.gameID))
        #expect(model.recordResult != nil)
        let record = log.record(gameID: CatPuzzleModel.gameID, variant: "easy")
        #expect(record?.bestSeconds == 65)
        #expect(record?.variantLabel == "かんたん")
        #expect(spy.ends(of: CatPuzzleModel.gameID) == 1)
        #expect(spy.outcomes == [.win])
        // 解き終えた盤はもう触れない。
        model.tap(cell: 0)
        #expect(model.marks[0] == .empty)
    }

    @Test("中断データ: 印を付けた盤は保存され、同じ問題・印・ミス・ヒントで復元される")
    func snapshotRoundTrip() {
        let store = MemorySnapshotStore()
        let first = CatPuzzleModel(services: makeServices(store: store), size: .normal, seed: 9)
        #expect(!store.exists(for: CatPuzzleModel.gameID), "手つかずの盤は保存しない")
        first.tap(cell: 0)
        placeCat(first, at: first.puzzle.solutionCells[0])
        placeCat(first, at: first.puzzle.solutionCells[0] + 1)
        first.useHint()
        #expect(store.exists(for: CatPuzzleModel.gameID))

        let spy = SpyAnalyticsService()
        let second = CatPuzzleModel(services: makeServices(store: store, analytics: spy), size: .easy, seed: 1)
        #expect(second.size == .normal, "保存した大きさが優先される")
        #expect(second.puzzle == first.puzzle)
        #expect(second.marks == first.marks)
        #expect(second.mistakes == 1)
        #expect(second.hintsUsed == 1)
        #expect(second.hintCell == first.hintCell)
        #expect(second.violations == first.violations)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 0, "復元は新しいプレイではない")
    }

    @Test("壊れた中断データは捨てて新規に始める")
    func brokenSnapshotIsIgnored() throws {
        let store = MemorySnapshotStore()
        let broken = CatPuzzleSnapshot(size: "normal", puzzle: sample, marks: [1], elapsedSeconds: 0, mistakes: 0, hintsUsed: 0)
        try store.save(broken, for: CatPuzzleModel.gameID)
        let model = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 2)
        #expect(model.size == .easy)
        #expect(model.puzzle.side == 6)
        #expect(!store.exists(for: CatPuzzleModel.gameID))
    }

    @Test("新規ゲームで問題が変わり、ミス・ヒント・タイムが戻る。大きさも切り替えられる")
    func newGame() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), size: .easy, seed: 5)
        let before = model.puzzle
        placeCat(model, at: 0)
        placeCat(model, at: 1)
        model.useHint()
        model.newGame(size: .hard)
        #expect(model.size == .hard)
        #expect(model.puzzle.side == 8)
        #expect(model.puzzle != before)
        #expect(model.marks.allSatisfy { $0 == .empty })
        #expect(model.mistakes == 0 && model.hintsUsed == 0 && model.elapsedSeconds == 0 && model.hintCell == nil)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 2)
        #expect(spy.startLevels == [.beginner, .hard])
        #expect(spy.quits(of: CatPuzzleModel.gameID) == 1, "途中の盤を捨てたので quit が出る")
    }

    @Test("計時は最初のタップで始まり、離れると止まり、戻ると再開する")
    func timerLifecycle() {
        let clock = ManualClock()
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.clockNow = clock.now
        #expect(!model.isCounting)
        model.tap(cell: 0)
        #expect(model.isCounting)
        clock.advance(by: .seconds(10))
        model.pauseTimer()
        #expect(!model.isCounting)
        #expect(model.elapsedSeconds == 10)
        clock.advance(by: .seconds(30))
        model.resumeTimerIfNeeded()
        #expect(model.isCounting)
        clock.advance(by: .seconds(5))
        model.syncElapsed()
        #expect(model.elapsedSeconds == 15, "止めていたあいだは数えない")
    }
}
