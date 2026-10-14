import Core
import Observation

/// サイコロ役づくり（#1752）のゲーム状態。1 人用で、12 役ぜんぶに点を入れたら 1 局の決着。
///
/// 1 ターン = 最大 3 回振る → 役を 1 つ選んで点を入れる。キープした目は振り直さない。
/// 役の判定と得点は `DiceComboLogic` に委譲し、ここは乱数・永続化・記録・解析だけを担う。
@MainActor
@Observable
public final class DiceComboModel {
    public static let gameID = "dicecombo"

    /// いまの出目。このターンでまだ振っていなければ空。
    public private(set) var dice: [Int] = []
    /// 各サイコロをキープしているか（`dice` と同じ並び）。
    public private(set) var held: [Bool] = []
    /// このターンに振った回数（0〜3）。
    public private(set) var rollsUsed = 0
    /// 埋めた役の点。
    public private(set) var scores: [DiceComboCategory: Int] = [:]
    /// 直前に点を入れた役（得点表で一瞬目立たせる）。永続化しない。
    public private(set) var lastFilled: DiceComboCategory?
    /// 12 役ぜんぶ埋まって決着したか。
    public private(set) var isFinished = false
    /// 直近の決着で確定した記録。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 振るたびに増える番号。View はサイコロの転がる動きの鍵にする。
    public private(set) var rollSerial = 0

