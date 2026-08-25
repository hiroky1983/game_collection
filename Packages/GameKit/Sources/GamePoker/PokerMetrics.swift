import CoreGraphics

/// ポーカーの操作まわりの寸法。**View から切り出した定数**として置く。
///
/// 切り出しの理由は麻雀ソリティア（`MahjongSolitaireBoardMetrics`）・マインスイーパ
/// （`MinesweeperMetrics`）と同じで、ここが「押しにくい」の急所だから。
/// 値が縮んだらテストで気づけるようにする。
enum PokerMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// アクションボタン（チェック・ベット・フォールド・コール・交換・次のゲーム）の高さの下限（#207）。
    ///
    /// もとは本文 14pt + 上下 10pt の余白しか無く、実測の高さは 34〜37pt で HIG を下回っていた。
    /// ポーカーで最も頻繁に押す操作なので、他ゲームの手当て（#196/#197/#199）と同じ 44pt に揃える。
    /// 文字は `lineLimit(1)` + `minimumScaleFactor` で折り返さない（#189）ため、
    /// 高さを下限で固定してもボタンの背が跳ねることはない。
    static let actionButtonMinHeight: CGFloat = minimumTapTarget
}
