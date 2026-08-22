import Foundation

/// 盤面の VoiceOver 読み上げ文（#188）。
///
/// 盤は `Canvas` に線と円を直接描いているため、そのままでは 64 マスが VoiceOver から
/// 1 つの塊にしか見えない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum OthelloAccessibility {
    /// マス 1 つの読み上げ文（例: "4行3列、空、ここに置けます"）。
    ///
    /// - Parameter isValidMove: いま手番の石をここに置けるか（合法手ドットが出ているマス）。
    public static func squareLabel(
        row: Int,
        col: Int,
        stone: OthelloStone?,
        isValidMove: Bool,
        isLastMove: Bool
    ) -> String {
        var parts = ["\(row + 1)行\(col + 1)列"]
        switch stone {
        case .black: parts.append("黒")
        case .white: parts.append("白")
        case nil:    parts.append("空")
        }
        if isValidMove { parts.append("ここに置けます") }
        if isLastMove { parts.append("直前の手") }
        return parts.joined(separator: "、")
    }
}
