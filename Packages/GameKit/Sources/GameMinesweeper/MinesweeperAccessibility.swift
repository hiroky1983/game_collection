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
        } else if cell.mark == .question {
            // ? は旗と違って「開ける未開放マス」なので、旗と混ぜずに独立して読む（#444）。
            parts.append("はてな")
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
    /// `canToggleFlag` / `canChord` が唯一の出どころで、ここでは受け取るだけにする。
    public static func cellHint(
        flagMode: Bool,
        canReveal: Bool,
        canToggleFlag: Bool,
        canChord: Bool
    ) -> String {
        if flagMode {
            // マークは「なし → 旗 → ? → なし」の3状態を循環する（#444）。いま何が置かれて
            // いるかは `cellLabel` が読み上げるので、ここでは循環に何が含まれるかだけ伝える。
            return canToggleFlag ? "ダブルタップで旗・はてなを切り替えます" : ""
        }
        if canReveal { return "ダブルタップで開きます" }
        // 開いている数字マスは、周囲の旗が揃っていればまとめて開ける（コード・#437）。
        return canChord ? "ダブルタップで周囲をまとめて開きます" : ""
    }

    /// 旗モードの切り替えボタン（#761）。旗モードはマスのタップ結果を左右するので、
    /// 画面を見なくても「いまどちらか」が分かるよう状態込みで読む（ナンプレのメモと同じ形）。
    public static func flagToggleLabel(isOn: Bool) -> String {
        isOn ? "旗モード、オン" : "旗モード、オフ"
    }

    /// 拡大の切り替えボタン（#761）。ラベルは押すと何が起きるか（フリーセル・ナンプレと同じ）。
    public static func zoomToggleLabel(isZoomed: Bool) -> String {
        isZoomed ? "盤全体を表示" : "盤を拡大"
    }

    /// ヒントも状態で切り替える。ラベルだけ切り替えると、拡大中に「盤全体を表示」と読んだ直後に
    /// 拡大の案内をすることになる（フリーセル #604 と同じ理由）。
    public static func zoomToggleHint(isZoomed: Bool) -> String {
        isZoomed
            ? "等倍に戻して盤全体を画面に収めます"
            : "マスを大きくして指で押しやすくします。はみ出した部分は縦横にスクロールします"
    }
}
