import CoreGraphics

/// 碁盤の余白と交点の間隔。View（タップの座標変換・読み上げの格子）と `GoBoardCanvas`（描画）が
/// 同じ値を使うよう、純関数としてここに置く（テストで縛れる）。
///
/// 余白は以前 18pt 固定だったが、9 路盤では交点の間隔が 40pt 前後になり石の半径（間隔の 0.47 倍）が
/// 19pt を超えて、縁の石が盤の角丸（`Theme.corner` = 20）からはみ出していた（会長 QA 2026-09-13）。
/// 余白を**間隔に比例**させ（実物の碁盤も外周は半目ほど広い）、小さい盤ほど広く取る。
enum GoBoardMetrics {
    /// 余白の下限（13 路以上はこちらが効く。19 路でも石は半径 9pt ほどなので十分）。
    static let minPad: CGFloat = 18
    /// 余白 ÷ 交点の間隔。石の半径 0.47 + 落ち影（ぼかし 0.09 + ずれ 0.07）= 0.63 を覆い、ぼかしの裾の分だけ余裕を持たせる。
    static let padRatio: CGFloat = 0.7
    /// 石の半径 ÷ 交点の間隔（`GoBoardCanvas` と共有）。
    static let stoneRadiusRatio: CGFloat = 0.47
    /// 落ち影が石の外へ出る量 ÷ 交点の間隔（ぼかし半径 0.09 + 下向きのずれ 0.07）。
    static let shadowReachRatio: CGFloat = 0.16

    /// 盤の一辺 `boardWidth` に `size` 路の格子を置くときの余白。
    /// 余白 = 間隔 × `padRatio` を満たす間隔は `boardWidth / (size - 1 + 2 × padRatio)`。
    static func pad(boardWidth: CGFloat, size: Int) -> CGFloat {
        let lines = CGFloat(max(1, size - 1))
        let proportional = boardWidth * padRatio / (lines + 2 * padRatio)
        return max(minPad, proportional)
    }

    /// 交点の間隔。
    static func spacing(boardWidth: CGFloat, size: Int) -> CGFloat {
        (boardWidth - pad(boardWidth: boardWidth, size: size) * 2) / CGFloat(max(1, size - 1))
    }
}
