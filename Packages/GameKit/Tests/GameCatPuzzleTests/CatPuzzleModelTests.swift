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

    @Test("答えでないマスに猫を置こうとすると、猫は置かれず赤い × が固定で付き、ミスが 1 増える")
    func wrongCatBecomesFixedRedCross() {
        let store = MemorySnapshotStore()
        let model = CatPuzzleModel(services: makeServices(store: store), puzzle: sample)
        placeCat(model, at: 1)
        #expect(model.mistakes == 0, "答えのマスの猫はミスにならない")
        #expect(model.marks[1] == .cat && model.wrongCrosses.isEmpty)
        // 3 は答えでない（1 行目の答えは 1）。× → 猫 にしようとすると赤い × になる。
        placeCat(model, at: 3)
        #expect(model.marks[3] == .cross, "猫は置かれない")
        #expect(model.wrongCrosses == [3])
        #expect(model.lastWrongCell == 3)
        #expect(model.mistakes == 1)
        #expect(!model.catCells.contains(3))
        // タップしても消えない・ミスも増えない。
        model.tap(cell: 3)
        model.tap(cell: 3)
        #expect(model.marks[3] == .cross && model.mistakes == 1)
        // 次の操作で直近の印（揺れ・赤枠）は消えるが、赤い × は残る。
        model.tap(cell: 2)
        #expect(model.lastWrongCell == nil)
        #expect(model.mistakes == 1, "× を置くだけではミスにならない")
        // 戻す・やり直しでも消えない。
        while model.canUndo { model.undo() }
        #expect(model.marks[3] == .cross && model.wrongCrosses == [3])
        model.reset()
        #expect(model.marks[3] == .cross && model.wrongCrosses == [3])
        #expect(model.marks.indices.filter { model.marks[$0] != .empty } == [3], "残るのは赤い × だけ")
        #expect(model.mistakes == 1)
        // 中断データに残る（赤い × だけの盤も「続き」）。
        #expect(store.exists(for: CatPuzzleModel.gameID))
        let saved = store.load(CatPuzzleSnapshot.self, for: CatPuzzleModel.gameID)
        #expect(saved?.wrongCrosses == [3] && saved?.marks[3] == CatPuzzleModel.Mark.cross.rawValue && saved?.mistakes == 1)
        // 再開後も残る・消せないことは `snapshotRoundTrip`（本物の大きさの問題）で見る。
    }

    @Test("赤い × より前の中断データに残る答えでない猫は、赤い × に置き換えて再開する（ミスは足さない）")
    func legacyWrongCatIsConverted() throws {
        let store = MemorySnapshotStore()
        // 6×6 の正しい問題を作り、その盤で旧データ（答えの猫 1 匹・答えでない猫 1 匹）を組む。
        let base = CatPuzzleModel(services: makeServices(), size: .easy, seed: 3).puzzle
        var baseMarks = Array(repeating: 0, count: base.cellCount)
        let answer = base.solutionCells[0]
        let wrong = (0..<base.cellCount).first { !base.solutionCells.contains($0) }!
        baseMarks[answer] = 2
        baseMarks[wrong] = 2
        try store.save(CatPuzzleSnapshot(size: "easy", puzzle: base, marks: baseMarks, elapsedSeconds: 30, mistakes: 1, hintsUsed: 0),
                       for: CatPuzzleModel.gameID)
        let model = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 9)
        #expect(model.puzzle == base)
        #expect(model.marks[answer] == .cat)
        #expect(model.marks[wrong] == .cross && model.wrongCrosses == [wrong])
        #expect(model.mistakes == 1)
        #expect(model.catCells == [answer])
    }

    @Test("戻すで直前の印に戻る。やり直しで印が全部消え、ミスとヒントは残る")
    func undoAndReset() {
        let store = MemorySnapshotStore()
        let model = CatPuzzleModel(services: makeServices(store: store), puzzle: sample)
        placeCat(model, at: 1)
        placeCat(model, at: 3)   // 答えでない → 赤い ×（ミス 1・戻す対象にならない）
        model.tap(cell: 2)
        #expect(model.canUndo)
        model.undo()
        #expect(model.marks[2] == .empty)
        #expect(model.marks[3] == .cross, "赤い × は戻しても残る")
        while model.canUndo { model.undo() }
        #expect(model.marks[1] == .empty)
        #expect(model.marks[3] == .cross)
        placeCat(model, at: 1)
        #expect(model.marks[1] == .cat)
        #expect(store.exists(for: CatPuzzleModel.gameID))

        model.useHint()
        let hintCrosses = model.hintCrosses
        #expect(!hintCrosses.isEmpty, "猫 1 匹の盤では、ヒントは × を置く推理になる")
        model.tap(cell: 5)
        model.reset()
        #expect(model.marks.indices.allSatisfy { model.marks[$0] == (hintCrosses.union([3]).contains($0) ? .cross : .empty) }, "ヒントの印と赤い × だけ残る")
        #expect(model.hintCrosses == hintCrosses)
        #expect(model.lastHint == nil)
        #expect(model.hintsUsed == 1, "ヒントの回数は引き継ぐ")
        #expect(model.mistakes == 1, "ミスは引き継ぐ")
        #expect(!model.canUndo)
        #expect(store.exists(for: CatPuzzleModel.gameID), "ヒントの印がある盤は保存する")
    }

    @Test("ヒントは推理の 1 歩として × を置く（印付き・消せない）。無料ぶん 3 回で尽き、広告は呼ばない")
    func hints() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), puzzle: sample)
        let hint = model.nextHint
        // 手つかずの見本: 部屋 2・3 の猫は 3・4 行目にしかいない → 3 行目の部屋 1 のマス（11）は ×。答えの猫は置かない。
        #expect(hint?.placed == nil && hint?.crossed == [11])
        model.useHint()
        #expect(model.lastHint == hint)
        #expect(model.marks[11] == .cross)
        #expect(model.hintCrosses == [11] && model.hintCells.isEmpty)
        #expect(model.hintsRemaining == 2)
        #expect(model.canHint, "次のヒントもすぐ押せる")
        // ヒントの × はタップしても変わらず、「戻す」でも残る。
        model.tap(cell: 11)
        #expect(model.marks[11] == .cross)
        #expect(!model.canUndo, "ヒントは戻せない")
        model.tap(cell: 0)
        #expect(model.lastHint == nil, "次の操作でヒントの一言は消える")
        model.undo()
        #expect(model.marks[11] == .cross)
        model.useHint()
        model.useHint()
        #expect(model.hintsRemaining == 0)
        #expect(model.hintCrosses.count + model.hintCells.count >= 3)
        #expect(!model.canHint, "無料ぶんを使い切った")
        #expect(spy.events.filter { if case .rewardOffer = $0 { return true } else { return false } }.isEmpty, "広告は呼ばない")
    }

    @Test("ヒントで最後の猫が確定したらそのままクリア")
    func hintCanFinish() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        for cell in sample.solutionCells.dropLast() { placeCat(model, at: cell) }
        // 部屋 3 の答え（14）以外の空きマスを全部 × にする → 残る推理は「部屋 3 に入れるのはここだけ」。
        for cell in 0..<16 where model.marks[cell] == .empty && cell != 14 { model.tap(cell: cell) }
        #expect(model.canHint)
        #expect(model.nextHint?.placed == 14)
        model.useHint()
        #expect(model.isSolved)
        #expect(!model.canHint)
        #expect(model.hintsUsed == 1)
    }

    @Test("赤い × はヒントの推理の前提になる（もう × なので触らず、答えの猫も教えすぎない）")
    func hintTrustsRedCross() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        // 部屋 2（左下）の答えは 8。隣の 12 に置こうとすると赤い ×。
        placeCat(model, at: 12)
        #expect(model.wrongCrosses == [12])
        let hint = model.nextHint
        #expect(hint != nil)
        #expect(hint?.removed.isEmpty == true && hint?.crossed.contains(12) == false)
        model.useHint()
        #expect(model.marks[12] == .cross && model.wrongCrosses == [12])
        #expect(!model.hintCrosses.contains(12))
    }

    @Test("入れるマスが 1 つだけになった部屋には、ヒントが猫を置く（印付き・消せない）")
    func hintPlacesOnlyCell() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        for cell in [0, 4, 9, 10, 11, 12, 13] { model.tap(cell: cell) }
        #expect(model.nextHint == CatPuzzleHint(reason: .onlyCell(group: .room(2), cell: 8), placed: 8, highlights: [.room(2)]))
        model.useHint()
        #expect(model.marks[8] == .cat && model.hintCells == [8])
        model.tap(cell: 8)
        #expect(model.marks[8] == .cat, "ヒントの猫は消せない")
        // 部屋 2 に正しい猫がある → 次のヒントは部屋 2 を指さない。
        #expect(model.nextHint?.highlights.contains(.room(2)) == false)
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
        #expect(model.clearCardWait == nil, "解ける前はダイアログの待ちが無い")
        placeCat(model, at: sample.solutionCells.last!)
        #expect(model.isSolved)
        #expect(model.marks[sample.solutionCells.last!] == .cat, "最後のマスは猫として残る")
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

    @Test("最後の猫を置いてから 1 拍（clearCardDelay）おいてクリアのダイアログを出す。新規ゲームで閉じる")
    func clearCardIsDelayed() {
        let clock = ManualClock()
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.clockNow = clock.now
        #expect(CatPuzzleModel.clearCardDelay == .milliseconds(800))
        for cell in sample.solutionCells { placeCat(model, at: cell) }
        #expect(model.isSolved)
        #expect(!model.showsClearCard, "置いた瞬間はまだ出さない（最後の猫が出る演出を見せる）")
        #expect(model.clearCardWait == .milliseconds(800))
        model.revealClearCardIfDue()
        #expect(!model.showsClearCard)
        clock.advance(by: .milliseconds(500))
        #expect(model.clearCardWait == .milliseconds(300))
        model.revealClearCardIfDue()
        #expect(!model.showsClearCard, "0.5 秒ではまだ")
        clock.advance(by: .milliseconds(300))
        #expect(model.clearCardWait == .zero)
        model.revealClearCardIfDue()
        #expect(model.showsClearCard, "0.8 秒で出す")
        clock.advance(by: .seconds(5))
        model.revealClearCardIfDue()
        #expect(model.showsClearCard)
        model.newGame()
        #expect(!model.showsClearCard && model.clearCardWait == nil)
    }

    @Test("終局後は遊んでいる間の操作（ヒント・戻す・やり直し）を出さない")
    func noPlayControlsAfterClear() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        placeCat(model, at: 1)
        let playing = CatPuzzleView.playControls(for: model)
        #expect(playing.actions.map(\.id) == ["undo", "hint"])
        #expect(playing.menu.map(\.id) == ["clear"])
        for cell in sample.solutionCells.dropFirst() { placeCat(model, at: cell) }
        #expect(model.isSolved)
        let finished = CatPuzzleView.playControls(for: model)
        #expect(finished.actions.isEmpty && finished.menu.isEmpty)
        #expect(!model.canHint && !model.canUndo && !model.hasProgressToLose)
    }

    @Test("中断データ: 印を付けた盤は保存され、同じ問題・印・ミス・ヒントで復元される")
    func snapshotRoundTrip() {
        let store = MemorySnapshotStore()
        let first = CatPuzzleModel(services: makeServices(store: store), size: .normal, seed: 9)
        #expect(!store.exists(for: CatPuzzleModel.gameID), "手つかずの盤は保存しない")
        // 答えの猫と、その隣で別の部屋にあるマスへの猫（答えでないので赤い ×・ミス 1）。× は関係ないマスに付ける。
        let puzzle = first.puzzle
        let answer = puzzle.solutionCells[0]
        let wrong = (0..<puzzle.cellCount).first {
            CatPuzzleLogic.isAdjacent($0, answer, side: puzzle.side) && puzzle.rooms[$0] != puzzle.rooms[answer]
        }!
        let cross = (0..<puzzle.cellCount).first { ![answer, wrong].contains($0) }!
        first.tap(cell: cross)
        placeCat(first, at: answer)
        placeCat(first, at: wrong)
        first.useHint()
        #expect(store.exists(for: CatPuzzleModel.gameID))

        let spy = SpyAnalyticsService()
        let second = CatPuzzleModel(services: makeServices(store: store, analytics: spy), size: .easy, seed: 1)
        #expect(second.size == .normal, "保存した大きさが優先される")
        #expect(second.puzzle == first.puzzle)
        #expect(second.marks == first.marks)
        #expect(second.mistakes == 1)
        #expect(second.hintsUsed == 1)
        #expect(second.hintCells == first.hintCells)
        #expect(second.hintCrosses == first.hintCrosses)
        #expect(second.wrongCrosses == [wrong] && first.wrongCrosses == [wrong])
        second.tap(cell: wrong)
        #expect(second.marks[wrong] == .cross, "再開後も赤い × は消せない")
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
        #expect(model.mistakes == 0 && model.hintsUsed == 0 && model.elapsedSeconds == 0 && model.lastHint == nil)
        #expect(model.hintCells.isEmpty && model.hintCrosses.isEmpty && model.wrongCrosses.isEmpty)
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
