import SwiftUI

/// 回転体の断面（半径 r・高さ y。単位は「マス 1 枚 = 1」、y は接地面が 0）。
typealias ChessRealProfile = [(r: CGFloat, y: CGFloat)]

enum ChessRealProfiles {
    /// 駒の全高（マス比）。接地から頂点まで。
    static func height(_ t: ChessPieceType) -> CGFloat {
        switch t {
        case .pawn: return 0.60
        case .knight: return 0.82
        case .rook: return 0.68
        case .bishop: return 0.815
        case .queen: return 0.88
        case .king: return 0.97
        }
    }

    private static let plinth: ChessRealProfile = [
        (0, 0), (0.33, 0), (0.35, 0.02), (0.35, 0.05), (0.31, 0.075), (0.25, 0.092),
    ]

    /// ナイトは台座だけ回転体（馬は別途、押し出し／面分割で作る）。
    static func knightBase() -> ChessRealProfile {
        plinth + [(0.26, 0.115), (0.24, 0.12), (0, 0.12)]
    }

    static func profile(_ t: ChessPieceType) -> ChessRealProfile {
        switch t {
        case .pawn:
            return plinth + [
                (0.27, 0.135), (0.22, 0.15), (0.14, 0.20), (0.11, 0.28), (0.10, 0.34),
                (0.16, 0.365), (0.16, 0.385), (0.12, 0.40), (0.15, 0.44), (0.16, 0.48),
                (0.14, 0.53), (0.10, 0.57), (0.05, 0.595), (0, 0.60),
            ]
        case .rook:
            return plinth + [
                (0.27, 0.12), (0.22, 0.15), (0.20, 0.20), (0.19, 0.40), (0.21, 0.44),
                (0.27, 0.47), (0.28, 0.50), (0.28, 0.60), (0.24, 0.60), (0, 0.60),
            ]
        case .bishop:
            return plinth + [
                (0.26, 0.12), (0.20, 0.15), (0.12, 0.22), (0.11, 0.28), (0.09, 0.36),
                (0.15, 0.39), (0.16, 0.41), (0.10, 0.43), (0.12, 0.47), (0.19, 0.53),
                (0.20, 0.60), (0.16, 0.68), (0.09, 0.74), (0.04, 0.75), (0.07, 0.765),
                (0.07, 0.79), (0.045, 0.81), (0, 0.815),
            ]
        case .queen:
            return plinth + [
                (0.27, 0.12), (0.22, 0.15), (0.12, 0.24), (0.10, 0.36), (0.17, 0.40),
                (0.17, 0.43), (0.11, 0.45), (0.14, 0.52), (0.19, 0.60), (0.22, 0.68),
                (0.26, 0.75), (0.27, 0.78), (0.23, 0.78), (0.10, 0.76), (0, 0.76),
            ]
        case .king:
            return plinth + [
                (0.27, 0.12), (0.22, 0.15), (0.12, 0.24), (0.10, 0.36), (0.17, 0.40),
                (0.17, 0.43), (0.11, 0.45), (0.14, 0.52), (0.19, 0.60), (0.20, 0.68),
                (0.22, 0.74), (0.21, 0.77), (0.14, 0.80), (0.08, 0.84), (0, 0.85),
            ]
        case .knight:
            return knightBase()
        }
    }

    /// 種類ごとに滑らかにした断面。描画のたびに刻み直さない。
    static func smoothed(_ t: ChessPieceType) -> ChessRealProfile { cache[t] ?? [] }

    private static let cache: [ChessPieceType: ChessRealProfile] =
        Dictionary(uniqueKeysWithValues: ChessPieceType.allCases.map { ($0, smooth(profile($0))) })

    /// Chaikin の角切りで滑らかにする（端点は保つ）。角が面取りされて、削り出した駒の丸みになる。
    static func smooth(_ p: ChessRealProfile, iterations: Int = 3) -> ChessRealProfile {
        var cur = p
        for _ in 0..<iterations {
            var next: ChessRealProfile = [cur[0]]
            for i in 0..<(cur.count - 1) {
                let a = cur[i], b = cur[i + 1]
                next.append((0.75 * a.r + 0.25 * b.r, 0.75 * a.y + 0.25 * b.y))
                next.append((0.25 * a.r + 0.75 * b.r, 0.25 * a.y + 0.75 * b.y))
            }
            next.append(cur[cur.count - 1])
            cur = next
        }
        return cur
    }

    /// ナイトの横顔（`ChessKnightShape` の単位矩形座標）→ マス座標への写像。
    /// 戻り値は (x のずれ, y 高さ)。y は接地が 0。
    static func knightMap(_ px: CGFloat, _ py: CGFloat) -> (CGFloat, CGFloat) {
        ((px - 0.485) * 0.96, 0.10 + (0.81 - py) / 0.74 * 0.72)
    }
}
