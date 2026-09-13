import CoreGraphics

/// ブラックジャックの操作まわりの寸法。**View から切り出した定数**として置く。
///
/// 切り出しの理由はポーカー（`PokerMetrics`・#207）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum BlackjackMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 操作ボタン（ベット・ヒット・スタンド・ダブルダウン・スプリット・次のゲーム・結果まで進める）の
    /// 高さの下限（#709）。
    ///
    /// もとは本文 14pt + 上下 10pt の余白しか無く、高さは約 37pt で HIG を下回っていた。
    /// 毎局必ず押すヒット／スタンドを含むので、ポーカー（#207）と同じ 44pt に揃える。
    /// 文字は `lineLimit(1)` + `minimumScaleFactor` で折り返さない（#189）ため、
    /// 高さを下限で固定してもボタンの背が跳ねることはない。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget
}
