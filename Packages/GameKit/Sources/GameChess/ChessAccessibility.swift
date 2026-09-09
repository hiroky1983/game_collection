import Foundation

/// 盤・取られた駒の VoiceOver 読み上げ文（将棋 #188 と同じ方式）。
///
/// 見た目（`ChessCell` / `ChessPieceView`）は駒の形と明暗だけで色と駒種を表しているため、
/// 画面を見ないと何が置かれているか分からない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum ChessAccessibility {
    /// マスの呼び名（例: index 36 → "e4"）。棋譜と同じ代数式にする。
    public static func squareName(_ index: Int) -> String {
        ChessSquare.name(index)
    }

    /// 駒の呼び名（例: "白のナイト"）。
    public static func pieceName(_ piece: ChessPiece) -> String {
        "\(piece.color.name)の\(piece.type.japaneseName)"
    }

    /// 盤上 1 マスの読み上げ文。
    public static func squareLabel(
        index: Int,
        piece: ChessPiece?,
        isSelected: Bool,
        isTarget: Bool,
        isLastMove: Bool,
        isCheckedKing: Bool = false
    ) -> String {
        var parts = [squareName(index)]
        if let piece {
            parts.append(pieceName(piece))
        } else {
            parts.append("空きマス")
        }
        // 王手は「なぜ動かせないのか」に直結する情報なので、選択状態より先に読ませる。
        if isCheckedKing { parts.append("チェックされています") }
        if isSelected { parts.append("選択中") }
        if isTarget { parts.append(piece == nil ? "ここに指せます" : "取れます") }
        if isLastMove { parts.append("直前の手") }
        return parts.joined(separator: "、")
    }

    /// 取られた駒の列の読み上げ文。1 マスずつ読ませると数だけ増えて意味が伝わらないので、
    /// 「誰が何を何枚失ったか」の 1 文にまとめる。
    public static func capturedLabel(owner: ChessColor, lost: [ChessPieceType]) -> String {
        guard !lost.isEmpty else { return "\(owner.name)の取られた駒、なし" }
        var counts: [ChessPieceType: Int] = [:]
        for type in lost { counts[type, default: 0] += 1 }
        let text = ChessPieceType.allCases
            .filter { counts[$0] != nil }
            .map { "\($0.japaneseName)\(counts[$0]!)枚" }
            .joined(separator: "、")
        return "\(owner.name)の取られた駒、\(text)"
    }
}
