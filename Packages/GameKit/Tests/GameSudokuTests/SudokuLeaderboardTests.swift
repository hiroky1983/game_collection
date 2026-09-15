import Testing
import Foundation
import Core
@testable import GameSudoku
import CoreTestSupport

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
        completion(true)
    }
}

@MainActor
private struct Fixture {
    let store: MemorySnapshotStore
    let spy: SpyGameCenterService
    let log: PlayLog
    let services: GameServices

    init(suite: String, store: MemorySnapshotStore = MemorySnapshotStore()) {
        let name = "asobiba.sudoku.leaderboard.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        self.store = store
        spy = SpyGameCenterService()
        log = PlayLog(defaults: defaults)
        services = GameServices(
            snapshots: store,
            ads: NoopAdService(),
            playLog: log,
            gameCenter: GameCenterReporter(service: spy, allowedGameIDs: ["sudoku"], isAvailable: { true })
        )
    }

    func makeModel() -> SudokuModel { SudokuModel(services: services, seed: 2026) }
}

/// 空きマスを1つ選び、正解ではない数字を入れる。
@MainActor
private func enterWrongDigit(_ model: SudokuModel) {
    guard let index = (0..<81).first(where: { !model.given[$0] && model.board[$0] == 0 }) else {
        Issue.record("空きマスが無い")
        return
    }
    if model.selected != index { model.select(index: index) }
    let wrong = (1...9).first { $0 != model.solution[index] }!
    model.enter(digit: wrong)
}

/// 誤答の入ったマスも含めて、正解と違うマスをすべて正解で埋める。
@MainActor
private func solveAll(_ model: SudokuModel) {
    for index in 0..<81 where model.board[index] != model.solution[index] {
        if model.selected != index { model.select(index: index) }
        model.enter(digit: model.solution[index])
    }
}

/// ミス上限まで誤答して、広告のコンティニューで続きに戻る。
@MainActor
private func failAndContinue(_ model: SudokuModel) {
    for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
    #expect(model.state == .failed, "前提: ミス上限に達している")
    #expect(model.continueAfterAd())
}

/// 広告コンティニューを使ったクリアの順位表の扱い（#730。マインスイーパーの #657 と同じ方針）。
///
/// 経過秒を 0 より大きくしておくのは、0 秒のクリアを順位表が捨てる仕様（`GameCenterLeaderboard.score`）
/// のせいで、対照側でも送信が起きなくなるのを避けるため。
@Suite("ナンプレ 広告コンティニューと順位表（#730）")
@MainActor
struct SudokuLeaderboardTests {

    @Test("コンティニューせずにクリアした局のタイムは順位表へ送られる（対照）")
    func clearWithoutContinueIsSubmitted() async {
        let f = Fixture(suite: "control")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        model.pauseTimer()
        model.tick()
        solveAll(model)

        #expect(model.state == .cleared)
        #expect(f.spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.sudokuEasy])
    }

    @Test("コンティニューを使ったクリアは順位表へ送らない")
    func clearAfterContinueIsNotSubmitted() async {
        let f = Fixture(suite: "continued")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        model.pauseTimer()
        model.tick()
        failAndContinue(model)
        model.pauseTimer()
        #expect(model.continueUsed)
        solveAll(model)

        #expect(model.state == .cleared, "前提: コンティニュー後にクリアしている")
        #expect(f.spy.scores.isEmpty, "広告コンティニューを使った局のタイムを順位表に混ぜない")
    }

    @Test("コンティニューを使っても自己ベスト（端末内）には記録される")
    func clearAfterContinueKeepsPersonalBest() async {
        let f = Fixture(suite: "personal-best")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        model.pauseTimer()
        model.tick()
        failAndContinue(model)
        model.pauseTimer()
        solveAll(model)

        #expect(model.state == .cleared)
        #expect(f.log.record(gameID: "sudoku", variant: "easy")?.bestSeconds == model.elapsedSeconds,
                "自己ベストは使用有無を問わず残す")
        #expect(model.recordResult != nil, "リザルトの自己ベスト表示も従来どおり出る")
    }

    @Test("新規ゲームで使用済みがリセットされ、次の局のクリアは順位表へ送られる")
    func newGameResetsContinueUsed() async {
        let f = Fixture(suite: "reset")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        failAndContinue(model)
        #expect(model.continueUsed)

        await model.newGame(difficulty: .easy)
        #expect(!model.continueUsed)
        model.pauseTimer()
        model.tick()
        solveAll(model)
        #expect(f.spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.sudokuEasy])
    }
}

/// コンティニューの使用済みを中断データに持ち回る（#730）。
@Suite("ナンプレ 中断データとコンティニューの使用済み（#730）")
@MainActor
struct SudokuSnapshotTests {

    @Test("コンティニュー使用済みが再起動で復活しない")
    func continueUsedSurvivesRestart() async {
        let f = Fixture(suite: "restart")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        model.pauseTimer()
        model.tick()
        failAndContinue(model)
        model.pauseTimer()

        let restored = f.makeModel()
        #expect(restored.state == .playing, "前提: 中断データから続きを復元している")
        #expect(restored.continueUsed, "使用済みフラグが復元される")
        solveAll(restored)
        #expect(restored.state == .cleared)
        #expect(f.spy.scores.isEmpty, "再起動をはさんでも順位表の資格は戻らない")
    }

    @Test("使用済みの鍵を持たない旧形式の中断データも読め、未使用として扱う")
    func legacySnapshotReadsAsUnused() async throws {
        let f = Fixture(suite: "legacy")
        let model = f.makeModel()
        await model.newGame(difficulty: .easy)
        model.pauseTimer()

        // 鍵を落として v1.1.4 までの中断データと同じ形にする（nil の optional は鍵ごと書かれない）。
        var snapshot = try #require(f.store.load(SudokuSnapshot.self, for: "sudoku"))
        snapshot.continueUsed = nil
        try f.store.save(snapshot, for: "sudoku")
        let legacyData = try #require(f.store.rawData(for: "sudoku"))
        let legacy = try #require(String(data: legacyData, encoding: .utf8))
        #expect(!legacy.contains("continueUsed"), "前提: 旧形式と同じく鍵が無い中断データ")

        let restored = f.makeModel()
        #expect(restored.state == .playing, "鍵が増えても既存の中断データを失わせない")
        #expect(!restored.continueUsed, "欠けていたら『まだ使っていない』として読む")
    }
}
