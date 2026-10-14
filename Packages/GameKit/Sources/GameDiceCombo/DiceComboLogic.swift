/// サイコロ役づくり（#1752）の役。並び順は得点表の上から。
///
/// `rawValue` は中断データの鍵（英字）なので、**名前を変えない**。表示名は `DiceComboText.name(_:)`。
public enum DiceComboCategory: String, CaseIterable, Codable, Sendable {
    case ones, twos, threes, fours, fives, sixes
    /// チョイス: 5 個の合計（条件なし）。
    case choice
    /// フォーダイス: 同じ目が 4 個以上なら 5 個の合計。
    case fourDice
    /// フルハウス: 同じ目 3 個 + 同じ目 2 個（5 個とも同じ目も含む）なら 5 個の合計。
    case fullHouse
    /// S ストレート: 4 つ続きの目があれば 15 点。
    case smallStraight
    /// B ストレート: 5 つ続きの目なら 30 点。
    case bigStraight
    /// ファイブダイス: 5 個とも同じ目なら 50 点。
    case fiveDice

    /// 上段（1〜6 の目）。合計でボーナスを判定する。
    public static let upper: [DiceComboCategory] = [.ones, .twos, .threes, .fours, .fives, .sixes]

    /// 上段なら対象の目（1〜6）。
    public var face: Int? {
        switch self {
        case .ones: return 1
        case .twos: return 2
        case .threes: return 3
        case .fours: return 4
        case .fives: return 5
        case .sixes: return 6
        default: return nil
        }
    }
}

/// 役の判定と得点の純粋ロジック。Model はここに委譲し、乱数・永続化・記録だけを担う。
public enum DiceComboLogic {
    /// サイコロの個数。
    public static let diceCount = 5
    /// 1 ターンに振れる回数。
    public static let maxRolls = 3
    /// 上段のボーナスがもらえる合計。
    public static let upperBonusThreshold = 63
    /// 上段のボーナス。
    public static let upperBonus = 35
    public static let smallStraightScore = 15
    public static let bigStraightScore = 30
    public static let fiveDiceScore = 50
    /// 全部の役で最高の出目が出たときの点（上段 105 + ボーナス 35 + 30 + 30 + 30 + 15 + 30 + 50）。
    public static let maxTotal = 325

    /// 目 1 つが正しいか。
    public static func isValidFace(_ value: Int) -> Bool { (1...6).contains(value) }

    /// 5 個そろった正しい出目か。
    public static func isValidDice(_ dice: [Int]) -> Bool {
        dice.count == diceCount && dice.allSatisfy(isValidFace)
    }

    /// 目ごとの個数（添字 1〜6 を使う。0 番は使わない）。
    public static func counts(_ dice: [Int]) -> [Int] {
        var result = Array(repeating: 0, count: 7)
        for value in dice where isValidFace(value) { result[value] += 1 }
        return result
    }

    /// `dice` を `category` に入れたときの点。条件を満たさない役は 0 点（それでも入れられる）。
    public static func score(_ category: DiceComboCategory, dice: [Int]) -> Int {
        guard isValidDice(dice) else { return 0 }
        let total = dice.reduce(0, +)
        let counts = counts(dice)
        switch category {
        case .ones, .twos, .threes, .fours, .fives, .sixes:
            let face = category.face ?? 0
            return counts[face] * face
        case .choice:
            return total
        case .fourDice:
            return counts.contains { $0 >= 4 } ? total : 0
        case .fullHouse:
            let shape = counts.filter { $0 > 0 }.sorted()
            return (shape == [2, 3] || shape == [5]) ? total : 0
        case .smallStraight:
            let runs = [[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]]
            return runs.contains { run in run.allSatisfy { counts[$0] > 0 } } ? smallStraightScore : 0
        case .bigStraight:
            let faces = Set(dice)
            return (faces == [1, 2, 3, 4, 5] || faces == [2, 3, 4, 5, 6]) ? bigStraightScore : 0
        case .fiveDice:
            return counts.contains(5) ? fiveDiceScore : 0
        }
    }

    /// 上段の合計（入れた役だけ）。
    public static func upperSubtotal(_ scores: [DiceComboCategory: Int]) -> Int {
        DiceComboCategory.upper.reduce(0) { $0 + (scores[$1] ?? 0) }
    }

    /// 上段のボーナス（合計が 63 以上なら 35、未満なら 0）。
    public static func bonus(_ scores: [DiceComboCategory: Int]) -> Int {
        upperSubtotal(scores) >= upperBonusThreshold ? upperBonus : 0
    }

    /// 合計点（入れた役 + ボーナス）。
    public static func total(_ scores: [DiceComboCategory: Int]) -> Int {
        scores.values.reduce(0, +) + bonus(scores)
    }

    /// 12 役ぜんぶ埋まったか。
    public static func isComplete(_ scores: [DiceComboCategory: Int]) -> Bool {
        DiceComboCategory.allCases.allSatisfy { scores[$0] != nil }
    }

    /// 得点として正しいか（中断データの検証用）。その役で取りうる点だけを許す。
    public static func isPossibleScore(_ value: Int, for category: DiceComboCategory) -> Bool {
        possibleScoreTable[category]?.contains(value) ?? false
    }

    /// 5 個の出目の全通り（6^5 = 7,776 通り）。
    public static var allDice: [[Int]] {
        (0..<7776).map { code in
            var rest = code
            return (0..<diceCount).map { _ in
                defer { rest /= 6 }
                return rest % 6 + 1
            }
        }
    }

    /// 役ごとに取りうる点の全部。全通りの出目から一度だけ求める。
    private static let possibleScoreTable: [DiceComboCategory: Set<Int>] = {
        let everyDice = allDice
        var table: [DiceComboCategory: Set<Int>] = [:]
        for category in DiceComboCategory.allCases {
            table[category] = Set(everyDice.map { score(category, dice: $0) })
        }
        return table
    }()

    /// 振り直す。`held[i]` が true の目はそのまま残す。
    public static func roll(
        _ dice: [Int],
        held: [Bool],
        using generator: inout some RandomNumberGenerator
    ) -> [Int] {
        (0..<diceCount).map { index in
            let keep = held.indices.contains(index) && held[index]
            if keep, dice.indices.contains(index), isValidFace(dice[index]) { return dice[index] }
            return Int.random(in: 1...6, using: &generator)
        }
    }
}
