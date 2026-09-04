import Foundation

/// 指し手の表記（SAN = 代数記法）。ステータス行の「直前 Nf3」に使う。
///
/// 将棋の `KIF` に当たるもの。**駒の記号は国際式（K/Q/R/B/N）ではなく日本語の頭文字にしない**
/// — チェスの棋譜表記としてはこちらが世界共通で、後から棋譜を人に見せるときにも通じる。
public enum ChessNotation {
    /// `pos` の局面で `move` を指したときの SAN。
    public static func san(_ move: ChessMove, in pos: ChessPosition) -> String {
        guard let piece = pos.squares[move.from] else { return move.uci }

        var text: String
        if pos.isCastling(move) {
            text = ChessSquare.file(move.to) > ChessSquare.file(move.from) ? "O-O" : "O-O-O"
        } else {
            let isCapture = pos.squares[move.to] != nil || pos.isEnPassant(move)
            if piece.type == .pawn {
                // ポーンは駒記号を書かない。取るときだけ「元の筋 + x」を前に置く。
                text = isCapture
                    ? "\(fileLetter(move.from))x\(ChessSquare.name(move.to))"
                    : ChessSquare.name(move.to)
                if let promotion = move.promotion { text += "=\(promotion.fenLetter)" }
            } else {
                text = String(piece.type.fenLetter)
                    + disambiguation(for: move, piece: piece, in: pos)
                    + (isCapture ? "x" : "")
                    + ChessSquare.name(move.to)
            }
        }

        // 王手・詰みの記号。指した後の局面から判定する。
        var after = pos
        after.make(move)
        if after.isKingInCheck(after.sideToMove) {
            text += after.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// 同じ駒種が同じマスへ複数行ける場合の区別（筋 → 段 → 両方の順に必要最小限で足す）。
    private static func disambiguation(
        for move: ChessMove, piece: ChessPiece, in pos: ChessPosition
    ) -> String {
        let rivals = pos.legalMoves().filter {
            $0.to == move.to && $0.from != move.from
                && pos.squares[$0.from]?.type == piece.type
                && pos.squares[$0.from]?.color == piece.color
        }
        guard !rivals.isEmpty else { return "" }
        let sameFile = rivals.contains { ChessSquare.file($0.from) == ChessSquare.file(move.from) }
        let sameRank = rivals.contains { ChessSquare.rank($0.from) == ChessSquare.rank(move.from) }
        if !sameFile { return fileLetter(move.from) }
        if !sameRank { return rankDigit(move.from) }
        return fileLetter(move.from) + rankDigit(move.from)
    }

    private static func fileLetter(_ square: Int) -> String {
        String(ChessSquare.name(square).prefix(1))
    }

    private static func rankDigit(_ square: Int) -> String {
        String(ChessSquare.name(square).suffix(1))
    }
}
