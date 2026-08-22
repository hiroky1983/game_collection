import Foundation

/// 盤面の VoiceOver 読み上げ文（#188）。
///
/// マスは背景色・旗アイコン・数字の色だけで状態を表しているため、画面を見ないと
/// 開いているかどうかも周囲の地雷数も分からない。読み上げ文はここに集約して
/// 純関数にし、View を組まずにテストできるようにする。
public enum MinesweeperAccessibility {
    /// マス 1 つの読み上げ文（例: "3行5列、周囲の地雷2"）。
    ///
    /// - Parameters:
    ///   - isHit: 踏んで負けた地雷のマスか。
    ///   - gameOver: 終局後か（誤った旗の告知は終局後にだけ行う。画面表示と同じ扱い）。
    public static func cellLabel(
        row: Int,
        col: Int,
        cell: MinesweeperCell,
        isHit: Bool,
        gameOver: Bool
    ) -> String {
        var parts = ["\(row + 1)行\(col + 1)列"]
        if cell.isRevealed {
            if cell.isMine {
                parts.append(isHit ? "踏んだ地雷" : "地雷")
            } else if cell.adjacentMines > 0 {
                parts.append("周囲の地雷\(cell.adjacentMines)")
            } else {
                parts.append("空き")
            }
        } else if cell.isFlagged {
            parts.append(gameOver && !cell.isMine ? "誤った旗" : "旗")
        } else if cell.isContinuedMine {
            parts.append("確定した地雷")
        } else {
            parts.append("未開放")
        }
        return parts.joined(separator: "、")
    }

    /// 開くか旗を立てるかは画面上のトグル（`flagMode`）で決まるため、
    /// いまタップすると何が起きるかをヒントで補う。
    ///
    /// **実行できない操作は案内しない**（開き済みのマスに「ダブルタップで開きます」と
    /// 言われても何も起きない）。可否の判定は `MinesweeperModel.canReveal` /
    /// `canToggleFlag` が唯一の出どころで、ここでは受け取るだけにする。
    public static func cellHint(flagMode: Bool, canReveal: Bool, canToggleFlag: Bool) -> String {
        if flagMode {
            return canToggleFlag ? "ダブルタップで旗を切り替えます" : ""
        }
        return canReveal ? "ダブルタップで開きます" : ""
    }
}
