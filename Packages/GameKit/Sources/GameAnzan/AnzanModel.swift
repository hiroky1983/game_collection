import Core
import Foundation
import Observation

/// ぱっと暗算（#1321）のゲーム状態。
///
/// 1 問 = 1 プレイ（`game_start` 〜 `game_end`）。数を順に見せ、消えたら合計を入力させ、正誤で決着する。
/// 表示の進行は**時間を持たない**。`advanceDisplay()` を呼ぶたびに 1 コマ進み、次のコマまでの待ち時間を
/// 返すだけなので、View はそれをタイマーで回し、テストは待たずに呼び切る（`GameKit` のテストは実時間で
/// 待つとフレークする）。
@MainActor
@Observable
public final class AnzanModel {
    public static let gameID = "anzan"

    public enum Phase: Equatable, Sendable {
        /// まだ 1 問も始めていない（難易度のシートを出す）。
        case idle
        /// 数を順に見せている。
        case flashing
        /// 合計を入力してもらっている。
        case answering
        /// 正誤が出た。
        case result
    }

    public private(set) var settings: AnzanSettings
    public private(set) var phase: Phase = .idle
    /// いま出題している数。
    public private(set) var numbers: [Int] = []
    /// いま見せているコマ。`flashing` 以外では nil。
    public private(set) var step: AnzanDisplayStep?
    /// 入力中の答え（文字列のまま持ち、先頭の 0 の扱いと桁数の上限をここで見る）。
    public private(set) var input = ""
    /// 決定した答え。
    public private(set) var answer: Int?
    public private(set) var isCorrect = false
    /// 最後の数が消えてから決定までの秒数（切り上げ・最低 1 秒）。
    public private(set) var answerSeconds: Int?
    /// 直近の決着で確定した記録。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// いまの難易度での連続正解。`PlayRecord.currentStreak` と同じ値で、アプリを閉じても続く。
    public private(set) var streak = 0
    /// いまの難易度での最速の回答（秒）。まだ正解が無ければ nil。
    public private(set) var bestSeconds: Int?
    /// 問題の通し番号。広告の前後で問題が入れ替わっていないかの照合に使う（#526）。
    public private(set) var questionSerial = 0
    /// この問題で「もう一度見る」を使ったか（1 問 1 回）。
    public private(set) var replayUsed = false
    /// 表示の並びを頭から回し直す回数。View はこれを `.task(id:)` の鍵にする。
    public private(set) var displayRun = 0

    private let services: GameServices?
    private let now: () -> Date
    private var generator: SplitMix64?
    private var stepIndex = -1
    private var answerStartedAt: Date?
    /// `gameDidStart` を一度通したか。2 問目からは `gameDidRestart` で数える。
    private var hasCountedStart = false
    #if DEBUG
    /// 撮影用。true のあいだは表示を進めない（数を出した瞬間で止める）。
    private var isFrozenForCapture = false
    #endif

    /// - Parameters:
    ///   - seed: 出題を種から決める（テスト用。省略時はシステム乱数）。
    ///   - now: 回答時間の計測に使う時計（テスト用）。
    public init(services: GameServices? = nil, seed: UInt64? = nil, now: @escaping () -> Date = Date.init) {
        self.services = services
        self.now = now
        generator = seed.map { SplitMix64(seed: $0) }
        // 中断データは最後に選んだ難易度の控え。問題は復元せず、必ず難易度のシートから入る。
        settings = services?.snapshots.load(AnzanSnapshot.self, for: Self.gameID)?.settings ?? .standard
        refreshRecord()
    }

    // MARK: - 読み取り

    public var sum: Int { AnzanLogic.sum(numbers) }

    /// いま見せている数。空白・「よーい」・出題以外では nil。
    public var displayedNumber: Int? {
        if case let .number(index)? = step, numbers.indices.contains(index) { return numbers[index] }
        return nil
    }

    public var isShowingReady: Bool { step == .ready }

    /// 「もう一度見る」を出してよいか（入力中で、この問題ではまだ使っていない）。
    public var canReplay: Bool { phase == .answering && !replayUsed }

    public var canSubmit: Bool { phase == .answering && Int(input) != nil }

    public var maxInputDigits: Int { AnzanLogic.maxInputDigits(settings) }

    // MARK: - 進行

    /// 難易度を決めて 1 問目（または新しい難易度の 1 問目）を始める。
    public func start(_ newSettings: AnzanSettings) {
        settings = newSettings
        persist()
        refreshRecord()
        beginQuestion()
    }

    /// 同じ難易度で次の問題へ。
    public func next() {
        guard phase == .result else { return }
        beginQuestion()
    }

    /// 表示を 1 コマ進める。
    ///
    /// - Returns: いま入ったコマを見せる時間。並びを終えて入力に移ったときは nil
    ///   （`flashing` 以外で呼んでも nil）。
    @discardableResult
    public func advanceDisplay() -> Duration? {
        guard phase == .flashing else { return nil }
        #if DEBUG
        if isFrozenForCapture { return nil }
        #endif
        let steps = AnzanLogic.steps(count: numbers.count)
        stepIndex += 1
        guard stepIndex < steps.count else {
            step = nil
            phase = .answering
            answerStartedAt = now()
            return nil
        }
        let current = steps[stepIndex]
        step = current
        if stepIndex == 0 {
            // 数が出始めた = 捨てたら途中離脱として数える問題（#500）。冪等なので見直しでも増えない。
            services?.gameDidProgress(gameID: Self.gameID)
        }
        return .milliseconds(AnzanLogic.milliseconds(of: current, speed: settings.speed))
    }

