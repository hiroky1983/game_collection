import CoreGraphics

/// 数独の寸法。**状態を持たない純粋な定数・関数**として View から切り出す
/// （マインスイーパー `MinesweeperMetrics`・麻雀ソリティア `MahjongSolitaireBoardMetrics` と同じ理由）。
///
/// 「押しにくい」の急所がソースに散らばった数値のままだと、シミュレータを立てるまで
/// 退行に気づけない。ここに集約すればテストで固定できる。
enum SudokuMetrics {

    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 数字パッド・操作ボタンの一辺の下限。
    static let padButtonMinSide: CGFloat = minimumTapTarget

    /// 拡大モードでの 1 マスの一辺。
    ///
    /// **9 列 × 44pt = 396pt は、iPhone SE (3rd gen) の画面幅 375pt にも
    /// iPhone 17 Pro の 402pt（左右余白 16pt ずつを引くと 370pt）にも入らない**。
    /// つまり画面幅に収める描き方のままでは 1 マスを 44pt にできないため、
    /// マインスイーパー（#203）と同じく**拡大モードを用意してそちらで 44pt を満たす**。
    /// 既定の等倍表示は盤全体を一望できることを優先する。
    static let zoomedCellSide: CGFloat = minimumTapTarget

    /// 数字パッドの 1 行あたりのボタン数。
    ///
    /// 1〜9 と消しゴムの 10 個を 2 段に割る。10 個を 1 段に並べると
    /// iPhone SE では 1 個 37pt 台になり、上の最小タップ標的を割る。
    static let padColumns = 5

    /// ステータスバーの上下の余白。44pt のトグルが帯の高さを決めるぶん詰める（#203 と同じ手当て）。
    static let statusBarVerticalPadding: CGFloat = 4

    /// 3×3 ブロックの区切り線の太さ。
    static let blockBorderWidth: CGFloat = 2
    /// マスどうしの区切り線の太さ。
    static let cellBorderWidth: CGFloat = 0.5

    /// 数字が入る演出の長さ（秒）。Reduce Motion では `gameAnimation` が自動で止める。
    static let fillDuration: Double = 0.14
}
