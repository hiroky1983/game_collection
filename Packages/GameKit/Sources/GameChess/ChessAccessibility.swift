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
        tr("%1$@の%2$@", piece.color.name, piece.type.displayName)
    }

    /// 盤上 1 マスの読み上げ文。
    public static func squareLabel(
        index: Int,
        piece: ChessPiece?,
        isSelected: Bool,
        isTarget: Bool,
        isLastMove: Bool,
        isCheckedKing: Bool = false,
        isHint: Bool = false
    ) -> String {
        var parts = [squareName(index)]
        if let piece {
            parts.append(pieceName(piece))
        } else {
            parts.append(tr("空きマス"))
        }
        // 王手は「なぜ動かせないのか」に直結する情報なので、選択状態より先に読ませる。
        if isCheckedKing { parts.append(tr("チェックされています")) }
        if isSelected { parts.append(tr("選択中")) }
        if isTarget { parts.append(piece == nil ? tr("ここに指せます") : tr("取れます")) }
        if isLastMove { parts.append(tr("直前の手")) }
        // ヒントの印（#1118）。見た目の枠（`ChessView.targetLayer` が描くヒントの印）と同じ条件で読ませる。
        if isHint { parts.append(tr("ヒントの手")) }
        return parts.joined(separator: tr("、"))
    }

    /// 成り先の選択札の読み上げ文（#1641）。見た目の問い（`ChessView.promotionOverlay`）と同じ文言にする。
    public static var promotionPromptLabel: String { tr("何に成りますか？") }

    /// 取られた駒の列の読み上げ文。1 マスずつ読ませると数だけ増えて意味が伝わらないので、
    /// 「誰が何を何枚失ったか」の 1 文にまとめる。
    public static func capturedLabel(owner: ChessColor, lost: [ChessPieceType]) -> String {
        guard !lost.isEmpty else { return tr("%@の取られた駒、なし", owner.name) }
        var counts: [ChessPieceType: Int] = [:]
        for type in lost { counts[type, default: 0] += 1 }
        let text = ChessPieceType.allCases
            .filter { counts[$0] != nil }
            .map { tr("%1$@%2$lld枚", $0.displayName, counts[$0]!) }
            .joined(separator: tr("、"))
        return tr("%1$@の取られた駒、%2$@", owner.name, text)
    }

    /// CPU が指したときの読み上げ文（#2280）。`piece` は指したあとの `to` にある駒。
    /// チェックは「なぜ動かせない駒があるのか」に直結するので、掛かっていれば続けて読ませる。
    public static func cpuMoveAnnouncement(piece: ChessPiece?, move: ChessMove, isCheck: Bool) -> String {
        let from = squareName(move.from), to = squareName(move.to)
        var text: String
        if let piece {
            text = tr("CPUは%1$@を%2$@から%3$@へ動かしました", pieceName(piece), from, to)
        } else {
            text = tr("CPUは%1$@から%2$@へ動かしました", from, to)
        }
        if isCheck { text += tr("。") + tr("チェックです") }
        return text
    }
}
