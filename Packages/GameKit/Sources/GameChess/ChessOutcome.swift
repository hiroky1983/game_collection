import Foundation

/// 決着の種類。表示文言と `GameOutcome` への振り分けをここ 1 か所に集約する。
///
/// **状態として保存せず、局面と指し手列から毎回導く**（将棋の千日手・王手表示と同じ方針）。
/// こうしておくと、中断からの復元でも検討ナビで戻ったときでも、別の復元処理なしに
/// 同じ結果が出る。
public enum ChessResult: Equatable, Sendable {
    /// チェックメイト。`loser` が詰まされた側。
    case checkmate(loser: ChessColor)
    /// ステイルメイト（手番側に合法手が無く、王手もされていない）。
    case stalemate
    /// 50手ルール（駒取りもポーンの移動も無いまま両者 50 手）。
    case fiftyMoveRule
    /// 3回同形反復。
    case threefoldRepetition
    /// 駒不足（どう指しても詰ませられない）。
    case insufficientMaterial
    /// 投了。`loser` が投げた側。
    case resignation(loser: ChessColor)

    /// 引き分けか。
    public var isDraw: Bool {
        switch self {
        case .checkmate, .resignation: return false
        case .stalemate, .fiftyMoveRule, .threefoldRepetition, .insufficientMaterial: return true
        }
    }

    /// 負けた側（引き分けなら nil）。
    public var loser: ChessColor? {
        switch self {
        case let .checkmate(loser), let .resignation(loser): return loser
        case .stalemate, .fiftyMoveRule, .threefoldRepetition, .insufficientMaterial: return nil
        }
    }

    /// ステータス行に出す文言。`humanSide` から見た言い方にする。
    public func text(humanSide: ChessColor) -> String {
        switch self {
        case let .checkmate(loser):
            return loser == humanSide ? "あなたの負け（チェックメイト）" : "あなたの勝ち（チェックメイト）"
        case .stalemate:
            return "引き分け（ステイルメイト）"
        case .fiftyMoveRule:
            return "引き分け（50手ルール）"
        case .threefoldRepetition:
            return "引き分け（同じ局面が3回）"
        case .insufficientMaterial:
            return "引き分け（駒が足りない）"
        case let .resignation(loser):
            return loser == humanSide ? "あなたの負け（投了）" : "あなたの勝ち（CPUの投了）"
        }
    }
}

extension ChessPosition {
    /// どう指してもチェックメイトが成立しない駒構成か（FIDE の「デッドポジション」の
    /// 実務上の判定。キング同士・キング＋軽い駒 1 枚・同色マスのビショップ同士）。
    public func isInsufficientMaterial() -> Bool {
        var knights = 0
        var bishopSquareColors: Set<Bool> = []
        var bishops = 0
        for piece in squares {
            guard let piece else { continue }
            switch piece.type {
            case .king: continue
            case .knight: knights += 1
            case .bishop: bishops += 1
            case .pawn, .rook, .queen:
                // ポーン・ルーク・クイーンが 1 枚でも残っていれば詰ませる筋がある。
                return false
            }
        }
        for (sq, piece) in squares.enumerated() where piece?.type == .bishop {
            bishopSquareColors.insert(ChessSquare.isLightSquare(sq))
        }
        // K vs K / K+N vs K / K+B vs K
        if knights + bishops <= 1 { return true }
        // ビショップだけが何枚残っていても、全部が同じ色のマスなら詰まない。
        if knights == 0, bishopSquareColors.count <= 1 { return true }
        return false
    }
}
