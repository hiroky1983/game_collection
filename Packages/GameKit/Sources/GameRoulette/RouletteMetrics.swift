import CoreGraphics

/// ルーレットの操作まわりの寸法（#1318）。**View から切り出した定数**として置く。
///
/// 切り出しの理由はブラックジャック（`BlackjackMetrics`・#709）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum RouletteMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（戻す・スピン・結果まで進める・次のゲーム・同じ賭けでもう一度）の高さの下限。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget

    /// チップの額を選ぶ丸ボタンの直径。毎スピン触るので HIG の下限に置く。
    static let chipButtonSize: CGFloat = minimumTapTarget

    /// ホイールの直径（iPhone）。iPad は `AdaptiveLayout.elementScale` で相似に拡大する。
    static let wheelDiameter: CGFloat = 132

    /// 数字 1 点のマスの高さ。37 マスを 1 画面に並べるため HIG の 44pt には届かない
    /// （幅は 4 段 × 9 列で約 32pt）。隣を押しても同じ「数字 1 点」の賭けで、置いた口は
    /// 「戻す」で外せるので、誤タップの損は 1 タップで取り返せる。
    static let numberCellHeight: CGFloat = 34

    /// 12 個ずつの区分・赤黒などのマスの高さ。数字のマスより少しだけ高くして段を見分けやすくする。
    static let outsideCellHeight: CGFloat = 36

    /// マスの間隔。
    static let cellSpacing: CGFloat = 3
}
