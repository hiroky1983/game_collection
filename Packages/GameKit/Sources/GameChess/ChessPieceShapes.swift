import SwiftUI
import Core

/// チェスの駒（ベクター自前描画）。
///
/// **フォント（Merida 等のチェスフォント）・Unicode のチェス記号・他アプリの駒画像は使わない**
/// （#462 の権利確認。碁石・将棋駒で確立した流儀に揃える）。
///
/// 図案は複数の部品を**下から順に塗り重ねて**組む。1 つの `Path` に部品を足していくと
/// nonZero 塗りで重なりが打ち消し合って穴が開くため（#409 の教訓）、部品ごとに独立した
/// `Path` にして順に敷く。重なりの縁に出る輪郭線は、実物の駒の「くびれ」「襟」に見えるので
/// むしろ都合がよい。
///
/// 重ねる先は **`Canvas` 1 枚**にする。部品を `Shape` の View として `ZStack` に積むと、
/// 部品ごとに別々のレイアウトが走り、iOS では一部の部品だけが枠いっぱいに広がって
/// 駒が塊に潰れた（実測。macOS の `ImageRenderer` では再現しないため、コードだけでは気づけない）。
/// `Canvas` なら全部品が**同じ矩形**を基準に描かれることが式の上で保証され、
/// 32 枚ぶんの図形が 1 回の描画にまとまるので速度でも有利。
struct ChessPieceView: View {
    let piece: ChessPiece
    let size: CGFloat

    /// 輪郭線の太さ。駒が小さいときでも 1pt を切らないようにする。
    private var lineWidth: CGFloat { max(1, size * 0.022) }

    /// 輪郭の色。白駒は濃い線（明るいマスの上でも形が読める）、
    /// 黒駒は明るい線（暗いマスの上でも形が読める）にする。
    private var outline: Color {
        piece.color == .white ? ChessBoardStyle.whitePieceLine : ChessBoardStyle.blackPieceLine
    }

    private var gradientColors: [Color] {
        piece.color == .white
            ? [ChessBoardStyle.whitePieceTop, ChessBoardStyle.whitePieceBottom]
            : [ChessBoardStyle.blackPieceTop, ChessBoardStyle.blackPieceBottom]
    }

    var body: some View {
        Canvas { ctx, sz in
            let rect = CGRect(origin: .zero, size: sz)
            let fill = GraphicsContext.Shading.linearGradient(
                Gradient(colors: gradientColors),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: sz.height)
            )
            let line = GraphicsContext.Shading.color(outline)
            for part in ChessPieceArt.parts(of: piece.type) {
                let path = part.path(in: rect)
                ctx.fill(path, with: fill)
                ctx.stroke(path, with: line, lineWidth: lineWidth)
            }
            // 装飾線（ビショップの切れ込み）は塗りを持たないので線だけ引く。
            for accent in ChessPieceArt.accents(of: piece.type) {
                ctx.stroke(accent.path(in: rect), with: line, lineWidth: lineWidth)
            }
        }
        .frame(width: size * 0.88, height: size * 0.88)
        .shadow(color: .black.opacity(0.28), radius: size * 0.03, y: size * 0.02)
    }
}

