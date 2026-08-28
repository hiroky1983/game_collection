import CoreGraphics

/// 盤面の大きさと牌の置き場所の計算。**状態を持たない純粋関数**として View から切り出してある。
///
/// 切り出しの理由は、ここが「牌が小さすぎて押せない」の急所だから（#196）。
/// 亀型レイアウトは横 15.56 枚ぶんあるため、Apple HIG の最小タップ標的 44pt を牌の幅に取ると
/// 盤面の幅は **684.6pt** 必要になる。iPhone は最大でも 440pt 程度なので、
/// **「盤面全体が 1 画面に収まる」と「牌が 44pt ある」は同時に成り立たない**。
/// そこで大きさを 2 段階持ち、既定を「操作しやすい方」にしたうえで全体表示へ 1 タップで戻れるようにする。
enum MahjongSolitaireBoardMetrics {

    /// Apple HIG の最小タップ標的。牌の**幅**をこれ以上にする（高さは縦横比のぶんさらに大きくなる）。
    static let minimumTapTarget: CGFloat = 44

    /// 表示切り替え（全体表示 ⇄ 拡大）ボタンの一辺の下限（#197）。
    ///
    /// 全体像を取り戻す唯一の入口がこのボタンなので、牌と同じく 44pt を下回らせない。
    /// 実測 29×23pt だったものをここに集約し、値が縮んだらテストで気づけるようにする。
    static let toggleButtonMinSide: CGFloat = minimumTapTarget

    /// 盤の下の操作ボタン（ヒント・並べ替え）の高さの下限（#199）。
    ///
    /// `Capsule` + 上下 6pt の余白しか無く、実測の高さは約 29pt で Apple HIG を下回っていた。
    /// 表示切り替えボタン（#197）と同じく牌と同じ基準に揃える。
    /// 操作カードが高くなるぶんは `controlArea` のひな形（リザルト + レコメンドカード ≒ 109pt）が
    /// 吸収するため、盤面に配る高さは変わらない。
    static let controlButtonMinHeight: CGFloat = minimumTapTarget

    /// 牌の増減・枠色の変化に掛ける演出の長さ（秒・#199）。
    ///
    /// 盤面の `.gameAnimation` と、最後の 1 組を消しきってからクリア表示へ切り替える待ち時間の
    /// **両方がこの値を使う**。片方だけ変えると、最後の 2 枚が消える前に盤面が差し替わる
    /// （または消えた後に間が空く）ため、定数を 1 つにして必ず連動させる。
    static let boardAnimationDuration: Double = 0.2

    /// ステータスバーの上下の余白（#197）。
    ///
    /// 44pt のボタンをそのまま置くと帯が高くなり、#148 で捻出した盤面の高さを食う。
    /// ボタンが帯の高さを決めるようになったぶん余白を詰め、帯の高さをほぼ据え置きにする。
    static let statusBarVerticalPadding: CGFloat = 4

    /// 牌の縦横比（実物の牌に近い縦長）。
    static let tileAspect: CGFloat = 1.40

    /// 1 段上がるごとに右上へずらす量（牌の幅に対する比）。積み上がりを見せるための奥行き。
    static let layerShift: CGFloat = 0.14

    /// 牌の幅を 1 として、盤面全体が何枚分の広さになるか。**レイアウトごとに違う**（#239）。
    static func canvasWidthInTiles(layout: MahjongSolitaireLayout) -> CGFloat {
        CGFloat(layout.halfWidth) / 2 + CGFloat(layout.topLayer) * layerShift
    }

    /// 牌の**高さ**を 1 として、盤面全体が何枚分の高さになるか。
    static func canvasHeightInTiles(layout: MahjongSolitaireLayout) -> CGFloat {
        CGFloat(layout.halfHeight) / 2 + CGFloat(layout.topLayer) * layerShift
    }

    /// 盤面全体がちょうど収まる牌の幅（全体表示）。
    static func fittingTileWidth(in size: CGSize, layout: MahjongSolitaireLayout) -> CGFloat {
        let byWidth = size.width / canvasWidthInTiles(layout: layout)
        let byHeight = size.height / (canvasHeightInTiles(layout: layout) * tileAspect)
        return max(1, min(byWidth, byHeight))
    }

    /// 操作しやすい牌の幅（既定表示）。44pt を下回らせない。
    ///
    /// 画面が広くて全体表示の方が大きくなる場合（iPad 等）は全体表示に合わせる。
    /// 44pt へ**切り下げる**と拡大表示のはずが縮小になってしまうため。
    static func comfortableTileWidth(in size: CGSize, layout: MahjongSolitaireLayout) -> CGFloat {
        max(minimumTapTarget, fittingTileWidth(in: size, layout: layout))
    }

    /// 牌の幅から盤面全体の大きさ。
    static func canvasSize(tileWidth: CGFloat, layout: MahjongSolitaireLayout) -> CGSize {
        CGSize(
            width: tileWidth * canvasWidthInTiles(layout: layout),
            height: tileWidth * tileAspect * canvasHeightInTiles(layout: layout)
        )
    }

    /// 盤面の左上を原点としたときの、その位置の牌の矩形。**これがそのままタップ標的になる**。
    static func tileFrame(index: Int, tileWidth: CGFloat, layout: MahjongSolitaireLayout) -> CGRect {
        let position = layout.positions[index]
        let tileHeight = tileWidth * tileAspect
        let depth = CGFloat(position.layer)
        let top = CGFloat(layout.topLayer)
        return CGRect(
            x: CGFloat(position.hx) / 2 * tileWidth + depth * layerShift * tileWidth,
            y: CGFloat(position.hy) / 2 * tileHeight + (top - depth) * layerShift * tileHeight,
            width: tileWidth,
            height: tileHeight
        )
    }
}
