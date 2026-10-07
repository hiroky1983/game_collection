import CoreGraphics

/// スワイプを「何マスぶんの操作か」に翻訳する幾何計算（会長指示 2026-09-17: 左右ボタンは置かない）。
///
/// View から切り出してあるのは、**指の移動量とマスの対応**がこのゲームの操作感をそのまま決めるため。
/// ここが狂うと「1 回のスワイプで 2 マス飛ぶ」「押しても動かない」になるので、シミュレータを
/// 起動せずに数値で固定できるようにしている（`BlockPuzzleDrop` と同じ考え方）。
public enum OjisanPuzzleDrag {
    /// これ以下の指の移動はタップ（＝回す）とみなす。
    public static let tapSlack: CGFloat = 12

    /// 指の移動量が何マスぶんか。`step` は 1 マスぶんの距離。
    ///
    /// 端数は切り捨てる（半マスぶん動かしただけでは動かさない）。左が負・右が正。
    public static func steps(_ distance: CGFloat, step: CGFloat) -> Int {
        guard step > 0, distance.isFinite else { return 0 }
        return Int(distance / step)
    }

    /// 下方向に何マスぶん落とすか。上へのスワイプには何も割り当てないので 0 で止める。
    public static func downSteps(_ distance: CGFloat, step: CGFloat) -> Int {
        max(0, steps(distance, step: step))
    }

    /// 指を離したときに、それがタップ（＝回す）だったか。
    ///
    /// 1 マスでも動かしていたらタップではない。**移動量だけで見ると、ゆっくり 1 マス動かして
    /// 指を戻した操作がタップに化ける**ので、実際に動かしたマス数も一緒に見る。
    public static func isTap(translation: CGSize, movedColumns: Int, movedRows: Int) -> Bool {
        guard movedColumns == 0, movedRows == 0 else { return false }
        return abs(translation.width) + abs(translation.height) < tapSlack
    }
}
