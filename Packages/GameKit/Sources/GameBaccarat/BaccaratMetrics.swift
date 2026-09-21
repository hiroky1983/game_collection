import CoreGraphics

/// バカラの操作まわりの寸法。**View から切り出した定数**として置く。
///
/// 切り出しの理由はポーカー（`PokerMetrics`・#207）・ブラックジャック（#709）と同じで、
/// ここが「押しにくい」の急所だから。値が縮んだらテストで気づけるようにする。
enum BaccaratMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（賭け先・ベット額・次のゲーム）の高さの下限。
    /// 毎局必ず押すので、ブラックジャック（#709）と同じ 44pt に揃える。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget
}
