import Foundation

/// 盤面の VoiceOver 読み上げ文（#188）。
///
/// 盤は `Canvas` に線と円を直接描いているため、そのままでは 15×15 の交点が
/// VoiceOver から 1 つの塊にしか見えない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum GomokuAccessibility {
    /// 交点 1 つの読み上げ文（例: "8行8列、黒石、直前の手"）。
    public static func pointLabel(row: Int, col: Int, stone: GomokuStone?, isLastMove: Bool) -> String {
        var parts = ["\(row + 1)行\(col + 1)列"]
        switch stone {
        case .black: parts.append("黒石")
        case .white: parts.append("白石")
        case nil:    parts.append("空点")
        }
        if isLastMove { parts.append("直前の手") }
        return parts.joined(separator: "、")
    }
}
