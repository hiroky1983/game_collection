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

/// マスで猫を見つける（ダブルタップ）。
@MainActor
private func placeCat(_ model: CatPuzzleModel, at cell: Int) {
    model.findCat(cell: cell)
}

@Suite("おじさんちのねこさがしの Model")
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

    @Test("シングルタップは × の付け外し（ミスにならない）。猫のいるマスは変わらない")
    func toggleCross() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.toggleCross(cell: 3)
        #expect(model.marks[3] == .cross)
        model.toggleCross(cell: 3)
        #expect(model.marks[3] == .empty, "× を外して空に戻せる（会長 QA 2026-10-22・build 45）")
        #expect(model.mistakes == 0 && model.wrongCrosses.isEmpty, "答えでないマスでも付け外しはミスにならない")
        #expect(model.moves == 2)
        #expect(!model.hasProgressToLose, "印が無くなった盤は捨ててよい")
        placeCat(model, at: 1)
        #expect(model.marks[1] == .cat && model.remainingCats == 3)
        #expect(!model.toggleCross(cell: 1))
        #expect(model.marks[1] == .cat, "猫のいるマスはタップしても変わらない")
        model.findCat(cell: 1)
        #expect(model.marks[1] == .cat && model.mistakes == 0, "猫のいるマスをダブルタップしても何も起きない")
    }

    @Test("ダブルタップは空でも × でも猫を見つける。答えなら猫、答えでなければ赤い ×（ミス）")
    func findCatFromEmptyOrCross() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        placeCat(model, at: 1)
        #expect(model.marks[1] == .cat && model.mistakes == 0)
        model.toggleCross(cell: 7)   // 7 は答え（2 行目の答えは列 3）
        model.findCat(cell: 7)
        #expect(model.marks[7] == .cat, "× のマスでも猫を見つけられる")
        model.toggleCross(cell: 0)
        model.findCat(cell: 0)
        #expect(model.marks[0] == .cross && model.wrongCrosses == [0] && model.mistakes == 1)
        model.toggleCross(cell: 0)
        model.findCat(cell: 0)
        #expect(model.marks[0] == .cross && model.mistakes == 1, "赤い × は付け外しも猫を見つけるもできない")
    }

    @Test("入力経路: 1 回目はすぐ × を付け、同じマスへの 0.3 秒以内の 2 回目で 1 回目を取り消して猫を見つける")
    func tapInputPathDoubleTap() {
        let clock = ManualClock()
        let store = MemorySnapshotStore()
        let model = CatPuzzleModel(services: makeServices(store: store), puzzle: sample)
        model.clockNow = clock.now
        #expect(CatPuzzleModel.doubleTapInterval == .milliseconds(300))
        // 1 回目: 待たずにすぐ × が付く（単タップを遅らせない）。
        model.tap(cell: 1)
        #expect(model.marks[1] == .cross && model.moves == 1 && model.canUndo)
        // 2 回目（0.25 秒後・同じマス）: ダブルタップ。答えのマスなので猫。
        clock.advance(by: .milliseconds(250))
        model.tap(cell: 1)
        #expect(model.marks[1] == .cat && model.mistakes == 0)
        #expect(model.moves == 1, "1 回目の付け外しは手数に残らない")
        model.undo()
        #expect(model.marks[1] == .empty, "戻すは猫の前（空）に戻る。1 回目の × は履歴に残らない")
        #expect(!model.canUndo)

        // 答えでないマス（0）へのダブルタップ: 赤い × が 1 つ、ミス 1。戻すの履歴には何も積まない。
        clock.advance(by: .seconds(1))
        model.tap(cell: 0)
        clock.advance(by: .milliseconds(300))
        model.tap(cell: 0)
        #expect(model.marks[0] == .cross && model.wrongCrosses == [0] && model.mistakes == 1)
        #expect(!model.canUndo, "1 回目の × も赤い × も戻すの対象にならない")
        let saved = store.load(CatPuzzleSnapshot.self, for: CatPuzzleModel.gameID)
        #expect(saved?.wrongCrosses == [0] && saved?.mistakes == 1)

        // × のマスへのダブルタップ: 1 回目で × が外れ、2 回目で × に戻してから猫を見つける。
        clock.advance(by: .seconds(1))
        model.tap(cell: 7)
        #expect(model.marks[7] == .cross)
        clock.advance(by: .seconds(1))
        model.tap(cell: 7)
        #expect(model.marks[7] == .empty, "間が空いた 2 回目は単タップ（× を外す）")
        clock.advance(by: .seconds(1))
        model.toggleCross(cell: 7)
        let movesBefore = model.moves
        model.tap(cell: 7)
        #expect(model.marks[7] == .empty)
        clock.advance(by: .milliseconds(100))
        model.tap(cell: 7)
        #expect(model.marks[7] == .cat && model.moves == movesBefore + 1)
        model.undo()
        #expect(model.marks[7] == .cross, "戻すと × のマスに戻る（1 回目の × 外しは残らない）")
    }

    @Test("入力経路: 間隔が 0.3 秒を超えた・別のマス・3 回目は単タップとして扱う")
    func tapInputPathSingleTaps() {
        let clock = ManualClock()
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.clockNow = clock.now
        // 0.3 秒を超えた 2 回目は単タップ: × を外す。
        model.tap(cell: 3)
        clock.advance(by: .milliseconds(301))
        model.tap(cell: 3)
        #expect(model.marks[3] == .empty && model.mistakes == 0)
        // 別のマスへの続けてのタップは、それぞれ単タップ。
        model.tap(cell: 2)
        model.tap(cell: 3)
        #expect(model.marks[2] == .cross && model.marks[3] == .cross && model.mistakes == 0)
        // 間に別のマスを挟んだら、元のマスへ戻ってもダブルタップにならない。
        model.tap(cell: 2)
        #expect(model.marks[2] == .empty)
        // ダブルタップ（猫を見つけた）の後の 3 回目は新しい 1 回目。猫のマスなので何も起きない。
        model.tap(cell: 1)
        model.tap(cell: 1)
        #expect(model.marks[1] == .cat)
        model.tap(cell: 1)
        #expect(model.marks[1] == .cat && model.mistakes == 0)
        // 赤い × のマスへのダブルタップは何も起きない（ミスも増えない）。
        clock.advance(by: .seconds(1))
        model.tap(cell: 0); model.tap(cell: 0)
        #expect(model.wrongCrosses == [0] && model.mistakes == 1)
        clock.advance(by: .seconds(1))
        model.tap(cell: 0)
        model.tap(cell: 0)
        #expect(model.marks[0] == .cross && model.mistakes == 1)
        // 1 回目の後に「戻す」を挟んだら、2 回目はダブルタップにしない。
        clock.advance(by: .seconds(1))
        model.tap(cell: 5)
        model.undo()
        model.tap(cell: 5)
        #expect(model.marks[5] == .cross && model.mistakes == 1)
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
        model.toggleCross(cell: 3)
        model.toggleCross(cell: 3)
        #expect(model.marks[3] == .cross && model.mistakes == 1)
        // 次の操作で直近の印（揺れ・赤枠）は消えるが、赤い × は残る。
        model.toggleCross(cell: 2)
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
        model.toggleCross(cell: 2)
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
        model.toggleCross(cell: 5)
        model.reset()
        #expect(model.marks.indices.allSatisfy { model.marks[$0] == (hintCrosses.union([3]).contains($0) ? .cross : .empty) }, "ヒントの印と赤い × だけ残る")
        #expect(model.hintCrosses == hintCrosses)
        #expect(model.lastHint == nil)
        #expect(model.hintsUsed == 1, "ヒントの回数は引き継ぐ")
        #expect(model.mistakes == 1, "ミスは引き継ぐ")
        #expect(!model.canUndo)
        #expect(store.exists(for: CatPuzzleModel.gameID), "ヒントの印がある盤は保存する")
    }

    @Test("ヒントは推理の 1 歩として × を置く（印付き・消せない）。無料ぶん 1 回のあとは広告が要る")
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
        #expect(model.hintsRemaining == 0, "無料は 1 局 1 回（#3048）")
        #expect(model.canHint, "無料を使い切っても広告で足せるので押せる")
        // ヒントの × はタップしても変わらず、「戻す」でも残る。
        model.toggleCross(cell: 11)
        #expect(model.marks[11] == .cross)
        #expect(!model.canUndo, "ヒントは戻せない")
        model.toggleCross(cell: 0)
        #expect(model.lastHint == nil, "次の操作でヒントの一言は消える")
        model.undo()
        #expect(model.marks[11] == .cross)
        // 無料ぶんを使い切ったら、押せるが次の 1 回は広告（`useHint` だけでは減らず、盤も進まない）。
        #expect(model.needsAdForHint && model.canHint, "無料ぶんを使い切っても広告で足せる")
        let marksBefore = model.marks
        model.useHint()
        #expect(model.hintsUsed == 1 && model.marks == marksBefore, "広告を見ずに 2 回目は出ない")
        #expect(spy.events.filter {
            switch $0 {
            case .rewardOffer, .rewardRequest, .rewardAd: true
            default: false
            }
        }.isEmpty, "無料のヒントは広告を呼ばない")
    }

    @Test("ヒントで最後の猫が確定したらそのままクリア")
    func hintCanFinish() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        for cell in sample.solutionCells.dropLast() { placeCat(model, at: cell) }
        // 部屋 3 の答え（14）以外の空きマスを全部 × にする → 残る推理は「部屋 3 に入れるのはここだけ」。
        for cell in 0..<16 where model.marks[cell] == .empty && cell != 14 { model.toggleCross(cell: cell) }
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
        for cell in [0, 4, 9, 10, 11, 12, 13] { model.toggleCross(cell: cell) }
        #expect(model.nextHint == CatPuzzleHint(reason: .onlyCell(group: .room(2), cell: 8), placed: 8, highlights: [.room(2)]))
        model.useHint()
        #expect(model.marks[8] == .cat && model.hintCells == [8])
        model.toggleCross(cell: 8)
        #expect(model.marks[8] == .cat, "ヒントの猫は消せない")
        // 部屋 2 に正しい猫がある → 次のヒントは部屋 2 を指さない。
        #expect(model.nextHint?.highlights.contains(.room(2)) == false)
    }

    @Test("ステージのクリアは「ステージ」の区分に記録し、自由に遊ぶの大きさ別ベストは変わらない（#3145）")
    func stageClearDoesNotTouchFreePlayBest() throws {
        let log = makeLog("stageSplit")
        let defaults = UserDefaults(suiteName: "asobiba.catpuzzle.tests.stageSplit.progress")!
        defaults.removePersistentDomain(forName: "asobiba.catpuzzle.tests.stageSplit.progress")
        let clock = ManualClock()
        // 先に自由に遊ぶ（かんたん）で 65 秒の記録を作る。
        let free = CatPuzzleModel(services: makeServices(log: log), puzzle: sample, size: .easy)
        free.clockNow = clock.now
        for cell in sample.solutionCells.dropLast() { placeCat(free, at: cell) }
        clock.advance(by: .seconds(65))
        free.syncElapsed()
        placeCat(free, at: sample.solutionCells.last!)
        #expect(log.record(gameID: CatPuzzleModel.gameID, variant: "easy")?.bestSeconds == 65)
        // ステージ（かんたんの盤）を 10 秒でクリアしても、かんたんのベストは 65 のまま。
        let stage = CatPuzzleModel(
            services: makeServices(log: log), puzzle: sample, size: .easy, stage: 1, stageDefaults: defaults
        )
        let stageClock = ManualClock()
        stage.clockNow = stageClock.now
        for cell in sample.solutionCells.dropLast() { placeCat(stage, at: cell) }
        stageClock.advance(by: .seconds(10))
        stage.syncElapsed()
        placeCat(stage, at: sample.solutionCells.last!)
        #expect(stage.isSolved)
        #expect(log.record(gameID: CatPuzzleModel.gameID, variant: "easy")?.bestSeconds == 65)
        let stageRecord = try #require(log.record(gameID: CatPuzzleModel.gameID, variant: "stage"))
        #expect(stageRecord.wins == 1 && stageRecord.variantLabel == "ステージ")
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
        model.toggleCross(cell: 0)
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
        first.toggleCross(cell: cross)
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
        second.toggleCross(cell: wrong)
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

    @Test("計時は盤が出た時点（タップ前）から進み、シート・離脱で止まり、戻ると再開する")
    func timerStartsWhenBoardIsShown() {
        let clock = ManualClock()
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample)
        model.clockNow = clock.now
        // 画面が盤を出したとき（`.task` / 開始シートを閉じたとき）に呼ぶ入口。1 手も打っていなくても進む。
        model.resumeTimerIfNeeded()
        #expect(model.isCounting)
        clock.advance(by: .seconds(10))
        model.syncElapsed()
        #expect(model.elapsedSeconds == 10, "眺めて考えている時間も数える")
        // 開始シート・確認・遊び方を出している間（`gameTimerLifecycle` が pause を呼ぶ）。
        model.pauseTimer()
        #expect(!model.isCounting)
        clock.advance(by: .seconds(30))
        model.resumeTimerIfNeeded()
        clock.advance(by: .seconds(5))
        model.syncElapsed()
        #expect(model.elapsedSeconds == 15, "止めていたあいだは数えない")
    }

    @Test("開始シート・確認を出している間は計時を止める（画面の判定）")
    func clockIsHeldWhileSheetsAreOpen() {
        #expect(!CatPuzzleView.holdsClock(showNewGame: false, showConfirmNewGame: false, showConfirmClear: false))
        #expect(CatPuzzleView.holdsClock(showNewGame: true, showConfirmNewGame: false, showConfirmClear: false))
        #expect(CatPuzzleView.holdsClock(showNewGame: false, showConfirmNewGame: true, showConfirmClear: false))
        #expect(CatPuzzleView.holdsClock(showNewGame: false, showConfirmNewGame: false, showConfirmClear: true))
    }

    @Test("新しい問題が出た瞬間から計時し、記録の最短タイムもこの計時")
    func newGameStartsClockImmediately() {
        let clock = ManualClock()
        let log = makeLog("clock")
        let model = CatPuzzleModel(services: makeServices(log: log), puzzle: sample, size: .easy)
        model.clockNow = clock.now
        model.newGame()
        #expect(model.isCounting, "開始シートで選んだ直後・もう一回の直後から動く")
        // 問題を差し替えた盤を解くのは手間なので、見本の盤を使う別の局で記録を確かめる。
        let solving = CatPuzzleModel(services: makeServices(log: log), puzzle: sample, size: .easy)
        solving.clockNow = clock.now
        solving.resumeTimerIfNeeded()
        clock.advance(by: .seconds(40))
        for cell in sample.solutionCells { placeCat(solving, at: cell) }
        #expect(solving.isSolved && solving.elapsedSeconds == 40, "最初のタップより前の 40 秒も含む")
        #expect(log.record(gameID: CatPuzzleModel.gameID, variant: "easy")?.bestSeconds == 40)
    }

    @Test("中断データからの再開は経過時間を引き継いで、そこから進む")
    func resumedGameKeepsElapsedTime() {
        let store = MemorySnapshotStore()
        let clock = ManualClock()
        let first = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 3)
        first.clockNow = clock.now
        first.resumeTimerIfNeeded()
        first.toggleCross(cell: first.puzzle.solutionCells[0] == 0 ? 1 : 0)
        clock.advance(by: .seconds(25))
        first.pauseTimer()
        let second = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 9)
        #expect(second.elapsedSeconds == 25)
        #expect(!CatPuzzleView.startsWithNewGameSheet(second), "続きの盤があれば開始シートを出さない")
        second.clockNow = clock.now
        second.resumeTimerIfNeeded()
        clock.advance(by: .seconds(5))
        second.syncElapsed()
        #expect(second.elapsedSeconds == 30)
    }

    @Test("ミス 2 回までは続き、3 回目で終局（負け）。記録・解析は負けで、中断データは消える")
    func threeMistakesLose() throws {
        let store = MemorySnapshotStore()
        let spy = SpyAnalyticsService()
        let log = makeLog("lose")
        let feedback = SpyFeedbackService()
        let model = CatPuzzleModel(services: makeServices(store: store, log: log, analytics: spy, feedback: feedback),
                                   puzzle: sample, size: .easy)
        #expect(CatPuzzleModel.maxMistakes == 3)
        let wrongs = (0..<sample.cellCount).filter { !sample.solutionCells.contains($0) }
        placeCat(model, at: wrongs[0])
        placeCat(model, at: wrongs[1])
        #expect(model.mistakes == 2 && model.mistakesRemaining == 1)
        #expect(!model.isFailed && !model.isOver, "2 回目まではまだ続く")
        #expect(model.hasProgressToLose && store.exists(for: CatPuzzleModel.gameID))
        model.toggleCross(cell: sample.solutionCells[0])
        #expect(model.marks[sample.solutionCells[0]] == .cross, "2 回目のあとも打てる")
        placeCat(model, at: wrongs[2])
        #expect(model.mistakes == 3 && model.mistakesRemaining == 0)
        // 3 回目のミスでは、まず広告を見て続ける提案。負けはこの時点で記録し、断っても二重には付けない（#2780・#3144）。
        #expect(model.isOfferingContinue && !model.isFailed && !model.isCounting)
        #expect(spy.ends(of: CatPuzzleModel.gameID) == 1 && model.unfoundCats.isEmpty)
        model.declineContinue()
        #expect(!model.isOfferingContinue)
        #expect(model.isFailed && model.isOver && !model.isSolved)
        #expect(model.wrongCrosses.count == 3 && model.lastWrongCell == wrongs[2], "3 回目の赤い × も盤に残す")
        #expect(!model.isCounting)
        #expect(!store.exists(for: CatPuzzleModel.gameID), "終局した盤は続きにしない")
        #expect(spy.ends(of: CatPuzzleModel.gameID) == 1)
        #expect(spy.outcomes == [.loss])
        #expect(spy.quits(of: CatPuzzleModel.gameID) == 0)
        let record = try #require(log.record(gameID: CatPuzzleModel.gameID, variant: "easy"))
        #expect(record.losses == 1 && record.wins == 0 && record.bestSeconds == nil, "負けは最短タイムに数えない")
        #expect(model.recordResult != nil)
        // 終局後は触れない・ヒントも戻すも出さない。
        model.toggleCross(cell: sample.solutionCells[1])
        #expect(model.marks[sample.solutionCells[1]] == .empty)
        #expect(!model.canHint && !model.canUndo && !model.hasProgressToLose)
        let controls = CatPuzzleView.playControls(for: model)
        #expect(controls.actions.isEmpty && controls.menu.isEmpty)
        model.resumeTimerIfNeeded()
        #expect(!model.isCounting, "終局後は計時しない")
        // もう一回で負けが解け、ミスも 0 に戻る。前の局は決着済みなので quit は出ない。
        model.newGame()
        #expect(!model.isFailed && model.mistakes == 0 && model.mistakesRemaining == 3)
        #expect(spy.quits(of: CatPuzzleModel.gameID) == 0)
    }

    @Test("ミスの回数は中断データに残り、再開後の 3 回目で負けになる。上限に届いた古い中断データは捨てる")
    func mistakesSurviveResume() throws {
        let store = MemorySnapshotStore()
        let first = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 4)
        let puzzle = first.puzzle
        let wrongs = (0..<puzzle.cellCount).filter { !puzzle.solutionCells.contains($0) }
        placeCat(first, at: wrongs[0])
        placeCat(first, at: wrongs[1])
        let log = makeLog("resume-lose")
        let second = CatPuzzleModel(services: makeServices(store: store, log: log), size: .easy, seed: 9)
        #expect(second.mistakes == 2 && second.mistakesRemaining == 1)
        placeCat(second, at: wrongs[2])
        second.declineContinue()
        #expect(second.isFailed)
        #expect(log.record(gameID: CatPuzzleModel.gameID, variant: "easy")?.losses == 1)

        // ミス 3 回で負けの決まりより前（build 43 まで）の中断データでミスが 3 以上のもの。
        var marks = Array(repeating: CatPuzzleModel.Mark.empty.rawValue, count: puzzle.cellCount)
        for cell in wrongs.prefix(4) { marks[cell] = CatPuzzleModel.Mark.cross.rawValue }
        let old = CatPuzzleSnapshot(size: "easy", puzzle: puzzle, marks: marks, elapsedSeconds: 30, mistakes: 4,
                                    hintsUsed: 0, wrongCrosses: Array(wrongs.prefix(4)))
        #expect(CatPuzzleSnapshot.isWellFormed(old))
        #expect(!CatPuzzleSnapshot.isResumable(old), "上限に届いた盤は終局済み")
        let oldStore = MemorySnapshotStore()
        try oldStore.save(old, for: CatPuzzleModel.gameID)
        let fresh = CatPuzzleModel(services: makeServices(store: oldStore), size: .easy, seed: 2)
        #expect(fresh.mistakes == 0 && fresh.marks.allSatisfy { $0 == .empty }, "捨てて新しい問題で始める")
    }

    @Test("＋: 印が無ければ確認なしで開始シート。途中なら確認を挟み、やめて始めた局は途中離脱（quit）に数える")
    func newGameFromPlusCountsQuit() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), size: .easy, seed: 6, defersStart: true)
        #expect(CatPuzzleView.startsWithNewGameSheet(model), "続きが無ければ最初に開始シートで難易度を選ぶ")
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 0, "開始シートで選ぶまで game_start は遅らせる")
        // 開いただけの盤で開始シートから始めても、離脱には数えない。開始は選んだ難易度の 1 回だけ。
        #expect(!model.hasProgressToLose, "確認なしで開始シートを出す")
        model.newGame(size: .normal)
        #expect(spy.quits(of: CatPuzzleModel.gameID) == 0)
        #expect(spy.startLevels == [.normal])
        model.startPlayIfPending()
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 1, "シートで始めた局に遅らせた開始を足さない")
        // 1 手打った局は確認を挟む（`hasProgressToLose`）。開始シートで始めた時点で quit。
        model.toggleCross(cell: 0)
        #expect(model.hasProgressToLose, "途中なので確認を出す")
        model.newGame(size: .hard)
        #expect(spy.quits(of: CatPuzzleModel.gameID) == 1)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 2)
    }

    @Test("開始シートを閉じて今の盤で遊ぶときは、遅らせた game_start を 1 回だけ数える")
    func cancelledSheetStartsOnce() {
        let spy = SpyAnalyticsService()
        let model = CatPuzzleModel(services: makeServices(analytics: spy), size: .hard, seed: 6, defersStart: true)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 0)
        model.startPlayIfPending()
        model.startPlayIfPending()
        model.toggleCross(cell: 0)
        #expect(spy.starts(of: CatPuzzleModel.gameID) == 1)
        #expect(spy.startLevels == [.hard])
        // 閉じる経路を通らずに最初の操作をしても 1 回。
        let other = SpyAnalyticsService()
        let direct = CatPuzzleModel(services: makeServices(analytics: other), size: .easy, seed: 7, defersStart: true)
        direct.toggleCross(cell: 0)
        direct.toggleCross(cell: 1)
        #expect(other.starts(of: CatPuzzleModel.gameID) == 1)
    }

    // MARK: - 負けたあとの答え合わせ・コンティニュー（#2780）

    /// 3 回目のミスまで進めた盤（見本の問題・答えの 1 匹目だけ見つけてある）。
    private func atThirdMistake(
        store: MemorySnapshotStore = MemorySnapshotStore(), spy: SpyAnalyticsService? = nil, log: PlayLog? = nil
    ) -> (CatPuzzleModel, wrongs: [Int]) {
        let model = CatPuzzleModel(services: makeServices(store: store, log: log, analytics: spy), puzzle: sample, size: .easy)
        let wrongs = (0..<sample.cellCount).filter { !sample.solutionCells.contains($0) }
        placeCat(model, at: sample.solutionCells[0])
        for cell in wrongs.prefix(3) { placeCat(model, at: cell) }
        return (model, wrongs)
    }

    @Test("負けを確定すると、まだ見つけていない猫がすべて正解の場所に出る（自分で見つけた猫は含めない）")
    func lossRevealsEveryUnfoundCat() {
        let (model, wrongs) = atThirdMistake()
        #expect(model.unfoundCats.isEmpty, "提案の最中はまだ見せない")
        model.declineContinue()
        #expect(model.isFailed)
        #expect(model.unfoundCats == Array(sample.solutionCells.dropFirst()).sorted())
        #expect(model.unfoundCats.count == sample.side - 1)
        #expect(model.isUnfoundCat(cell: sample.solutionCells[1]) && !model.isUnfoundCat(cell: sample.solutionCells[0]))
        // 自分が置いた猫・赤い × はそのまま残る。
        #expect(model.marks[sample.solutionCells[0]] == .cat)
        #expect(wrongs.prefix(3).allSatisfy { model.marks[$0] == .cross && model.wrongCrosses.contains($0) })
        // 新しい局では出さない。
        model.newGame()
        #expect(model.unfoundCats.isEmpty)
    }

    @Test("ヒントで置いた猫・自分で × を付けた答えのマスの扱い: 猫の印が無い答えのマスだけが出る")
    func revealSkipsPlacedCatsOnly() {
        let model = CatPuzzleModel(services: makeServices(), puzzle: sample, size: .easy)
        model.toggleCross(cell: sample.solutionCells[1])
        let wrongs = (0..<sample.cellCount).filter { !sample.solutionCells.contains($0) }
        for cell in wrongs.prefix(3) { placeCat(model, at: cell) }
        model.declineContinue()
        #expect(model.unfoundCats.count == sample.side, "答えのマスに × を付けていても、猫はそこにいた")
        #expect(model.unfoundCats.contains(sample.solutionCells[1]))
    }

    @Test("コンティニュー: 広告のあとミスが 1 回ぶん戻り、赤い × は残る。計時が再開し、提案時に付けた負けは取り消される")
    func continueAfterAd() {
        let store = MemorySnapshotStore()
        let spy = SpyAnalyticsService()
        let (model, wrongs) = atThirdMistake(store: store, spy: spy)
        #expect(model.isOfferingContinue && !model.continueUsed)
        #expect(store.exists(for: CatPuzzleModel.gameID), "提案の最中も続きは残る")
        // 提案の最中は盤に触れない・ヒントも戻すも使えない。
        model.toggleCross(cell: sample.solutionCells[2])
        placeCat(model, at: sample.solutionCells[2])
        #expect(model.marks[sample.solutionCells[2]] == .empty && !model.canHint && !model.canUndo)
        model.resumeTimerIfNeeded()
        #expect(!model.isCounting)
        let serial = model.gameSerial
        #expect(!model.continueAfterAd(forGame: serial + 1), "別の局への報酬は乗せない")
        #expect(model.continueAfterAd(forGame: serial))
        #expect(!model.isOfferingContinue && !model.isFailed && model.continueUsed)
        #expect(model.mistakes == CatPuzzleModel.maxMistakes - 1 && model.mistakesRemaining == 1)
        #expect(model.wrongCrosses == Set(wrongs.prefix(3)), "最後の赤い × は盤に残る")
        #expect(model.isCounting)
        #expect(!model.continueAfterAd(), "提案が出ていないときは使えない")
        // 続けて遊べる。
        placeCat(model, at: sample.solutionCells[1])
        #expect(model.marks[sample.solutionCells[1]] == .cat)
    }

    @Test("提案を放置して新規で捨てても、負けが 1 つ付く（#3144）")
    func abandoningOfferRecordsLoss() {
        let log = makeLog("abandonOffer")
        let (model, _) = atThirdMistake(log: log)
        #expect(model.isOfferingContinue)
        model.newGame()
        #expect(log.record(gameID: CatPuzzleModel.gameID, variant: CatPuzzleSize.easy.recordVariant)?.losses == 1)
    }

    @Test("コンティニューで提案時の負けは取り消され、断っても二重には付かない（#3144）")
    func continueCancelsLossAndDeclineDoesNotDouble() {
        let log = makeLog("continueCancel")
        let (continued, _) = atThirdMistake(log: log)
        #expect(continued.continueAfterAd())
        #expect((log.record(gameID: CatPuzzleModel.gameID, variant: CatPuzzleSize.easy.recordVariant)?.losses ?? 0) == 0)
        #expect(continued.recordResult == nil)

        let declineLog = makeLog("decline")
        let (declined, _) = atThirdMistake(log: declineLog)
        declined.declineContinue()
        #expect(declineLog.record(gameID: CatPuzzleModel.gameID, variant: CatPuzzleSize.easy.recordVariant)?.losses == 1)
        #expect(declined.recordResult != nil)
    }

    @Test("コンティニューは 1 局 1 回。使ったあとの 3 回目のミスはそのまま負け、新しい局で使える")
    func continueOncePerGame() {
        let spy = SpyAnalyticsService()
        let (model, wrongs) = atThirdMistake(spy: spy)
        #expect(model.continueAfterAd())
        placeCat(model, at: wrongs[3])
        #expect(model.mistakes == 3 && model.isFailed && !model.isOfferingContinue, "2 回目の提案はしない")
        #expect(spy.ends(of: CatPuzzleModel.gameID) == 1 && spy.outcomes == [.loss])
        model.newGame()
        #expect(!model.continueUsed && !model.isFailed)
    }

    /// ミス 3 回のダイアログが 1 回しか出ないことの再発防止（会長 QA・#2904）。
    ///
    /// 「広告で続ける提案」（`isOfferingContinue`）と「負け」（`isFailed`）が同時に真になることは無いのを、
    /// 「あきらめる」「広告でコンティニュー」どちらの道でも確かめる。画面のカードの出し方は `failCardShowsOnce`。
    @Test("ミス 3 回の提案と負けの結果は、同時に真にならない（あきらめる／コンティニューのどちらでも）")
    func offerAndFailedAreMutuallyExclusive() {
        // あきらめる道: 提案 → あきらめで負け確定。それ以降、提案が生き返ることはない。
        let (declined, _) = atThirdMistake()
        #expect(declined.isOfferingContinue && !declined.isFailed, "提案は 1 回だけ")
        declined.declineContinue()
        #expect(!declined.isOfferingContinue && declined.isFailed, "あきらめたら提案は消え、負けだけが残る")
        #expect(!(declined.isOfferingContinue && declined.isFailed), "提案と負けの結果が同時に真にならない")
        // 負けたあとに盤へ触れても、提案は戻らない（終局後は `isFrozen` が弾く）。
        declined.toggleCross(cell: declined.puzzle.solutionCells[0])
        #expect(!declined.isOfferingContinue)

        // コンティニューの道: 提案 → 広告で続行 → もう一度ミス 3 回目で今度こそ負け（2 回目の提案はしない）。
        let (granted, wrongs) = atThirdMistake()
        #expect(granted.continueAfterAd())
        #expect(!granted.isOfferingContinue && !granted.isFailed)
        placeCat(granted, at: wrongs[3])
        #expect(!granted.isOfferingContinue && granted.isFailed, "2 回目の負けは提案を挟まず直接負けになる")
        #expect(!(granted.isOfferingContinue && granted.isFailed), "提案と負けの結果が同時に真にならない")
    }

    /// 会長 QA build 53: 提案（1 枚目）→ あきらめる → 負けの結果カード（2 枚目）と、順に 2 回出ていた（#2904）。
    /// カードは提案のときの 1 枚だけで、あきらめたあとは重ねない。コンティニュー済みの負けは 1 回だけ出して閉じられる。
    @Test("ミス 3 回のダイアログは、あきらめる／コンティニューのどちらでも 1 回だけ")
    func failCardShowsOnce() {
        // あきらめる道: 3 回目で 1 枚 → あきらめたら消え、盤に正解を出すだけ。
        let (declined, _) = atThirdMistake()
        #expect(CatPuzzleView.showsFailCard(declined, closed: false), "3 回目で 1 枚目を出す")
        declined.declineContinue()
        #expect(!CatPuzzleView.showsFailCard(declined, closed: false), "あきらめたあとに 2 枚目を重ねない")

        // コンティニューの道: 3 回目で 1 枚 → 広告で続けたら消える → 次の 3 回目は負けのカードを 1 回だけ。
        let (granted, wrongs) = atThirdMistake()
        #expect(CatPuzzleView.showsFailCard(granted, closed: false))
        #expect(granted.continueAfterAd())
        #expect(!CatPuzzleView.showsFailCard(granted, closed: false), "続けたら消える")
        placeCat(granted, at: wrongs[3])
        #expect(CatPuzzleView.showsFailCard(granted, closed: false), "コンティニュー済みの負けは 1 回出す")
        #expect(!CatPuzzleView.showsFailCard(granted, closed: true), "閉じたらもう出さない")
    }

    @Test("答えを見たあとはコンティニューできない")
    func noContinueAfterReveal() {
        let (model, _) = atThirdMistake()
        model.declineContinue()
        let serial = model.gameSerial
        #expect(!model.continueAfterAd(forGame: serial))
        #expect(model.isFailed && model.mistakes == 3)
    }

    @Test("提案の最中に離れても、開き直すと同じ提案から続く。使用済みなら上限の保存は残らない")
    func offerSurvivesResume() throws {
        let store = MemorySnapshotStore()
        let first = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 4)
        let puzzle = first.puzzle
        let wrongs = (0..<puzzle.cellCount).filter { !puzzle.solutionCells.contains($0) }
        for cell in wrongs.prefix(3) { placeCat(first, at: cell) }
        #expect(first.isOfferingContinue)
        let snap = try #require(store.load(CatPuzzleSnapshot.self, for: CatPuzzleModel.gameID))
        #expect(snap.mistakes == 3 && CatPuzzleSnapshot.isResumable(snap))
        let resumed = CatPuzzleModel(services: makeServices(store: store), size: .easy, seed: 3)
        #expect(resumed.isOfferingContinue && resumed.mistakes == 3 && !resumed.isFailed)
        resumed.resumeTimerIfNeeded()
        #expect(!resumed.isCounting)
        #expect(resumed.continueAfterAd())
        #expect(resumed.continueUsed && resumed.mistakes == 2)
        // 使用済みであることも保存される。使用済みで上限の保存は終局済み（残さない）。
        let saved = try #require(store.load(CatPuzzleSnapshot.self, for: CatPuzzleModel.gameID))
        #expect(saved.continueUsed == true && saved.mistakes == 2)
        var broken = saved
        broken.mistakes = 3
        #expect(!CatPuzzleSnapshot.isResumable(broken))
    }
}

@MainActor
@Suite("盤が縮む新規でも View の読み出しが落ちない（#3141）")
struct CatPuzzleStaleIndexTests {
    @Test("大→小の新規のあと、旧盤面の添字は nil を返す")
    func staleIndexReturnsNil() {
        let model = CatPuzzleModel(services: makeServices(), size: .expert, seed: 1)
        let oldCount = model.puzzle.cellCount
        model.newGame(size: .easy)
        let newCount = model.puzzle.cellCount
        #expect(newCount < oldCount)
        for index in 0..<newCount { #expect(model.cellState(at: index) != nil) }
        for index in newCount..<oldCount { #expect(model.cellState(at: index) == nil) }
        #expect(model.cellState(at: -1) == nil)
    }
}
