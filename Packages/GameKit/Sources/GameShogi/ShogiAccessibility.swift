import Foundation

/// 盤・持ち駒の VoiceOver 読み上げ文（#188）。
///
/// 見た目（`ShogiCell` / `KomaView`）は色と漢字1文字で先後や成りを表しているため、
/// 画面を見ないと駒種も手番も分からない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum ShogiAccessibility {
    /// 段の漢数字（rank 0 = 一段目）。
    private static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// マスの呼び名（例: index 60 → "7七"）。筋はアラビア数字・段は漢数字という棋譜の慣習に合わせる。
    public static func squareName(_ index: Int) -> String {
        "\(Sq.file(index) + 1)\(rankKanji[Sq.rank(index)])"
    }

    /// 駒の呼び名（例: 成った歩 → "と金"）。盤面の1文字表記（`Glyph.kanji`）は
    /// 「圭」「全」のように読み上げても意味が伝わらないため、別に語を用意する。
    public static func pieceName(_ piece: Piece) -> String {
        if piece.promoted {
            switch piece.type {
            case .pawn:   return "と金"
            case .lance:  return "成香"
            case .knight: return "成桂"
            case .silver: return "成銀"
            case .bishop: return "馬"
            case .rook:   return "龍"
            case .gold, .king: break
            }
        }
        switch piece.type {
        case .pawn:   return "歩"
        case .lance:  return "香車"
        case .knight: return "桂馬"
        case .silver: return "銀"
        case .gold:   return "金"
        case .bishop: return "角"
        case .rook:   return "飛車"
        case .king:   return "玉"
        }
    }

    private static func sideName(_ side: Side) -> String {
        side == .black ? "先手" : "後手"
    }

    /// 盤上 1 マスの読み上げ文。
    public static func squareLabel(
        index: Int,
        piece: Piece?,
        isSelected: Bool,
        isTarget: Bool,
        isLastMove: Bool,
        isCheckedKing: Bool = false
    ) -> String {
        var parts = [squareName(index)]
        if let piece {
            parts.append("\(sideName(piece.color))の\(pieceName(piece))")
        } else {
            parts.append("空きマス")
        }
        // 王手は「なぜ動かせないのか」に直結する情報なので、選択状態より先に読ませる（#377）。
        // 見た目の赤枠（`ShogiView.checkLayer`）と同じ条件で出す。
        if isCheckedKing { parts.append("王手されています") }
        if isSelected { parts.append("選択中") }
        if isTarget { parts.append(piece == nil ? "ここに指せます" : "取れます") }
        if isLastMove { parts.append("直前の手") }
        return parts.joined(separator: "、")
    }

    /// 持ち駒 1 種類の読み上げ文。
    public static func handLabel(type: PieceType, color: Side, count: Int, isSelected: Bool) -> String {
        var text = "\(sideName(color))の持ち駒、\(pieceName(Piece(type: type, color: color)))\(count)枚"
        if isSelected { text += "、選択中" }
        return text
    }
}
