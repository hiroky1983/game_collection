import CoreGraphics
import Foundation

/// スワイプを「何マスぶんの操作か」に翻訳する幾何計算（会長指示 2026-09-17: 左右ボタンは置かない）。
///
/// View から切り出してあるのは、**指の移動量とマスの対応**がこのゲームの操作感をそのまま決めるため。
/// ここが狂うと「1 回のスワイプで 2 マス飛ぶ」「押しても動かない」になるので、シミュレータを
/// 起動せずに数値で固定できるようにしている。
public enum OjisanPuzzleDrag {
    /// これ以下の指の移動はタップ（＝回す）とみなす。
    public static let tapSlack: CGFloat = 12

    /// 1 本のドラッグが受け持つ向き。
    public enum Axis: Sendable, Equatable {
        case horizontal
        case vertical
    }

    /// 向きを決めるのに、優勢な側が劣勢な側の何倍以上動いている必要があるか。接戦のうちは決めない。
    public static let axisDominance: CGFloat = 1.5

    /// ドラッグの向きを決める。タップの遊び（`tapSlack`）を超え、かつ片方がはっきり優勢になるまでは決めない。
    ///
    /// **下へ素早く払うと指は必ず横にも流れる**。向きを決めずに両方拾うと、着地の直前に荷物が横へずれる（#2063）。
    /// 決めたら指を離すまで変えない（View 側が控える）。縦は下向きのときだけ決める（上スワイプには何も割り当てて
    /// いないので、最初に上へ動いたせいで、そのあとの横移動を捨てない）。
    public static func axis(for translation: CGSize) -> Axis? {
        let width = abs(translation.width)
        let height = abs(translation.height)
        if width >= tapSlack, width >= height * axisDominance { return .horizontal }
        if translation.height >= tapSlack, translation.height >= width * axisDominance { return .vertical }
        return nil
    }

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

    /// 「速く払った」とみなす最小の移動距離（pt）。1 マスずつ刻むつもりの下スワイプを誤判定しない長さ。
    public static let flickMinDistance: CGFloat = 80
    /// 「速く払った」とみなす最小の速さ（pt/秒）。指を止めずに払うと 1000 を超え、狙って刻むと 300 前後に収まる。
    public static let flickMinSpeed: CGFloat = 700

    /// 下へ払う動きが「一気に落とす」速さか。`elapsed` は触れてからの秒数（平均の速さで見る）。
    public static func isFlickDown(distance: CGFloat, elapsed: TimeInterval) -> Bool {
        guard distance.isFinite, elapsed.isFinite, elapsed > 0, distance >= flickMinDistance else { return false }
        return distance / CGFloat(elapsed) >= flickMinSpeed
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
