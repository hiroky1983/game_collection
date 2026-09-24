import Core

/// 出題の表示の 1 コマ。View はこの並びをタイマーで順に進める。
public enum AnzanDisplayStep: Equatable, Sendable {
    /// 最初の数が出る前の「よーい」。
    case ready
    /// `numbers[index]` を見せている。
    case number(Int)
    /// 数と数のあいだの空白。同じ数が続いても切れ目が分かるように必ず挟む。
    case blank
}

/// 出題・合計・表示の並びの純粋ロジック。Model はここに委譲し、乱数・永続化・記録だけを担う。
public enum AnzanLogic {
    /// 「よーい」を見せる時間（ミリ秒）。
    public static let readyMilliseconds = 1000

    /// 間隔のうち数を見せている割合。残りは空白。
    public static let visibleFraction = 0.7

    /// 設定どおりの個数の数を作る。桁数の範囲は `AnzanDigits.range`。
    public static func makeNumbers(
        _ settings: AnzanSettings,
        using generator: inout some RandomNumberGenerator
    ) -> [Int] {
        (0..<settings.count.rawValue).map { _ in Int.random(in: settings.digits.range, using: &generator) }
    }

    public static func sum(_ numbers: [Int]) -> Int {
        numbers.reduce(0, +)
    }

    /// 表示の並び: よーい → 数 → 空白 → 数 → 空白 … 最後の数のあとにも空白を 1 つ置き、
    /// 数が消えてから入力に移る。
    public static func steps(count: Int) -> [AnzanDisplayStep] {
        var steps: [AnzanDisplayStep] = [.ready]
        for index in 0..<max(0, count) {
            steps.append(.number(index))
            steps.append(.blank)
        }
        return steps
    }

    /// そのコマを見せる時間（ミリ秒）。数と空白を足すとちょうど 1 間隔になる。
    public static func milliseconds(of step: AnzanDisplayStep, speed: AnzanSpeed) -> Int {
        let visible = Int((Double(speed.intervalMilliseconds) * visibleFraction).rounded())
        switch step {
        case .ready:  return readyMilliseconds
        case .number: return visible
        case .blank:  return speed.intervalMilliseconds - visible
        }
    }

    /// 答えとして入力できる最大の桁数。取りうる最大の合計の桁数で、それ以上打っても正解にはならない。
    public static func maxInputDigits(_ settings: AnzanSettings) -> Int {
        String(settings.digits.range.upperBound * settings.count.rawValue).count
    }

    /// リザルトに出す式（「3 + 8 + 5 = 16」）。
    public static func expression(_ numbers: [Int]) -> String {
        guard !numbers.isEmpty else { return "" }
        return numbers.map(String.init).joined(separator: " + ") + " = " + String(sum(numbers))
    }
}