/// 駒 1 種類ぶんの図案（部品の並び）。**下から順**に塗り重ねる。
///
/// 見た目のテストが `Shape` を直接呼べるよう、View から切り離してここに置く。
enum ChessPieceArt {
    /// 塗り + 輪郭で描く部品。
    static func parts(of type: ChessPieceType) -> [any Shape] {
        var list: [any Shape] = [ChessBaseShape()]
        switch type {
        case .pawn:
            list += [
                ChessCollarShape(top: 0.70, bottom: 0.81, topInset: 0.36, bottomInset: 0.29),
                ChessPawnBodyShape(),
                ChessCircleShape(cx: 0.5, cy: 0.345, r: 0.135),
            ]
        case .rook:
            list += [
                ChessCollarShape(top: 0.44, bottom: 0.81, topInset: 0.34, bottomInset: 0.27),
                ChessRectShape(x0: 0.24, y0: 0.34, x1: 0.76, y1: 0.45),
                ChessRookCrownShape(),
            ]
        case .bishop:
            list += [
                ChessCollarShape(top: 0.70, bottom: 0.81, topInset: 0.35, bottomInset: 0.29),
                ChessBishopMitreShape(),
                ChessCircleShape(cx: 0.5, cy: 0.165, r: 0.058),
            ]
        case .knight:
            list += [ChessKnightShape()]
        case .queen:
            list += [
                ChessCollarShape(top: 0.69, bottom: 0.81, topInset: 0.34, bottomInset: 0.27),
                ChessStemShape(),
                ChessRectShape(x0: 0.29, y0: 0.38, x1: 0.71, y1: 0.47),
                ChessQueenCrownShape(),
            ]
        case .king:
            list += [
                ChessCollarShape(top: 0.69, bottom: 0.81, topInset: 0.34, bottomInset: 0.27),
                ChessStemShape(),
                ChessRectShape(x0: 0.29, y0: 0.38, x1: 0.71, y1: 0.47),
                ChessKingCrownShape(),
                ChessRectShape(x0: 0.462, y0: 0.03, x1: 0.538, y1: 0.22),
                ChessRectShape(x0: 0.392, y0: 0.082, x1: 0.608, y1: 0.158),
            ]
        }
        return list
    }

    /// 塗らずに線だけを引く飾り。
    static func accents(of type: ChessPieceType) -> [any Shape] {
        type == .bishop ? [ChessBishopSlitShape()] : []
    }
}

// MARK: - 部品の図形（すべて 0..1 の正規化座標で定義し、与えられた矩形へ引き伸ばす）

/// 台座。どの駒にも共通。
struct ChessBaseShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.14, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.86))
        p.closeSubpath()
        return p
    }
}

/// 襟（台座と胴のあいだのくびれ）。上辺・下辺の幅を指定する台形。
struct ChessCollarShape: Shape {
    let top: CGFloat
    let bottom: CGFloat
    /// 上辺の左右の食い込み（0.5 で幅ゼロ）。
    let topInset: CGFloat
    let bottomInset: CGFloat

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * bottomInset, y: h * bottom))
        p.addLine(to: CGPoint(x: w * (1 - bottomInset), y: h * bottom))
        p.addLine(to: CGPoint(x: w * (1 - topInset), y: h * top))
        p.addLine(to: CGPoint(x: w * topInset, y: h * top))
        p.closeSubpath()
        return p
    }
}

/// 正規化座標の矩形。
struct ChessRectShape: Shape {
    let x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat

    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.width * x0, y: r.height * y0,
                    width: r.width * (x1 - x0), height: r.height * (y1 - y0)))
    }
}

/// ポーンの胴（下に広がる曲線）。
struct ChessPawnBodyShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.34, y: h * 0.73))
        p.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.44),
                       control: CGPoint(x: w * 0.40, y: h * 0.60))
        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.44))
        p.addQuadCurve(to: CGPoint(x: w * 0.66, y: h * 0.73),
                       control: CGPoint(x: w * 0.60, y: h * 0.60))
        p.closeSubpath()
        return p
    }
}

/// クイーン・キング共通の胴。
struct ChessStemShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.33, y: h * 0.72))
        p.addQuadCurve(to: CGPoint(x: w * 0.40, y: h * 0.42),
                       control: CGPoint(x: w * 0.39, y: h * 0.58))
        p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.42))
        p.addQuadCurve(to: CGPoint(x: w * 0.67, y: h * 0.72),
                       control: CGPoint(x: w * 0.61, y: h * 0.58))
        p.closeSubpath()
        return p
    }
}