    // MARK: - 入力

    public func tapDigit(_ digit: Int) {
        guard phase == .answering, (0...9).contains(digit) else { return }
        // 先頭の 0 は置き換える（「0」のあとに「5」で「05」にしない）。
        if input == "0" { input = "" }
        guard input.count < maxInputDigits else {
            services?.feedback.notify(.warning)
            return
        }
        input.append(String(digit))
        services?.feedback.impact(.light)
    }

    public func backspace() {
        guard phase == .answering, !input.isEmpty else { return }
        input.removeLast()
        services?.feedback.impact(.light)
    }

    /// 答えを決定して正誤を出す。空の入力では何も起きない。
    public func submit() {
        guard phase == .answering, let value = Int(input) else { return }
        answer = value
        isCorrect = value == sum
        phase = .result
        step = nil
        let elapsed = answerStartedAt.map { now().timeIntervalSince($0) } ?? 0
        let seconds = max(1, Int(elapsed.rounded(.up)))
        answerSeconds = seconds
        services?.feedback.notify(isCorrect ? .success : .error)
        // 決着 1 回につき `gameDidFinish` は 1 回だけ。正解のときだけ回答時間を記録し、
        // 「もう一度見る」を使った回は時間の記録から外す（見直したぶん有利になるため。正解・連続正解には数える）。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: isCorrect ? .win : .loss,
            score: GameScore(
                metric: .winLoss,
                seconds: (isCorrect && !replayUsed) ? seconds : nil,
                variant: settings.variant,
                variantLabel: settings.variantLabel
            )
        )
        if let record = recordResult?.record {
            streak = record.currentStreak
            bestSeconds = record.bestSeconds
        } else {
            streak = isCorrect ? streak + 1 : 0
        }
    }

    // MARK: - 救済

    /// 広告を見終えたあとに同じ問題をもう一度見せる（#1321 の広告救済。1 問 1 回）。
    ///
    /// - Parameter serial: 広告を出す**前に**控えた `questionSerial`。広告のあいだに問題が変わっていたら
    ///   （次の問題・難易度の変更）適用せず false を返す。
    /// - Returns: 適用できたか。
    public func replayAfterAd(forGame serial: Int) -> Bool {
        guard serial == questionSerial, canReplay else { return false }
        replayUsed = true
        input = ""
        stepIndex = -1
        step = nil
        answerStartedAt = nil
        phase = .flashing
        displayRun += 1
        return true
    }

    // MARK: - 内部

    private func beginQuestion() {
        questionSerial += 1
        numbers = makeNumbers()
        input = ""
        answer = nil
        isCorrect = false
        answerSeconds = nil
        recordResult = nil
        replayUsed = false
        stepIndex = -1
        step = nil
        answerStartedAt = nil
        phase = .flashing
        displayRun += 1
        if hasCountedStart {
            services?.gameDidRestart(gameID: Self.gameID, level: settings.analyticsLevel)
        } else {
            services?.gameDidStart(gameID: Self.gameID, level: settings.analyticsLevel)
            hasCountedStart = true
        }
        // 中断データは難易度の控えで問題そのものは復元しない。既定の「中断データが在る = 続きから戻れる」を
        // 打ち消し、途中で離れたら休憩ではなく離脱として数える（チャリンコおじさん #1105 と同じ）。
        services?.gameWillNotResume(gameID: Self.gameID)
    }

    private func makeNumbers() -> [Int] {
        if var seeded = generator {
            defer { generator = seeded }
            return AnzanLogic.makeNumbers(settings, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return AnzanLogic.makeNumbers(settings, using: &system)
    }

    private func persist() {
        try? services?.snapshots.save(AnzanSnapshot(settings: settings), for: Self.gameID)
    }

    private func refreshRecord() {
        let record = services?.playLog?.record(gameID: Self.gameID, variant: settings.variant)
        streak = record?.currentStreak ?? 0
        bestSeconds = record?.bestSeconds
    }

    #if DEBUG
    /// 撮影・動作確認用（`-anzanScenario flash|answer|correct|wrong`）。出題を固定して絵を安定させる。
    /// Release には残さない（`ModuleTests` が走査で固定する）。
    public func applyDebugScenario(_ name: String) {
        settings = AnzanSettings(digits: .two, count: .ten, speed: .normal)
        numbers = [47, 12, 85, 30, 66, 21, 93, 58, 74, 19]
        questionSerial += 1
        input = ""
        answer = nil
        recordResult = nil
        replayUsed = false
        streak = 4
        bestSeconds = 3
        switch name {
        case "flash":
            phase = .flashing
            stepIndex = 5
            step = .number(2)
            isFrozenForCapture = true
        case "answer":
            phase = .answering
            input = "50"
        case "correct":
            phase = .result
            answer = sum
            isCorrect = true
            answerSeconds = 3
            streak = 5
        case "wrong":
            phase = .result
            answer = sum - 10
            isCorrect = false
            answerSeconds = 6
            streak = 0
        default:
            break
        }
    }
    #endif
}
