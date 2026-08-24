import Foundation

/// 盤面の VoiceOver 読み上げ文（#188）。
///
/// マスは色（出題 / 自力 / ヒント / 間違い）と小さなメモ数字だけで状態を表しているため、
/// 画面を見ないと何も分からない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする（`MinesweeperAccessibility` と同じ方針）。
public enum SudokuAccessibility {

    /// マス 1 つの読み上げ文（例: "3行5列、7、出題"）。
    ///
    /// - Parameters:
    ///   - digit: 入っている数字。0 なら空きマス。
    ///   - isGiven: 出題として最初から入っていたマスか。
    ///   - isHinted: ヒントで埋めたマスか。
    ///   - isError: 正解と違う数字が入っているか。
    ///   - noteDigits: 付いているメモ（昇順）。
    ///   - isSelected: いま選択中のマスか。
    public static func cellLabel(
        row: Int,
        col: Int,
        digit: Int,
        isGiven: Bool,
        isHinted: Bool,
        isError: Bool,
        noteDigits: [Int],
        isSelected: Bool
    ) -> String {
        var parts = ["\(row + 1)行\(col + 1)列"]
        if digit != 0 {
            parts.append("\(digit)")
            if isGiven {
                parts.append("出題")
            } else if isError {
                parts.append("間違い")
            } else if isHinted {
                parts.append("ヒント")
            }
        } else if noteDigits.isEmpty {
            parts.append("空きマス")
        } else {
            parts.append("メモ " + noteDigits.map(String.init).joined(separator: "、"))
        }
        if isSelected { parts.append("選択中") }
        return parts.joined(separator: "、")
    }

    /// いまタップすると何が起きるか。**実行できない操作は案内しない**
    /// （出題のマスに「ダブルタップで選びます」と言われても何も起きない）。
    public static func cellHint(isGiven: Bool, isPlaying: Bool) -> String {
        guard isPlaying, !isGiven else { return "" }
        return "ダブルタップで選びます"
    }

    /// 数字パッドのボタンの読み上げ文。
    ///
    /// メモモードかどうかで意味が変わる（数字を確定する / メモを付け外しする）ため、
    /// 数字だけを読ませると何が起きるか伝わらない。
    public static func padLabel(digit: Int, noteMode: Bool, isExhausted: Bool) -> String {
        var parts = [noteMode ? "メモ \(digit)" : "\(digit)"]
        if isExhausted { parts.append("使い切り") }
        return parts.joined(separator: "、")
    }

    /// ヒントボタンの読み上げ文（残り回数まで読む）。
    public static func hintLabel(remaining: Int) -> String {
        remaining > 0 ? "ヒント、残り\(remaining)回" : "ヒント、残りなし"
    }

    /// ステータスバーのまとめ読み（残りマス数と経過時間）。
    /// 個別に読ませると3要素を別々にスワイプすることになるので 1 要素にまとめる。
    public static func statusLabel(remainingCells: Int, elapsedSeconds: Int) -> String {
        let minutes = max(0, elapsedSeconds) / 60
        let seconds = max(0, elapsedSeconds) % 60
        let time = minutes > 0 ? "\(minutes)分\(seconds)秒" : "\(seconds)秒"
        return "残り\(remainingCells)マス、経過\(time)"
    }
}
