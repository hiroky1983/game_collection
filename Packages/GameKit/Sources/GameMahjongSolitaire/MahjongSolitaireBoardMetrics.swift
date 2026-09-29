import CoreGraphics
import Core

/// 盤面の大きさと牌の置き場所の計算。**状態を持たない純粋関数**として View から切り出してある。
///
/// 切り出しの理由は、ここが「牌が小さすぎて押せない」の急所だから（#196）。
/// 亀型レイアウトは横 15 枚ぶんあるため、Apple HIG の最小タップ標的 44pt を牌の幅に取ると
/// 盤面の幅は **660pt** 必要になる。iPhone は最大でも 440pt 程度なので、
/// **「盤面全体が 1 画面に収まる」と「牌が 44pt ある」は同時に成り立たない**。
/// そこで大きさを 2 段階持ち、既定を「操作しやすい方」にしたうえで全体表示へ 1 タップで戻れるようにする。
enum MahjongSolitaireBoardMetrics {

    /// Apple HIG の最小タップ標的。牌の**幅**をこれ以上にする（高さは縦横比のぶんさらに大きくなる）。
    static let minimumTapTarget: CGFloat = 44

    /// 牌の増減・枠色の変化に掛ける演出の長さ（秒・#199）。
    ///
    /// 盤面の `.gameAnimation` と、最後の 1 組を消しきってからクリア表示へ切り替える待ち時間の
    /// **両方がこの値を使う**。片方だけ変えると、最後の 2 枚が消える前に盤面が差し替わる
    /// （または消えた後に間が空く）ため、定数を 1 つにして必ず連動させる。
    static let boardAnimationDuration: Double = 0.2

    /// 牌の縦横比（実物の牌に近い縦長）。
    static let tileAspect: CGFloat = 1.40

    /// 1 段上がるごとに右上へずらす量（牌の幅に対する比）。積み上がりを見せるための奥行き。
    static let layerShift: CGFloat = 0.14

    /// 牌が実際に占める範囲（x は牌の幅、y は牌の高さを 1 とした単位）。
    ///
    /// 盤面の枠は**牌の外接矩形そのもの**にする（会長 QA 2026-09-28）。以前は
    /// 「地の段の広さ + 最上段ぶんのずらし」を枠にしていたが、上の段は山の中ほどにしか無いため、
    /// ずらしぶんの余白が地の段の右側と上側にだけ残り、枠を中央に置いても山が左（と下）に寄って見えた。
    struct Extent {
        let minX: CGFloat
        let minY: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    /// その位置の牌の左上（`Extent` と同じ単位。枠の原点へ寄せる前の値）。
    private static func origin(of position: MahjongPosition, layout: MahjongSolitaireLayout) -> CGPoint {
        let depth = CGFloat(position.layer)
        let top = CGFloat(layout.topLayer)
        return CGPoint(
            x: CGFloat(position.hx) / 2 + depth * layerShift,
            y: CGFloat(position.hy) / 2 + (top - depth) * layerShift
        )
    }

    static func extent(layout: MahjongSolitaireLayout) -> Extent {
        let origins = layout.positions.map { origin(of: $0, layout: layout) }
        guard let first = origins.first else { return Extent(minX: 0, minY: 0, width: 1, height: 1) }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for o in origins {
            minX = min(minX, o.x); minY = min(minY, o.y)
            maxX = max(maxX, o.x); maxY = max(maxY, o.y)
        }
        return Extent(minX: minX, minY: minY, width: maxX + 1 - minX, height: maxY + 1 - minY)
    }

    /// 牌の幅を 1 として、盤面全体が何枚分の広さになるか。**レイアウトごとに違う**（#239）。
    static func canvasWidthInTiles(layout: MahjongSolitaireLayout) -> CGFloat {
        extent(layout: layout).width
    }

    /// 牌の**高さ**を 1 として、盤面全体が何枚分の高さになるか。
    static func canvasHeightInTiles(layout: MahjongSolitaireLayout) -> CGFloat {
        extent(layout: layout).height
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
        tileFrame(index: index, tileWidth: tileWidth, layout: layout, extent: extent(layout: layout))
    }

    /// 同上。盤面を描くときは `extent` を 1 度だけ求めて渡す（牌ごとに全位置を舐め直さない）。
    static func tileFrame(index: Int, tileWidth: CGFloat, layout: MahjongSolitaireLayout, extent: Extent) -> CGRect {
        let o = origin(of: layout.positions[index], layout: layout)
        let tileHeight = tileWidth * tileAspect
        return CGRect(
            x: (o.x - extent.minX) * tileWidth,
            y: (o.y - extent.minY) * tileHeight,
            width: tileWidth,
            height: tileHeight
        )
    }
}
