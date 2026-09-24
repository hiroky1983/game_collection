import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameAnzan

/// 時計を手で進める（回答時間の計測を実時間に頼らない）。
@MainActor
private final class ManualClock {
    var current = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [AnzanModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.anzan.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 表示の並びを待たずに最後まで進め、見せた数を返す。
@MainActor
private func flashThrough(_ model: AnzanModel) -> [Int] {
    var shown: [Int] = []
    while model.advanceDisplay() != nil {
        if let number = model.displayedNumber { shown.append(number) }
    }
    return shown
}

@MainActor
private func type(_ value: Int, into model: AnzanModel) {
    for character in String(value) { model.tapDigit(Int(String(character))!) }
}

@MainActor
@Suite("ぱっと暗算の Model")
struct AnzanModelTests {

    @Test("開いた直後は何も始めず、難易度は既定")
    func freshStart() {
        let model = AnzanModel(services: makeServices(), seed: 1)
        #expect(model.phase == .idle)
        #expect(model.settings == .standard)
        #expect(model.numbers.isEmpty)
        #expect(model.advanceDisplay() == nil, "始める前は表示が進まない")
        #expect(!model.canReplay)
        #expect(!model.canSubmit)
    }

    @Test("始めると数が用意され、表示は よーい → 全部の数 → 入力へと進む")
    func flashSequence() {
        let model = AnzanModel(services: makeServices(), seed: 2)
        let settings = AnzanSettings(digits: .two, count: .ten, speed: .fast)
        model.start(settings)
        #expect(model.phase == .flashing)
        #expect(model.numbers.count == 10)
        #expect(model.numbers.allSatisfy { (10...99).contains($0) })
        #expect(model.questionSerial == 1)

        let first = model.advanceDisplay()
        #expect(model.isShowingReady)
        #expect(first == .milliseconds(AnzanLogic.readyMilliseconds))
        var shown: [Int] = []
        var waits: [Duration] = []
        while let wait = model.advanceDisplay() {
            waits.append(wait)
            if let number = model.displayedNumber { shown.append(number) }
        }
        #expect(shown == model.numbers, "数を順に全部見せる")
        #expect(waits.count == 20, "数と空白で 10 組")
        #expect(waits[0] == .milliseconds(AnzanLogic.milliseconds(of: .number(0), speed: .fast)))
        #expect(waits[1] == .milliseconds(AnzanLogic.milliseconds(of: .blank, speed: .fast)))
        #expect(model.phase == .answering)
        #expect(model.step == nil)
        #expect(model.displayedNumber == nil)
        #expect(model.advanceDisplay() == nil, "入力中はもう進まない")
    }

    @Test("正解すると win で決着し、回答時間と連続正解を記録する")
    func correctAnswerRecordsWin() {
        let clock = ManualClock()
        let log = makeLog("correct")
        let model = AnzanModel(services: makeServices(log: log), seed: 3, now: { clock.current })
        let settings = AnzanSettings(digits: .one, count: .five, speed: .normal)
        model.start(settings)
        _ = flashThrough(model)
        clock.advance(2.4)
        type(model.sum, into: model)
        #expect(model.canSubmit)
        model.submit()
        #expect(model.phase == .result)
        #expect(model.isCorrect)
        #expect(model.answer == model.sum)
        #expect(model.answerSeconds == 3, "切り上げ")
        #expect(model.streak == 1)
        #expect(model.bestSeconds == 3)
        let record = log.record(gameID: AnzanModel.gameID, variant: settings.variant)
        #expect(record?.metric == .winLoss)
        #expect(record?.wins == 1)
        #expect(record?.currentStreak == 1)
        #expect(record?.bestSeconds == 3)
        #expect(record?.variantLabel == "1桁・5個・ふつう")
        #expect(log.record(gameID: AnzanModel.gameID) == nil, "区分なしの記録は作らない")
    }

    @Test("間違えると loss で決着し、連続正解が 0 に戻り、時間は記録しない")
    func wrongAnswerRecordsLoss() {
        let clock = ManualClock()
        let log = makeLog("wrong")
        let feedback = SpyFeedbackService()
        let model = AnzanModel(services: makeServices(log: log, feedback: feedback), seed: 4, now: { clock.current })
        let settings = AnzanSettings(digits: .one, count: .five, speed: .normal)
        model.start(settings)
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        #expect(model.streak == 1)
        model.next()
        _ = flashThrough(model)
        clock.advance(5)
        type(model.sum + 1, into: model)
        model.submit()
        #expect(!model.isCorrect)
        #expect(model.streak == 0)
        #expect(model.answerSeconds == 5)
        let record = log.record(gameID: AnzanModel.gameID, variant: settings.variant)
        #expect(record?.plays == 2)
        #expect(record?.losses == 1)
        #expect(record?.currentStreak == 0)
        #expect(record?.bestStreak == 1)
        #expect(feedback.notices(of: .success) == 1)
        #expect(feedback.notices(of: .error) == 1)
    }

    @Test("回答時間は最低 1 秒（時計が動かなくても 0 秒の記録を作らない）")
    func answerSecondsAtLeastOne() {
        let clock = ManualClock()
        let model = AnzanModel(services: makeServices(log: makeLog("zero")), seed: 5, now: { clock.current })
        model.start(.standard)
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        #expect(model.answerSeconds == 1)
        clock.advance(-100)
        model.next()
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        #expect(model.answerSeconds == 1, "時計が巻き戻っても負にならない")
    }

    @Test("入力は入力中だけ効き、桁数の上限を超えず、先頭の 0 は置き換わる")
    func inputRules() {
        let feedback = SpyFeedbackService()
        let model = AnzanModel(services: makeServices(feedback: feedback), seed: 6)
        model.tapDigit(5)
        #expect(model.input.isEmpty, "始める前は打てない")
        model.start(AnzanSettings(digits: .one, count: .five, speed: .slow))   // 最大 2 桁（45）
        model.tapDigit(5)
        #expect(model.input.isEmpty, "数が出ているあいだは打てない")
        _ = flashThrough(model)
        model.tapDigit(0)
        model.tapDigit(0)
        #expect(model.input == "0", "0 を重ねない")
        model.tapDigit(7)
        #expect(model.input == "7", "先頭の 0 は置き換わる")
        model.tapDigit(3)
        #expect(model.input == "73")
        model.tapDigit(1)
        #expect(model.input == "73", "上限の桁数を超えない")
        #expect(feedback.notices(of: .warning) == 1, "超えたときは断りの触覚")
        model.tapDigit(12)
        #expect(model.input == "73", "1 桁でない値は無視")
        model.backspace()
        #expect(model.input == "7")
        model.backspace()
        model.backspace()
        #expect(model.input.isEmpty)
        #expect(!model.canSubmit)
        model.submit()
        #expect(model.phase == .answering, "空の入力では決定できない")
        model.tapDigit(0)
        #expect(model.canSubmit, "0 は答えとして決定できる")
    }

    @Test("決定後の入力・二重の決定は効かず、記録は 1 回だけ")
    func submitIsFinal() {
        let log = makeLog("final")
        let model = AnzanModel(services: makeServices(log: log), seed: 7)
        model.start(.standard)
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        model.tapDigit(9)
        model.backspace()
        model.submit()
        #expect(model.input == String(model.sum))
        #expect(log.record(gameID: AnzanModel.gameID, variant: model.settings.variant)?.plays == 1)
    }

    @Test("次の問題は同じ難易度で新しい数になり、見直しと入力が戻る")
    func nextQuestion() {
        let model = AnzanModel(services: makeServices(), seed: 8)
        let settings = AnzanSettings(digits: .two, count: .five, speed: .slow)
        model.start(settings)
        let first = model.numbers
        _ = flashThrough(model)
        #expect(model.replayAfterAd(forGame: model.questionSerial))
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        let runBefore = model.displayRun
        model.next()
        #expect(model.phase == .flashing)
        #expect(model.numbers != first)
        #expect(model.settings == settings)
        #expect(model.questionSerial == 2)
        #expect(model.input.isEmpty)
        #expect(!model.replayUsed)
        #expect(model.answer == nil)
        #expect(model.recordResult == nil)
        #expect(model.displayRun == runBefore + 1, "表示の並びを頭から回し直す")
        _ = flashThrough(model)
        #expect(model.canReplay, "次の問題では見直せる")
    }

    @Test("next は決着後にしか効かない")
    func nextOnlyAfterResult() {
        let model = AnzanModel(services: makeServices(), seed: 9)
        model.next()
        #expect(model.phase == .idle)
        model.start(.standard)
        let numbers = model.numbers
        model.next()
        #expect(model.numbers == numbers, "数が出ているあいだは次へ進めない")
        _ = flashThrough(model)
        model.next()
        #expect(model.phase == .answering)
    }

    // MARK: - 見直し（広告救済）

    @Test("見直しは入力中に 1 問 1 回だけで、同じ数を頭からもう一度見せる")
    func replayShowsTheSameNumbersOnce() {
        let model = AnzanModel(services: makeServices(), seed: 10)
        model.start(AnzanSettings(digits: .two, count: .five, speed: .normal))
        #expect(!model.canReplay, "数が出ているあいだは見直せない")
        #expect(!model.replayAfterAd(forGame: model.questionSerial))
        let shown = flashThrough(model)
        #expect(model.canReplay)
        model.tapDigit(4)
        let runBefore = model.displayRun
        #expect(model.replayAfterAd(forGame: model.questionSerial))
        #expect(model.phase == .flashing)
        #expect(model.replayUsed)
        #expect(model.input.isEmpty, "打ちかけの答えは消す")
        #expect(model.displayRun == runBefore + 1)
        #expect(flashThrough(model) == shown, "同じ数を同じ順で見せる")
        #expect(model.phase == .answering)
        #expect(!model.canReplay, "2 回目は無い")
        #expect(!model.replayAfterAd(forGame: model.questionSerial))
    }

    @Test("広告のあいだに問題が変わっていたら見直しを乗せない（局ガード #526）")
    func replayGuardRejectsStaleSerial() {
        let model = AnzanModel(services: makeServices(), seed: 11)
        model.start(.standard)
        _ = flashThrough(model)
        let staleSerial = model.questionSerial
        type(model.sum, into: model)
        model.submit()
        model.next()
        _ = flashThrough(model)
        #expect(!model.replayAfterAd(forGame: staleSerial), "前の問題の通し番号では適用しない")
        #expect(!model.replayUsed)
        #expect(model.canReplay, "いまの問題の見直しは残っている")
        // 難易度を変えて始め直した場合も同じ。
        let serial = model.questionSerial
        model.start(AnzanSettings(digits: .three, count: .five, speed: .slow))
        _ = flashThrough(model)
        #expect(!model.replayAfterAd(forGame: serial))
        #expect(model.replayAfterAd(forGame: model.questionSerial))
    }

    @Test("見直した問題は正解・連続正解には数えるが、最速の記録には入れない")
    func replayedQuestionIsExcludedFromBestSeconds() {
        let clock = ManualClock()
        let log = makeLog("replay")
        let model = AnzanModel(services: makeServices(log: log), seed: 12, now: { clock.current })
        model.start(.standard)
        _ = flashThrough(model)
        #expect(model.replayAfterAd(forGame: model.questionSerial))
        _ = flashThrough(model)
        clock.advance(1)
        type(model.sum, into: model)
        model.submit()
        #expect(model.isCorrect)
        #expect(model.streak == 1)
        #expect(model.bestSeconds == nil)
        let record = log.record(gameID: AnzanModel.gameID, variant: model.settings.variant)
        #expect(record?.wins == 1)
        #expect(record?.bestSeconds == nil)
        // 対照: 見直さずに正解すれば時間が入る。
        model.next()
        _ = flashThrough(model)
        clock.advance(4)
        type(model.sum, into: model)
        model.submit()
        #expect(model.bestSeconds == 4)
        #expect(log.record(gameID: AnzanModel.gameID, variant: model.settings.variant)?.bestSeconds == 4)
    }

    // MARK: - 難易度・記録・中断データ

    @Test("難易度は問題を出すときに焼き込まれ、区分ごとに記録が分かれる")
    func recordsPerVariant() {
        let log = makeLog("variants")
        let model = AnzanModel(services: makeServices(log: log), seed: 13)
        let easy = AnzanSettings(digits: .one, count: .five, speed: .slow)
        let hard = AnzanSettings(digits: .three, count: .fifteen, speed: .fast)
        model.start(easy)
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        model.start(hard)
        #expect(model.streak == 0, "別の区分の連続正解は持ち越さない")
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        #expect(log.record(gameID: AnzanModel.gameID, variant: easy.variant)?.wins == 1)
        #expect(log.record(gameID: AnzanModel.gameID, variant: hard.variant)?.wins == 1)
        model.start(easy)
        #expect(model.streak == 1, "戻ればその区分の連続正解が復元される")
        #expect(model.bestSeconds != nil)
    }

    @Test("最後に選んだ難易度は中断データに残り、次に開いたときの初期値になる")
    func settingsPersist() {
        let store = MemorySnapshotStore()
        let first = AnzanModel(services: makeServices(store: store), seed: 14)
        #expect(!store.exists(for: AnzanModel.gameID), "開いただけでは書かない")
        let chosen = AnzanSettings(digits: .two, count: .fifteen, speed: .fast)
        first.start(chosen)
        #expect(store.load(AnzanSnapshot.self, for: AnzanModel.gameID)?.settings == chosen)
        let second = AnzanModel(services: makeServices(store: store), seed: 15)
        #expect(second.settings == chosen)
        #expect(second.phase == .idle, "問題そのものは復元しない")
        #expect(second.numbers.isEmpty)
    }

    @Test("壊れた中断データは捨てて既定に倒す")
    func brokenSnapshotFallsBack() {
        let store = MemorySnapshotStore()
        store.inject(Data("{\"settings\":{\"digits\":9}}".utf8), for: AnzanModel.gameID)
        let model = AnzanModel(services: makeServices(store: store), seed: 16)
        #expect(model.settings == .standard)
    }

    @Test("登録口の resumesFromSnapshot は false で、中断データがあっても「続きから」にならない")
    func neverResumable() {
        let store = MemorySnapshotStore()
        let model = AnzanModel(services: makeServices(store: store), seed: 17)
        model.start(.standard)
        #expect(store.exists(for: AnzanModel.gameID))
        #expect(!AnzanModule().hasResumableSnapshot(in: store))
    }

    // MARK: - 解析（#158 / #500）

    @Test("1 問 = 1 プレイで game_start / game_end が出て、level は難易度から決まる")
    func analyticsPerQuestion() {
        let spy = SpyAnalyticsService()
        let model = AnzanModel(services: makeServices(analytics: spy), seed: 18)
        #expect(spy.starts.isEmpty, "開いただけでは始めない")
        model.start(AnzanSettings(digits: .three, count: .fifteen, speed: .fast))
        #expect(spy.starts == [AnzanModel.gameID])
        #expect(spy.startLevels == [.expert])
        _ = flashThrough(model)
        type(model.sum, into: model)
        model.submit()
        #expect(spy.outcomes == [.win])
        model.next()
        #expect(spy.starts.count == 2, "次の問題は新しいプレイ")
        _ = flashThrough(model)
        type(model.sum + 1, into: model)
        model.submit()
        #expect(spy.outcomes == [.win, .loss])
        model.start(.standard)
        #expect(spy.startLevels.last == .beginner, "難易度を変えると level も変わる")
    }

    @Test("数が出始めた問題を捨てると quit、出る前に離れれば quit は出ない")
    func quitCounting() {
        let spy = SpyAnalyticsService()
        let services = makeServices(analytics: spy)
        let model = AnzanModel(services: services, seed: 19)
        model.start(.standard)
        // 数が出る前（よーい すら出ていない）に次の問題へ → 進行が無いので quit は出ない。
        model.start(.standard)
        #expect(spy.quits.isEmpty)
        #expect(spy.starts.count == 2)
        model.advanceDisplay()
        model.start(.standard)
        #expect(spy.quits.count == 1, "数が出始めていたら途中離脱")
        // 画面を離れたとき: 中断データはあるが復元しないので離脱として数える。
        model.advanceDisplay()
        services.gameDidLeave(gameID: AnzanModel.gameID)
        #expect(spy.quits.count == 2, "中断データがあっても休憩扱いにしない（gameWillNotResume）")
    }

    @Test("撮影用の局面は数を固定し、flash は表示を進めない")
    func debugScenarios() {
        let model = AnzanModel(services: makeServices(), seed: 20)
        model.applyDebugScenario("flash")
        #expect(model.phase == .flashing)
        #expect(model.displayedNumber == 85)
        #expect(model.advanceDisplay() == nil, "撮影中は止めたまま")
        #expect(model.displayedNumber == 85)
        model.applyDebugScenario("answer")
        #expect(model.phase == .answering)
        #expect(model.canReplay)
        model.applyDebugScenario("correct")
        #expect(model.phase == .result && model.isCorrect)
        model.applyDebugScenario("wrong")
        #expect(model.phase == .result && !model.isCorrect && model.answer == model.sum - 10)
    }
}