    private let services: GameServices?
    private var generator: SplitMix64?

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと出目を種から決める（テスト用。省略時はシステム乱数）。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        generator = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(DiceComboSnapshot.self, for: Self.gameID),
           let restored = Self.restore(snap) {
            dice = restored.dice
            held = restored.held
            rollsUsed = restored.rollsUsed
            scores = restored.scores
        } else {
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: Self.gameID)
            persist()
        }
    }

    // MARK: - 読み取り

    /// いま何ターン目か（1〜12）。決着後は 12。
    public var turn: Int { min(scores.count + 1, DiceComboCategory.allCases.count) }

    /// このターンにあと何回振れるか。
    public var rollsRemaining: Int { DiceComboLogic.maxRolls - rollsUsed }

    public var canRoll: Bool { !isFinished && rollsUsed < DiceComboLogic.maxRolls }

    /// キープを切り替えられるか（振ったあとで、まだ振り直せるとき）。
    public var canHold: Bool { !isFinished && rollsUsed > 0 && rollsUsed < DiceComboLogic.maxRolls }

    /// その役にいま点を入れられるか。
    public func canChoose(_ category: DiceComboCategory) -> Bool {
        !isFinished && rollsUsed > 0 && scores[category] == nil
    }

    /// いまの出目をその役に入れたときの点（入れられないときは nil）。
    public func preview(_ category: DiceComboCategory) -> Int? {
        guard canChoose(category) else { return nil }
        return DiceComboLogic.score(category, dice: dice)
    }

    public var upperSubtotal: Int { DiceComboLogic.upperSubtotal(scores) }
    public var bonus: Int { DiceComboLogic.bonus(scores) }
    public var total: Int { DiceComboLogic.total(scores) }

    /// 「新しいゲーム」で失われる進行があるか（#1011）。1 回も振っていない局と決着した局は捨てて構わない。
    public var hasProgressToLose: Bool { !isFinished && (rollsUsed > 0 || !scores.isEmpty) }

    // MARK: - 操作

    /// キープしていないサイコロを振る。1 ターン 3 回まで。
    public func roll() {
        guard canRoll else {
            services?.feedback.notify(.warning)
            return
        }
        if rollsUsed == 0 { held = Array(repeating: false, count: DiceComboLogic.diceCount) }
        dice = rollDice()
        rollsUsed += 1
        rollSerial += 1
        lastFilled = nil
        // 振った = 捨てたら途中離脱として数える局（冪等）。
        services?.gameDidProgress(gameID: Self.gameID)
        services?.feedback.impact(.medium)
        persist()
    }

    /// `index` のサイコロのキープを切り替える。
    public func toggleHold(_ index: Int) {
        guard canHold, held.indices.contains(index) else { return }
        held[index].toggle()
        services?.feedback.impact(.light)
        persist()
    }

    /// いまの出目を `category` に入れてターンを終える。条件を満たさない役でも 0 点で入れられる。
    public func choose(_ category: DiceComboCategory) {
        guard canChoose(category) else {
            services?.feedback.notify(.warning)
            return
        }
        scores[category] = DiceComboLogic.score(category, dice: dice)
        lastFilled = category
        dice = []
        held = []
        rollsUsed = 0
        if DiceComboLogic.isComplete(scores) {
            finish()
        } else {
            services?.feedback.impact(.light)
            persist()
        }
    }

    /// 新しいゲーム。
    public func newGame() {
        dice = []
        held = []
        rollsUsed = 0
        scores = [:]
        lastFilled = nil
        isFinished = false
        recordResult = nil
        persist()
        services?.gameDidRestart(gameID: Self.gameID)
    }

    // MARK: - 内部

    private func finish() {
        isFinished = true
        services?.feedback.notify(.success)
        // 1 人用の得点ゲーム。12 役を埋め切ったら勝ちとして数え、合計点を自己ベストの対象にする（2048 と同じ）。
        // 評価リクエストの見せ場は自己ベストの更新だけにする（毎局が勝ちになるため）。
        // 決着 1 回につき `gameDidFinish` は 1 回だけ。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(metric: .points, points: total),
            isReviewHighlight: false
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    private func rollDice() -> [Int] {
        if var seeded = generator {
            defer { generator = seeded }
            return DiceComboLogic.roll(dice, held: held, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return DiceComboLogic.roll(dice, held: held, using: &system)
    }

    private func persist() {
        guard !isFinished else { return }
        let snap = DiceComboSnapshot(
            dice: dice,
            held: held,
            rollsUsed: rollsUsed,
            scores: Dictionary(uniqueKeysWithValues: scores.map { ($0.key.rawValue, $0.value) })
        )
        try? services?.snapshots.save(snap, for: Self.gameID)
    }

    /// 中断データを検証して局面に戻す。壊れたデータ・終わった局は nil（新規で始める）。
    static func restore(_ snap: DiceComboSnapshot) -> (
        dice: [Int], held: [Bool], rollsUsed: Int, scores: [DiceComboCategory: Int]
    )? {
        guard (0...DiceComboLogic.maxRolls).contains(snap.rollsUsed) else { return nil }
        if snap.rollsUsed == 0 {
            guard snap.dice.isEmpty, snap.held.isEmpty else { return nil }
        } else {
            guard DiceComboLogic.isValidDice(snap.dice), snap.held.count == DiceComboLogic.diceCount else { return nil }
        }
        var scores: [DiceComboCategory: Int] = [:]
        for (key, value) in snap.scores {
            guard let category = DiceComboCategory(rawValue: key),
                  DiceComboLogic.isPossibleScore(value, for: category) else { return nil }
            scores[category] = value
        }
        guard !DiceComboLogic.isComplete(scores) else { return nil }
        return (snap.dice, snap.held, snap.rollsUsed, scores)
    }

    #if DEBUG
    /// 撮影・動作確認用（`-dicecomboScenario rolled|late|result`）。局面を固定して絵を安定させる。
    public func applyDebugScenario(_ name: String) {
        let sample: [DiceComboCategory: Int] = [
            .ones: 3, .twos: 6, .threes: 9, .fours: 12, .fives: 15, .sixes: 18,
            .choice: 24, .fourDice: 0, .fullHouse: 23, .smallStraight: 15, .bigStraight: 30,
        ]
        switch name {
        case "rolled":
            scores = [.ones: 3, .sixes: 24, .choice: 22]
            dice = [4, 4, 2, 4, 6]
            held = [true, true, false, true, false]
            rollsUsed = 2
        case "late":
            scores = sample
            dice = [5, 5, 5, 5, 3]
            held = [true, true, true, true, false]
            rollsUsed = 2
        case "result":
            scores = sample.merging([.fiveDice: 50]) { a, _ in a }
            dice = []
            held = []
            rollsUsed = 0
            isFinished = true
        default:
            return
        }
        rollSerial += 1
    }
    #endif
}
