import CoreGraphics
import Core

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

    /// 帯の拡大トグルの一辺。実寸は共通の `BoardToggleButton`（Core・#641）が持つので、
    /// 帯の高さの見積りがそこからずれないよう同じ値を参照する。
    static let toggleButtonMinSide: CGFloat = BoardToggleMetrics.minSide

    /// 帯の拡大トグルに「拡大／全体」の文字を出せる帯の幅の下限。iPhone SE（帯 343pt）では
    /// 文字を付けると左の「残り」「ミス」が潰れ、iPhone 17 Pro Max（361pt）では収まる（実測 2026-09-13）。
    static let zoomTitleMinStatusBarWidth: CGFloat = 350

    /// 帯の幅 `statusBarWidth` で拡大トグルに文字を出すか。未計測（0）は出す側に倒す。
    static func showsZoomTitle(statusBarWidth: CGFloat) -> Bool {
        statusBarWidth <= 0 || statusBarWidth >= zoomTitleMinStatusBarWidth
    }

    /// 帯の幅 `statusBarWidth` で「残り」「ミス」にアイコンを付けるか（#775）。未計測（0）は付ける側に倒す。
    ///
    /// iPhone SE（帯 343pt）では拡大トグルの文字を省いても、時計が「11:05」と 2 桁分になると
    /// 「残り…」「ミス…」に潰れた（`minimumScaleFactor(0.7)` は文字しか縮めず、アイコンと間隔は残る）。
    /// 右の時計・トグルは既に中身の幅しか取っていないので、左に幅を返せるのはアイコンだけ。
    /// 境目は拡大トグルの文字と同じ（文字を省く幅ではアイコンも省く）。
    static func showsStatusIcons(statusBarWidth: CGFloat) -> Bool {
        showsZoomTitle(statusBarWidth: statusBarWidth)
    }

    /// 拡大モードでの 1 マスの一辺。
    ///
    /// **9 列 × 44pt = 396pt は、iPhone SE (3rd gen) の画面幅 375pt にも
    /// iPhone 17 Pro の 402pt（左右余白 16pt ずつを引くと 370pt）にも入らない**。
    /// つまり画面幅に収める描き方のままでは 1 マスを 44pt にできないため、
    /// マインスイーパー（#203）と同じく**拡大モードを用意してそちらで 44pt を満たす**。
    /// 既定の等倍表示は盤全体を一望できることを優先する。
    static let zoomedCellSide: CGFloat = minimumTapTarget

    /// 拡大モードでの 1 マスの一辺（画面幅を見て決める版・#458）。
    ///
    /// 上の 44pt は「iPhone では等倍の盤が 44pt に届かない」ことから来た**下限**であって、
    /// 目標値ではない。iPad では等倍の盤のほうが 44pt より大きくなるため、44pt へ**切り下げると
    /// 拡大モードが縮小モードになる**。麻雀ソリティアの `comfortableTileWidth` と同じ手当てで、
    /// 等倍で入る大きさを下回らせない。
    static func zoomedCellSide(availableWidth: CGFloat) -> CGFloat {
        max(zoomedCellSide, availableWidth / CGFloat(boardSize))
    }

    /// 盤の一辺のマス数。`SudokuEngine.size` と同じ値だが、寸法計算をロジックから独立させるため再掲する。
    static let boardSize = 9

    /// 数字パッドの 1 行あたりのボタン数。
    ///
    /// 1〜9 と消しゴムの 10 個を 2 段に割る。10 個を 1 段に並べると
    /// iPhone SE では 1 個 37pt 台になり、上の最小タップ標的を割る。
    static let padColumns = 5

    /// ステータスバーの上下の余白。44pt のトグルが帯の高さを決めるぶん詰める（#203 と同じ手当て）。
    static let statusBarVerticalPadding: CGFloat = 4

    /// 3×3 ブロックの区切り線の太さ。
    static let blockBorderWidth: CGFloat = 2

    /// 直線で引く 3×3 ブロックの区切り線の位置（左上から何ブロック目か）。
    ///
    /// **外周（0 と 3）は含めない**（会長QA #595-1）。盤は角丸で切り抜かれているので、
    /// 端に直線を置くと 4 隅で線が切れて枠が消えて見える。外周は切り抜きと同じ角丸の
    /// `strokeBorder` で描く。ここに 0 や 3 が戻ると隅の欠けが再発する。
    static let innerBlockLineIndices = [1, 2]
    /// マスどうしの区切り線の太さ。
    static let cellBorderWidth: CGFloat = 0.5

    /// 数字が入る演出の長さ（秒）。Reduce Motion では `gameAnimation` が自動で止める。
    static let fillDuration: Double = 0.14

    /// 行・列・ブロックが揃ったマスを光らせておく長さ（秒・#666）。このあと `unitFlashFadeDuration` で消える。
    /// フェードと合わせて Issue の「0.25 秒ハイライト」に収める（`SudokuFeedbackTests` が縛る）。
    static let unitFlashHoldDuration: Double = 0.1
    /// 揃ったマスの光が消える演出の長さ（秒）。Reduce Motion では `withGameAnimation` が即時に落とす。
    static let unitFlashFadeDuration: Double = 0.15
    /// 誤答のマスが揺れる演出の長さ（秒・#666）。五目並べの無効タップの揺れ（#202）と同じ長さにそろえる。
    static let mistakeShakeDuration: Double = 0.32
    /// 使い切った数字を数字パッドで薄くするときの不透明度（#666）。灰色の文字色に重ねて、押す必要が無いことを示す。
    static let exhaustedDigitOpacity: Double = 0.35
}
