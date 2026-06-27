import Foundation

/// 局面を CoreML モデルへの入力ベクトルに変換する。
/// Python の訓練スクリプト（Scripts/train_eval.py）と完全に同じエンコードを使うこと。
///
/// 特徴量レイアウト (95次元 Float32):
///   [0..80]  盤上 81 マス — 手番側の駒=正、相手駒=負、空=0.0
///   [81..87] 自分の持ち駒 (歩,香,桂,銀,金,角,飛) count / 18.0
///   [88..94] 相手の持ち駒 (同順)
public enum PositionFeatures {
    public static let size = 95

    // 駒の価値 (正規化用)
    private static func pieceValue(_ p: Piece) -> Float {
        let base: Float
        if p.promoted {
            switch p.type {
            case .pawn, .lance, .knight, .silver: base = 0.60
            case .bishop: base = 1.20
            case .rook:   base = 1.30
            default:      base = 0.60
            }
        } else {
            switch p.type {
            case .pawn:   base = 0.10
            case .lance:  base = 0.30
            case .knight: base = 0.40
            case .silver: base = 0.50
            case .gold:   base = 0.60
            case .bishop: base = 0.80
            case .rook:   base = 1.00
            case .king:   base = 0.00  // 玉は常に両方いるので差にならない
            }
        }
        return base
    }

    public static func encode(_ pos: Position) -> [Float] {
        var f = [Float](repeating: 0, count: size)
        let me = pos.sideToMove

        // 盤上
        for sq in 0..<81 {
            guard let p = pos.squares[sq] else { continue }
            let v = pieceValue(p)
            f[sq] = p.color == me ? v : -v
        }

        // 持ち駒 (PieceType.allCases の droppable 順 = pawn..rook)
        let handTypes: [PieceType] = [.pawn, .lance, .knight, .silver, .gold, .bishop, .rook]
        let opp = me.opponent
        for (i, type) in handTypes.enumerated() {
            f[81 + i] = Float(pos.hands[me.rawValue][type.rawValue]) / 18.0
            f[88 + i] = Float(pos.hands[opp.rawValue][type.rawValue]) / 18.0
        }

        return f
    }
}
