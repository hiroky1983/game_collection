import Foundation

/// 盤面の VoiceOver 読み上げ文（#188 のオセロと同じ作り）。
///
/// 盤は `Canvas` に三角と円を直接描いているため、そのままでは 24 ポイントが 1 つの塊にしか見えない。
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum BackgammonAccessibility {
    /// ポイント 1 つの読み上げ文（例: "6ポイント、あなたの駒5個、動かせます"）。
    ///
    /// - Parameters:
    ///   - index: 盤の添字（0 = 1 ポイント）。
    ///   - owner: 駒の持ち主。空なら nil。
    ///   - count: 駒の数。
    ///   - isMovable: 選べる駒か（選択のヒントが出ているポイント）。
    ///   - isSelected: 選択中の移動元か。
    ///   - isDestination: 選択中の駒の移動先か。
    public static func pointLabel(
        index: Int,
        owner: BackgammonSide?,
        count: Int,
        isMovable: Bool,
        isSelected: Bool,
        isDestination: Bool
    ) -> String {
        var parts = ["\(index + 1)ポイント"]
        switch owner {
        case .white: parts.append("あなたの駒\(count)個")
        case .black: parts.append("CPUの駒\(count)個")
        case nil:    parts.append("空")
        }
        if isSelected { parts.append("選択中") }
        else if isMovable { parts.append("動かせます") }
        if isDestination { parts.append("ここへ動かせます") }
        return parts.joined(separator: "、")
    }

    /// バーの読み上げ文。
    public static func barLabel(humanCount: Int, cpuCount: Int, isMovable: Bool, isSelected: Bool) -> String {
        var parts = ["バー"]
        if humanCount == 0 && cpuCount == 0 { parts.append("空") }
        if humanCount > 0 { parts.append("あなたの駒\(humanCount)個") }
        if cpuCount > 0 { parts.append("CPUの駒\(cpuCount)個") }
        if isSelected { parts.append("選択中") }
        else if isMovable { parts.append("動かせます") }
        return parts.joined(separator: "、")
    }

    /// あがりの置き場の読み上げ文。
    public static func offLabel(humanCount: Int, cpuCount: Int, isDestination: Bool) -> String {
        var parts = ["あがり", "あなた\(humanCount)個", "CPU\(cpuCount)個"]
        if isDestination { parts.append("ここへあがれます") }
        return parts.joined(separator: "、")
    }

    /// サイコロの読み上げ文（例: "サイコロ 5と3、残り 3"）。
    public static func diceLabel(dice: [Int], remaining: [Int]) -> String {
        guard !dice.isEmpty else { return "サイコロはまだ振っていません" }
        let shown = dice.count == 4 ? "\(dice[0])のゾロ目" : dice.map(String.init).joined(separator: "と")
        if remaining.isEmpty { return "サイコロ \(shown)、使い切りました" }
        return "サイコロ \(shown)、残り \(remaining.map(String.init).joined(separator: "と"))"
    }
}
