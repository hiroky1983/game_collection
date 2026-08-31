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

    /// 盤の緑地の下端（#366）。上端 `boardGreen` から下へ向けて暗くするグラデーションの終点。
    ///
    /// **`boardGreen` より必ず暗い側にしか振らない**こと。白い合法手ドットのコントラストは
    /// `boardGreen`（最も明るい上端）を背景として測っており、下端が明るくなると
    /// `OthelloBoardStyleTests` の保証が実際の盤の一部で崩れる。
    static let boardGreenDeep: UInt32 = 0x14522A

    // MARK: - 石の質感（#366）

    /// オセロの石は碁石（半球）ではなく**上面が平らな円柱**に見せる（会長フィードバック）。
    /// 上面は縦の linear グラデーション（明度差は控えめ）、その下に側面のだ円をのぞかせる。
    /// 左上ハイライトのラジアルにするとドーム（碁石）に見えるので使わない。
    static let stoneBlackFaceTop: UInt32 = 0x3C3C3C
    static let stoneBlackFaceBottom: UInt32 = 0x141414
    static let stoneBlackSide: UInt32 = 0x000000

    static let stoneWhiteFaceTop: UInt32 = 0xFFFDF2
    static let stoneWhiteFaceBottom: UInt32 = 0xE4DEC6
    static let stoneWhiteSide: UInt32 = 0xAFA98F

    /// 側面が見える高さ（石の半径に対する比）。上面と側面のだ円をこれだけ縦にずらす。
    static let stoneRimHeightRatio: CGFloat = 0.18

    /// 石の落ち影。ぼかし半径と下方向のずれはマスの一辺に対する比で持つ。
    static let stoneShadowOpacity: Double = 0.30
    static let stoneShadowRadiusRatio: CGFloat = 0.09
    static let stoneShadowOffsetRatio: CGFloat = 0.06

    /// 反転中に見せる「縁の厚み」の濃さの上限。真横（幅が最小）でこの濃さになる。
    static let flipEdgeShadeMaxOpacity: Double = 0.45

    // MARK: - 星（盤の目印・#366）

    /// 星を打つ線の交点（行・列の線番号）。実物の盤と同じく四隅から 2 マス内側。
    static let starPoints: [(row: Int, col: Int)] = [(2, 2), (2, 6), (6, 2), (6, 6)]

    /// 星の半径（マスの一辺に対する比）。合法手ドットより十分小さく、目印に徹する。
    static let starPointRadiusRatio: CGFloat = 0.07

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
