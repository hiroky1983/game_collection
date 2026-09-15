import Foundation

/// 雲・丘の無限スクロールの折り返し（#921）。
///
/// 各タイルは「基準 x − 距離 × 視差」を全幅（間隔 × 枚数）で折り返した位置に置く。以前は
/// `[0, 全幅)` に折り返していたため、いちばん左のタイルが 0 を割って右端へ飛んだ瞬間から次の
/// タイルが 0 に来るまで、画面左に最大 1 間隔ぶんの空白が周期的にできていた（会長 QA 2026-09-15
/// 「一定座標が進むと後ろの背景の左側が消える」）。**2 間隔ぶん左へずらして** `[−2s, 全幅 − 2s)` に
/// 置けば、全幅が画面幅＋2 間隔より広い限り、左は必ず負の位置のタイルが覆い、右も画面幅を超える。
enum RunnerParallax {
    /// タイル `base`（基準 x）の画面上の x。
    static func wrappedX(base: Double, distance: Double, parallax: Double, spacing: Double, count: Int) -> Double {
        let total = spacing * Double(count)
        let raw = (base - distance * parallax).truncatingRemainder(dividingBy: total)
        let wrapped = raw < 0 ? raw + total : raw
        return wrapped - 2 * spacing
    }

    /// 左端が原点で幅 `tileWidth` のタイルを `count` 枚並べたとき、距離 `distance` で画面 `[0, width]` が
    /// 隙間なく覆われるか（テスト用の純関数）。
    static func covers(width: Double, tileWidth: Double, spacing: Double, count: Int,
                       parallax: Double, distance: Double) -> Bool {
        let xs = (0..<count)
            .map { wrappedX(base: Double($0) * spacing, distance: distance, parallax: parallax, spacing: spacing, count: count) }
            .sorted()
        var coveredTo = -Double.infinity
        var started = false
        for x in xs {
            if !started {
                if x <= 0 { started = true; coveredTo = x + tileWidth }
                continue
            }
            if x > coveredTo { break }
            coveredTo = max(coveredTo, x + tileWidth)
        }
        return started && coveredTo >= width
    }
}
