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
    /// - Parameter isHint: ヒントが示している升か（#2011）。見た目の印（`OthelloView.hintMark`）と対にする。
    public static func squareLabel(
        row: Int,
        col: Int,
        stone: OthelloStone?,
        isValidMove: Bool,
        isLastMove: Bool,
        isHint: Bool = false
    ) -> String {
        var parts = [tr("%1$lld行%2$lld列", row + 1, col + 1)]
        switch stone {
        case .black: parts.append(tr("黒"))
        case .white: parts.append(tr("白"))
        case nil:    parts.append(tr("空"))
        }
        if isValidMove { parts.append(tr("ここに置けます")) }
        if isLastMove { parts.append(tr("直前の手")) }
        if isHint { parts.append(tr("ヒントの手")) }
        return parts.joined(separator: tr("、"))
    }
}