/// ルークの銃眼（3 山）。**1 本のサブパスで彫り込む**（切り欠きを別図形にすると穴が開く）。
struct ChessRookCrownShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let top = h * 0.16, notch = h * 0.27, bottom = h * 0.35
        var p = Path()
        p.move(to: CGPoint(x: w * 0.24, y: bottom))
        p.addLine(to: CGPoint(x: w * 0.24, y: top))
        p.addLine(to: CGPoint(x: w * 0.355, y: top))
        p.addLine(to: CGPoint(x: w * 0.355, y: notch))
        p.addLine(to: CGPoint(x: w * 0.4475, y: notch))
        p.addLine(to: CGPoint(x: w * 0.4475, y: top))
        p.addLine(to: CGPoint(x: w * 0.5525, y: top))
        p.addLine(to: CGPoint(x: w * 0.5525, y: notch))
        p.addLine(to: CGPoint(x: w * 0.645, y: notch))
        p.addLine(to: CGPoint(x: w * 0.645, y: top))
        p.addLine(to: CGPoint(x: w * 0.76, y: top))
        p.addLine(to: CGPoint(x: w * 0.76, y: bottom))
        p.closeSubpath()
        return p
    }
}

/// ビショップの帽子（ミトラ）。
struct ChessBishopMitreShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.33, y: h * 0.72))
        p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.21),
                       control: CGPoint(x: w * 0.33, y: h * 0.40))
        p.addQuadCurve(to: CGPoint(x: w * 0.67, y: h * 0.72),
                       control: CGPoint(x: w * 0.67, y: h * 0.40))
        p.closeSubpath()
        return p
    }
}

/// ビショップの切れ込み（塗らずに線だけ引く）。
struct ChessBishopSlitShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.585, y: h * 0.34))
        p.addLine(to: CGPoint(x: w * 0.465, y: h * 0.50))
        return p
    }
}

/// ナイトの横顔。左を向く 1 本の輪郭。
struct ChessKnightShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.27, y: h * 0.81))
        p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.64))
        p.addQuadCurve(to: CGPoint(x: w * 0.36, y: h * 0.49),
                       control: CGPoint(x: w * 0.31, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: w * 0.23, y: h * 0.43),
                       control: CGPoint(x: w * 0.29, y: h * 0.44))
        p.addLine(to: CGPoint(x: w * 0.17, y: h * 0.41))
        p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.31))
        p.addQuadCurve(to: CGPoint(x: w * 0.41, y: h * 0.21),
                       control: CGPoint(x: w * 0.27, y: h * 0.23))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.51, y: h * 0.20))
        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.07))
        p.addQuadCurve(to: CGPoint(x: w * 0.73, y: h * 0.42),
                       control: CGPoint(x: w * 0.74, y: h * 0.20))
        p.addQuadCurve(to: CGPoint(x: w * 0.73, y: h * 0.81),
                       control: CGPoint(x: w * 0.80, y: h * 0.62))
        p.closeSubpath()
        return p
    }
}

/// クイーンの冠（5 つの峰）。
struct ChessQueenCrownShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.28, y: h * 0.44))
        for (x, y) in [
            (0.30, 0.24), (0.35, 0.37), (0.40, 0.19), (0.45, 0.34),
            (0.50, 0.14), (0.55, 0.34), (0.60, 0.19), (0.65, 0.37), (0.70, 0.24),
        ] {
            p.addLine(to: CGPoint(x: w * x, y: h * y))
        }
        p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.44))
        p.closeSubpath()
        return p
    }
}

/// キングの冠（丸いドーム。上に十字が乗る）。
struct ChessKingCrownShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.29, y: h * 0.44))
        p.addQuadCurve(to: CGPoint(x: w * 0.71, y: h * 0.44),
                       control: CGPoint(x: w * 0.50, y: h * 0.14))
        p.closeSubpath()
        return p
    }
}

// MARK: - 正規化座標に置いた円

/// 単位矩形のうち中心 (cx,cy)・半径 r の位置に置いた円。
struct ChessCircleShape: Shape {
    let cx: CGFloat, cy: CGFloat, r: CGFloat

    func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height) * r * 2
        return Path(ellipseIn: CGRect(
            x: rect.width * cx - d / 2, y: rect.height * cy - d / 2, width: d, height: d))
    }
}
