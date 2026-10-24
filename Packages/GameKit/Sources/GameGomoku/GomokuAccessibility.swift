import Foundation

/// 盤面の VoiceOver 読み上げ文（#188）。
///
/// 盤は `Canvas` に線と円を直接描いているため、そのままでは 15×15 の交点が
/// VoiceOver から 1 つの塊にしか見えない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum GomokuAccessibility {
    /// 交点 1 つの読み上げ文（例: "8行8列、黒石、直前の手"）。
    ///
    /// - Parameter isHint: ヒントが示している交点か（#1118）。見た目の印（`GomokuView.hintMark`）と
    ///   同じ条件で読ませる。
    public static func pointLabel(
        row: Int, col: Int, stone: GomokuStone?, isLastMove: Bool, isHint: Bool = false
    ) -> String {
        var parts = [tr("%1$lld行%2$lld列", row + 1, col + 1)]
        switch stone {
        case .black: parts.append(tr("黒石"))
        case .white: parts.append(tr("白石"))
        case nil:    parts.append(tr("空点"))
        }
        if isLastMove { parts.append(tr("直前の手")) }
        if isHint { parts.append(tr("ヒントの手")) }
        return parts.joined(separator: tr("、"))
    }

    /// 禁じ手で着手を断ったときの読み上げ文（#1574）。
    ///
    /// 画面の帯（`GomokuView.forbiddenNotice`）は見せるだけの表示で、VoiceOver 利用者は
    /// 触って探さない限り「なぜ石が置けないのか」に気づけない。帯と同じ文言を自動で読ませる。
    public static func forbiddenAnnouncement(reason: GomokuForbidden) -> String {
        tr("%@は打てません（禁じ手）", reason.label)
    }

    /// 結果カードの補足行（#2799）。手数に加え、五連で終わったときは決め手（最後の石の位置）を足す。
    public static func resultCardDetails(
        moveCount: Int, winningLine: [GomokuPoint]?, lastMove: (row: Int, col: Int)?
    ) -> [String] {
        var lines = [tr("%lld手", moveCount)]
        if winningLine != nil, let lastMove {
            lines.append(tr("決め手 %1$lld行%2$lld列", lastMove.row + 1, lastMove.col + 1))
        }
        return lines
    }

    /// CPU が石を置いたときの読み上げ文（#2280）。
    public static func cpuMoveAnnouncement(row: Int, col: Int) -> String {
        tr("CPUは%1$lld行%2$lld列に打ちました", row + 1, col + 1)
    }
}
