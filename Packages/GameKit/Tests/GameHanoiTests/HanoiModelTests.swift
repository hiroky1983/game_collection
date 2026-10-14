import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameHanoi

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [HanoiModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.hanoi.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 最少手順をタップで指す（取る → 置く）。
@MainActor
private func playSolution(_ model: HanoiModel, upTo limit: Int? = nil) {
    let steps = HanoiLogic.solution(disks: model.disks)
    for step in steps.prefix(limit ?? steps.count) {
        model.tap(peg: step.from)
        model.tap(peg: step.to)
    }
}

@Suite("ハノイの塔のモデル")
@MainActor
struct HanoiModelTests {

    @Test("柱をタップで取り、別の柱をタップで置く。同じ柱をもう一度タップすると取り消し")
    func takeAndPlace() {
        let model = HanoiModel(services: makeServices())
        model.tap(peg: 0)
        #expect(model.selectedPeg == 0)
        model.tap(peg: 0)
        #expect(model.selectedPeg == nil, "同じ柱で取り消し")
        #expect(model.moves == 0)

        model.tap(peg: 0)
        model.tap(peg: 2)
        #expect(model.pegs == [[3, 2], [], [1]])
        #expect(model.moves == 1)
        #expect(model.selectedPeg == nil)
    }

    @Test("大きい円盤を小さい円盤の上に置こうとすると断り、理由を出す。取ったままなので選び直せる")
    func rejectsLargerOnSmaller() {
        let feedback = SpyFeedbackService()
        let model = HanoiModel(services: makeServices(feedback: feedback))
        model.tap(peg: 0); model.tap(peg: 2)   // 1 を右へ
        model.tap(peg: 0); model.tap(peg: 2)   // 2 を 1 の上へ → 断る
        #expect(model.rejection == .largerOnSmaller)
        #expect(model.pegs == [[3, 2], [], [1]], "盤は変わらない")
        #expect(model.moves == 1, "断った操作は手数に数えない")
        #expect(model.selectedPeg == 0, "取ったまま")
        #expect(feedback.notices(of: .warning) == 1)
        #expect(HanoiAccessibility.message(for: .largerOnSmaller) == "大きい円盤は、小さい円盤の上には置けません")

        model.tap(peg: 1)
        #expect(model.pegs == [[3], [2], [1]])
        #expect(model.rejection == nil, "動かせたら理由は消える")
    }

    @Test("空の柱は取れず、理由を出す")
    func emptyPegCannotBeTaken() {
        let model = HanoiModel(services: makeServices())
        model.tap(peg: 1)
        #expect(model.selectedPeg == nil)
        #expect(model.rejection == .emptySource)
    }

    @Test("最少手順で解くとクリアし、手数・タイムを枚数ごとの記録に残す。中断データは消える", arguments: [3, 5])
    func solvingRecordsBestMovesAndTime(disks: Int) throws {
        let store = MemorySnapshotStore()
        let log = makeLog("solve\(disks)")
        let clock = ManualClock()
        let model = HanoiModel(services: makeServices(store: store, log: log), disks: disks)
        model.clockNow = clock.now
        playSolution(model, upTo: 1)
        clock.advance(by: .seconds(42))
        playSolution2(model, from: 1)

        #expect(model.isSolved)
        #expect(model.moves == HanoiLogic.minimumMoves(disks: disks))
        #expect(model.elapsedSeconds == 42)
        #expect(!model.isCounting, "クリアしたら計時は止まる")
        #expect(!store.exists(for: HanoiModel.gameID))
        let record = try #require(log.record(gameID: HanoiModel.gameID, variant: "\(disks)disks"))
        #expect(record.metric == .fewestMoves)
        #expect(record.fewestMoves == HanoiLogic.minimumMoves(disks: disks))
        #expect(record.bestSeconds == 42)
        #expect(record.wins == 1)
        #expect(model.recordResult?.update.moves == true)

        // 解いた後の操作は受け付けない。
        model.tap(peg: 2)
        #expect(model.selectedPeg == nil)
    }

    /// 最少手順の `from` 手目以降を指す。
    private func playSolution2(_ model: HanoiModel, from start: Int) {
        for step in HanoiLogic.solution(disks: model.disks).dropFirst(start) {
            model.tap(peg: step.from)
            model.tap(peg: step.to)
        }
    }

    @Test("記録の区分名は枚数（日本語で保存・英語で引き直せる）")
    func variantLabel() {
        #expect(HanoiModel.recordVariant(disks: 5) == "5disks")
        #expect(RecordVariantLabels.stored(gameID: "hanoi", variant: "5disks") == "円盤5枚")
        #expect(RecordVariantLabels.label(recordKey: "hanoi#5disks", language: .english) == "5 Disks")
        #expect(RecordVariantLabels.label(recordKey: "hanoi#xdisks") == nil)
    }

    @Test("手つかずの盤は保存しない。1 手動かすと保存し、開き直すと続きから")
    func untouchedBoardIsNotSaved() throws {
        let store = MemorySnapshotStore()
        let services = makeServices(store: store)
        let first = HanoiModel(services: services, disks: 4)
        #expect(!store.exists(for: HanoiModel.gameID), "開いただけでは保存しない（#1847）")
        #expect(!HanoiModule().hasResumableSnapshot(in: store))
        first.tap(peg: 0)
        #expect(!store.exists(for: HanoiModel.gameID), "取っただけでは保存しない")
        first.tap(peg: 1)
        let snap = try #require(store.load(HanoiSnapshot.self, for: HanoiModel.gameID))
        #expect(snap.moves == 1 && snap.disks == 4)
        #expect(HanoiModule().hasResumableSnapshot(in: store))

        // 枚数の指定より中断データを優先する。
        let resumed = HanoiModel(services: services, disks: 7)
        #expect(resumed.disks == 4)
        #expect(resumed.moves == 1)
        #expect(resumed.pegs == [[4, 3, 2], [1], []])
    }

    @Test("壊れた中断データは捨てて新しく始める")
    func brokenSnapshotIsDiscarded() throws {
        let store = MemorySnapshotStore()
        try store.save(HanoiSnapshot(disks: 3, pegs: [[1, 3], [2], []], moves: 4, elapsedSeconds: 9), for: HanoiModel.gameID)
        let model = HanoiModel(services: makeServices(store: store))
        #expect(model.pegs == HanoiLogic.initial(disks: 3))
        #expect(model.moves == 0)
        #expect(!store.exists(for: HanoiModel.gameID))
    }

    @Test("新規ゲームで枚数を変えられ、範囲外の枚数は無視する。途中の盤は消える")
    func newGameChangesDisks() {
        let store = MemorySnapshotStore()
        let model = HanoiModel(services: makeServices(store: store))
        model.tap(peg: 0); model.tap(peg: 1)
        #expect(model.hasProgressToLose)
        model.newGame(disks: 6)
        #expect(model.disks == 6)
        #expect(model.pegs == HanoiLogic.initial(disks: 6))
        #expect(model.moves == 0 && model.elapsedSeconds == 0)
        #expect(!model.hasProgressToLose)
        #expect(!store.exists(for: HanoiModel.gameID))
        model.newGame(disks: 9)
        #expect(model.disks == 6)
        #expect(HanoiModel(services: nil, disks: 2).disks == HanoiLogic.defaultDisks)
    }

    @Test("計時は 1 手目から。開いて眺めている間は数えない")
    func timerStartsOnFirstMove() {
        let clock = ManualClock()
        let model = HanoiModel(services: makeServices())
        model.clockNow = clock.now
        model.resumeTimerIfNeeded()
        #expect(!model.isCounting, "1 手目より前は再開しても数えない")
        clock.advance(by: .seconds(30))
        model.tap(peg: 0); model.tap(peg: 2)
        #expect(model.isCounting)
        clock.advance(by: .seconds(5))
        model.pauseTimer()
        #expect(model.elapsedSeconds == 5)
        #expect(!model.isCounting)
        clock.advance(by: .seconds(100))
        model.resumeTimerIfNeeded()
        clock.advance(by: .seconds(2))
        model.pauseTimer()
        #expect(model.elapsedSeconds == 7, "止めていた間は数えない")
    }

    @Test("解析: 開始に枚数の段を載せ、1 手ごとに進行、クリアで 1 組そろう")
    func analytics() {
        let spy = SpyAnalyticsService()
        let model = HanoiModel(services: makeServices(log: makeLog("analytics"), analytics: spy), disks: 3)
        #expect(spy.starts == ["hanoi"])
        #expect(spy.startLevels == [.novice])
        playSolution(model)
        #expect(spy.ends.count == 1)
        #expect(spy.outcomes == [.win])

        model.newGame(disks: 7)
        #expect(spy.startLevels.last == .expert)
        #expect(HanoiModel.analyticsLevel(disks: 5) == .normal)
    }
}

@Suite("ハノイの塔の読み上げ")
struct HanoiAccessibilityTests {

    @Test("柱は「左の柱、上から小さい順に 1・2・3（3枚）」と、数字と枚数で読む")
    func pegLabels() {
        #expect(HanoiAccessibility.pegLabel(peg: 0, disks: [3, 2, 1]) == "左の柱、上から小さい順に 1・2・3（3枚）")
        #expect(HanoiAccessibility.pegLabel(peg: 1, disks: []) == "まんなかの柱、円盤なし")
        #expect(HanoiAccessibility.pegLabel(peg: 2, disks: [5], isSelected: true) == "右の柱、上から小さい順に 5（1枚）、いちばん上を取っています")
    }

    @Test("英語の文言（単数・複数）")
    func english() {
        #expect(GameHanoi.tr("ハノイの塔", language: .english) == "Tower of Hanoi")
        #expect(GameHanoi.tr("%1$@、上から小さい順に %2$@（%3$lld枚）", "Left peg", "1", 1, language: .english)
                == "Left peg, from the top, smallest first: 1 (1 disk)")
        #expect(GameHanoi.tr("%1$@、上から小さい順に %2$@（%3$lld枚）", "Left peg", "1, 2", 2, language: .english)
                == "Left peg, from the top, smallest first: 1, 2 (2 disks)")
        #expect(GameHanoi.tr("最少 %1$lld手に対して %2$lld手", 7, 9, language: .english) == "9 moves (fewest possible: 7)")
    }
}

@Suite("ハノイの塔の登録口")
@MainActor
struct HanoiModuleTests {
    @Test("id は英字の hanoi で、遊び方の gameID と一致する")
    func ids() {
        #expect(HanoiModule().id == "hanoi")
        #expect(HowToPlayGuide.hanoi.gameID == HanoiModule().id)
        #expect(HowToPlayGuide.hanoi.items.count == HanoiHowToFigures.items.count, "図と項目の数が合う")
    }
}
