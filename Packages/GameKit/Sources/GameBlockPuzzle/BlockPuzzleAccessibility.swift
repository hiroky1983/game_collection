import Foundation

/// 盤面と手元の VoiceOver 読み上げ文（#188 の横展開）。
///
/// このゲームは「どのマスが空いているか」と「手元の形」が分からないと 1 手も指せないため、
/// 見えている情報を音声でも同じだけ渡す必要がある。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum BlockPuzzleAccessibility {

    /// 盤の 1 マス（例: "3行5列、ブロック" / "3行5列、空きマス"）。
    ///
    /// 手元を選んでいるときは `canPlaceSelected` に「このマスを左上にして置けるか」を渡し、
    /// 末尾に読み足す（例: "3行5列、空きマス、置けます"。#1044）。
    public static func cellLabel(row: Int, col: Int, value: Int, canPlaceSelected: Bool? = nil) -> String {
        let base = "\(row + 1)行\(col + 1)列、\(value == 0 ? "空きマス" : "ブロック")"
        guard let canPlaceSelected else { return base }
        return base + (canPlaceSelected ? "、置けます" : "、置けません")
    }

    /// 手元を選んでいるときの盤のマスのヒント（#1044）。L 字は左上が空きのことがあるので基準を明示する。
    public static let cellHint = "ダブルタップで、選んだ形をこのマスを左上にして置きます"

    /// 手元のスロットのヒント（#1044）。
    public static let handHint = "ダブルタップで選び、盤のマスを選んで置きます"

    /// ピースの形の呼び名（例: "横4マスの棒" / "3×3の四角" / "L字5マス"）。
    ///
    /// 形の名前を持たせず外接矩形とマス数から機械的に作る。カタログにピースを足しても
    /// ここを直さずに読み上げが付いてくる。
    public static func shapeLabel(_ piece: BlockPuzzlePiece) -> String {
        let filled = piece.size == piece.width * piece.height
        switch (piece.width, piece.height, filled) {
        case (1, 1, _):            return "1マス"
        case (_, 1, true):         return "横\(piece.width)マスの棒"
        case (1, _, true):         return "縦\(piece.height)マスの棒"
        case let (w, h, true):     return "\(w)×\(h)の四角"
        default:                   return "L字\(piece.size)マス"
        }
    }

    /// 手元のピース（例: "手元2つ目、L字5マス、置けます" / "手元2つ目、L字5マス、置けます、選択中"）。
    public static func handLabel(index: Int, piece: BlockPuzzlePiece?, canPlace: Bool, isSelected: Bool = false) -> String {
        guard let piece else { return "手元\(index + 1)つ目、使用済み" }
        let base = "手元\(index + 1)つ目、\(shapeLabel(piece))、\(canPlace ? "置けます" : "置ける場所がありません")"
        return isSelected ? base + "、選択中" : base
    }

    /// スコアと連鎖の読み上げ（例: "スコア120、2連鎖中"）。
    public static func statusLabel(score: Int, combo: Int) -> String {
        combo > 1 ? "スコア\(score)、\(combo)連鎖中" : "スコア\(score)"
    }
}
