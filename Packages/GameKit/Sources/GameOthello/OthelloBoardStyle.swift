import CoreGraphics

/// オセロ盤の配色と演出の定数（#205）。**状態を持たない純粋な定数**として View から切り出す。
///
/// 切り出す理由はマインスイーパー（`MinesweeperMetrics`・#203）と同じで、
/// 「置ける場所が見えない」の急所が `Canvas` の描画コードに直書きされたままだと、
/// あとから誰かが値を戻してもシミュレータを立てるまで退行に気づけないため。
/// ここに集約すれば `OthelloBoardStyleTests` でコントラスト比として固定できる。
enum OthelloBoardStyle {

    // MARK: - 盤の配色

    /// 盤の緑地。合法手ドットのコントラストはこの色を背景として測る。
    static let boardGreen: UInt32 = 0x1C6B36

    // MARK: - 合法手ドット（#205）

    /// 合法手ドットの色。盤の緑地の上に `legalMoveDotOpacity` で重ねる。
    static let legalMoveDot: UInt32 = 0xFFFFFF

    /// 合法手ドットの不透明度。
    ///
    /// 従来は 0.38 で、盤の緑地に対するコントラスト比は **2.28:1** しかなく、
    /// WCAG 2.1 SC 1.4.11（非テキストコントラスト）の 3:1 を下回っていた。
    /// 0.62 に上げると **3.58:1** になり、置ける場所が緑地から浮き上がる。
    /// ドットの合成は sRGB 上で行う前提で見積もっている（実際の描画がリニア空間で
    /// 合成される場合は輝度がさらに上がるため、この見積もりは安全側）。
    static let legalMoveDotOpacity: Double = 0.62

    /// 合法手ドットの半径（マスの一辺に対する比）。
    ///
    /// 0.18 → 0.20 へわずかに広げて面積を約 23% 増やす。石の半径（`stoneRadiusRatio`）の
    /// 半分未満に留めているので、ドットが「小さい白石」に見えることはない。
    static let legalMoveDotRadiusRatio: CGFloat = 0.20

    /// 石の半径（マスの一辺に対する比）。合法手ドットと取り違えないための基準値でもある。
    static let stoneRadiusRatio: CGFloat = 0.43

    // MARK: - 終局演出（#205）

    /// 終局オーバーレイがフェードインしきるまでの長さ（秒）。
    ///
    /// 勝敗が瞬間表示だと「何が起きたか」を目で追えないため、`.transition(.opacity)` と
    /// 組で使う。盤の下の操作エリアの入れ替え（#148）はアニメーションさせないままなので、
    /// 決着の瞬間に盤が伸び縮みする副作用は起きない。
    static let resultOverlayFadeDuration: Double = 0.25
}
